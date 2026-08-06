"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import { useCopyOnce } from "@/lib/copyonce-provider";
import {
  Button,
  EmptyState,
  ErrorBanner,
  SkeletonList,
  cn,
} from "@/components/ui";
import { ClipboardCard } from "@/components/clipboard-card";
import { MediaViewer } from "@/components/media-viewer";
import {
  ImageIcon,
  Keycap,
  LinkIcon,
  PlusIcon,
  DownloadIcon,
  RefreshIcon,
  SearchIcon,
  TextIcon,
} from "@/components/icons";
import type { ClipboardItem, ClipboardItemType } from "@/lib/types";

type Filter = ClipboardItemType | "all";

const FILTERS: Array<{ id: Filter; label: string }> = [
  { id: "all", label: "All" },
  { id: "text", label: "Text" },
  { id: "link", label: "Links" },
  { id: "image", label: "Images" },
];

export default function ClipboardPage() {
  const {
    items,
    status,
    error,
    isUploading,
    clearError,
    refresh,
    captureText,
    captureImage,
    readSystemClipboard,
    downloadMany,
  } = useCopyOnce();

  const [filter, setFilter] = useState<Filter>("all");
  const [query, setQuery] = useState("");
  const [toast, setToast] = useState<string | null>(null);
  const [viewing, setViewing] = useState<ClipboardItem | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [batch, setBatch] = useState<{ done: number; total: number } | null>(null);

  // Selection only exists on the Images view: bulk-downloading text would be
  // meaningless, and a checkbox on every row would be clutter the rest of the
  // time.
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [saving, setSaving] = useState<{ done: number; total: number } | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  // The latest error, for the batch summary — reading `error` directly would
  // capture the value from the render that started the loop.
  const errorRef = useRef<string | null>(null);
  useEffect(() => {
    errorRef.current = error;
  }, [error]);

  // Ids present on the previous render, so arrivals can be highlighted once.
  const seen = useRef<Set<string>>(new Set());
  const [arrived, setArrived] = useState<Set<string>>(new Set());

  useEffect(() => {
    const fresh = items.filter((i) => !seen.current.has(i.id)).map((i) => i.id);
    const first = seen.current.size === 0;
    for (const item of items) seen.current.add(item.id);

    // Nothing is "new" on the first load — the whole list would flash.
    if (first || fresh.length === 0) return;
    setArrived(new Set(fresh));
    const timer = window.setTimeout(() => setArrived(new Set()), 900);
    return () => window.clearTimeout(timer);
  }, [items]);

  // A pointer that is not fine-grained means a touchscreen, and a touchscreen
  // means no Ctrl+V. Read once after mount so the server and client agree.
  const hasKeyboard = useSyncExternalStore(
    () => () => {},
    () => window.matchMedia("(pointer: fine)").matches,
    () => true,
  );
  const isApple = useSyncExternalStore(
    () => () => {},
    () => /Mac|iPhone|iPad/.test(navigator.platform ?? ""),
    () => false,
  );

  const say = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(null), 2600);
  }, []);

  /**
   * Ctrl+V anywhere on the page captures.
   *
   * The path that always works. A browser will not let a page watch the
   * clipboard in the background — no API exists, on any platform — so the
   * moment the user presses paste is the one time the content is unambiguously
   * offered. It also takes screenshots, which the phone cannot do at all.
   */
  useEffect(() => {
    async function onPaste(event: ClipboardEvent) {
      const target = event.target as HTMLElement | null;
      if (
        target &&
        (target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          target.isContentEditable)
      ) {
        return;
      }

      const data = event.clipboardData;
      if (!data) return;

      const image = Array.from(data.items).find((i) => i.type.startsWith("image/"));
      if (image) {
        event.preventDefault();
        const blob = image.getAsFile();
        if (!blob) return;
        const saved = await captureImage(blob, `Pasted image.${image.type.split("/")[1] ?? "png"}`);
        if (saved) say("Image sent to your devices");
        return;
      }

      const text = data.getData("text/plain");
      if (!text.trim()) return;
      event.preventDefault();
      const saved = await captureText(text);
      say(saved ? "Saved to CopyOnce" : "That is already at the top");
    }

    document.addEventListener("paste", onPaste);
    return () => document.removeEventListener("paste", onPaste);
  }, [captureText, captureImage, say]);

  async function handleRefresh() {
    setRefreshing(true);
    await refresh();
    setRefreshing(false);
    say("Up to date");
  }

  async function handleReadClipboard() {
    const result = await readSystemClipboard();
    say(
      result === "saved"
        ? "Saved to CopyOnce"
        : result === "empty"
          ? "Nothing new on the clipboard"
          : "Your browser will not hand over the clipboard on request — press Ctrl+V instead",
    );
  }

  async function handleFilePicked(event: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.target.files ?? []);
    event.target.value = "";
    if (files.length === 0) return;

    // Serial, not parallel: each upload puts two objects in Storage and decodes
    // a full-resolution image for its thumbnail, and a quota refusal should stop
    // the run rather than fire once per file.
    let stored = 0;
    for (const file of files) {
      const saved = await captureImage(file, file.name);
      if (!saved) break;
      stored++;
      if (files.length > 1) setBatch({ done: stored, total: files.length });
    }
    setBatch(null);

    // A batch can half-succeed — the ten-image cap is the usual reason — and
    // saying so beats a bare error or a silent partial.
    if (stored === files.length) {
      say(stored === 1 ? "Image sent to your devices" : `${stored} images sent`);
    } else if (stored === 0) {
      say(errorRef.current ?? "Could not send those images");
    } else {
      say(`${stored} of ${files.length} sent`);
    }
  }

  function toggleSelected(id: string) {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function handleDownloadSelected() {
    const chosen = items.filter((i) => selected.has(i.id));
    if (chosen.length === 0) return;

    setSaving({ done: 0, total: chosen.length });
    const saved = await downloadMany(chosen, (done, total) =>
      setSaving({ done, total }),
    );
    setSaving(null);
    setSelected(new Set());

    say(
      saved === chosen.length
        ? `${saved} ${saved === 1 ? "image" : "images"} downloaded`
        : `${saved} of ${chosen.length} downloaded`,
    );
  }

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items.filter(
      (item) =>
        (filter === "all" || item.content_type === filter) &&
        (!q || item.content.toLowerCase().includes(q)),
    );
  }, [items, filter, query]);

  const counts = useMemo(
    () => ({
      all: items.length,
      text: items.filter((i) => i.content_type === "text").length,
      link: items.filter((i) => i.content_type === "link").length,
      image: items.filter((i) => i.content_type === "image").length,
    }),
    [items],
  );

  return (
    <div className="flex flex-col gap-4 py-5">
      {/*
        The paste invitation, but only where a keyboard exists. On a phone
        browser — iOS Safari especially — there is no Ctrl+V to press, so
        showing keycaps would be instructing the user to do something
        impossible. There, the read button is the whole story.
      */}
      <div className="flex flex-wrap items-center gap-3 rounded-[--radius-l] border border-divider bg-card px-4 py-3">
        {hasKeyboard && (
          <span className="flex items-center gap-1.5">
            <Keycap label={isApple ? "\u2318" : "Ctrl"} size={26} />
            <Keycap label="V" size={26} />
          </span>
        )}
        <p className="flex-1 text-sm text-ink-soft">
          {hasKeyboard
            ? "Press paste anywhere on this page — text, a link, or a screenshot."
            : "Tap Read clipboard to save what you copied, or add an image."}
        </p>
        <div className="flex items-center gap-2">
          <Button variant="secondary" onClick={handleReadClipboard}>
            Read clipboard
          </Button>
          <Button
            variant="primary"
            loading={isUploading}
            icon={!isUploading && <PlusIcon size={16} />}
            onClick={() => fileInput.current?.click()}
          >
            {batch ? `${batch.done} of ${batch.total}` : isUploading ? "Sending…" : "Images"}
          </Button>
          <input
            ref={fileInput}
            type="file"
            accept="image/*"
            multiple
            className="sr-only"
            onChange={handleFilePicked}
            tabIndex={-1}
          />
        </div>
      </div>

      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <SearchIcon
            size={16}
            className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint"
          />
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search"
            aria-label="Search clipboard"
            className="w-full rounded-[--radius-m] border border-divider bg-card py-2.5 pl-9 pr-3.5 text-sm text-ink placeholder:text-ink-faint focus:border-transparent focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <button
          onClick={handleRefresh}
          aria-label="Refresh"
          title="Refresh"
          className="flex size-10 shrink-0 items-center justify-center rounded-[--radius-m] border border-divider bg-card text-ink-soft transition-colors hover:bg-surface hover:text-ink"
        >
          <RefreshIcon size={17} className={cn(refreshing && "animate-spin")} />
        </button>
      </div>

      <div className="flex flex-wrap gap-2" role="tablist" aria-label="Filter by type">
        {FILTERS.map((f) => (
          <button
            key={f.id}
            role="tab"
            aria-selected={filter === f.id}
            onClick={() => {
              setFilter(f.id);
              // A selection made on Images cannot be acted on anywhere else.
              if (f.id !== "image") setSelected(new Set());
            }}
            className={cn(
              "rounded-full border px-3 py-1.5 text-[13px] font-medium transition-colors",
              filter === f.id
                ? "border-transparent bg-brand text-[var(--color-on-accent)]"
                : "border-divider bg-card text-ink-soft hover:bg-surface",
            )}
          >
            {f.label}
            <span className="ml-1.5 opacity-60">{counts[f.id]}</span>
          </button>
        ))}
      </div>

      {filter === "image" && counts.image > 0 && (
        <div className="flex flex-wrap items-center gap-2 rounded-[--radius-m] border border-divider bg-card px-3 py-2">
          <span className="text-sm text-ink-soft">
            {selected.size > 0
              ? `${selected.size} selected`
              : "Select images to download several at once"}
          </span>
          <div className="ml-auto flex items-center gap-2">
            <Button
              variant="ghost"
              onClick={() =>
                setSelected(
                  selected.size === counts.image
                    ? new Set()
                    : new Set(items.filter((i) => i.content_type === "image").map((i) => i.id)),
                )
              }
            >
              {selected.size === counts.image ? "Clear" : "Select all"}
            </Button>
            <Button
              variant="primary"
              disabled={selected.size === 0}
              loading={saving !== null}
              icon={!saving && <DownloadIcon size={16} />}
              onClick={handleDownloadSelected}
            >
              {saving ? `${saving.done} of ${saving.total}` : "Download"}
            </Button>
          </div>
        </div>
      )}

      {error && <ErrorBanner message={error} onDismiss={clearError} />}

      {status === "loading" && <SkeletonList rows={4} />}

      {status === "error" && items.length === 0 && (
        <EmptyState
          icon={<RefreshIcon size={22} />}
          title="Cannot reach your clipboard"
          body="Check your connection, then try again."
          action={
            <Button variant="secondary" onClick={handleRefresh}>
              Try again
            </Button>
          }
        />
      )}

      {status === "ready" && visible.length === 0 && (
        <EmptyState
          icon={filter === "image" ? <ImageIcon size={22} /> : filter === "link" ? <LinkIcon size={22} /> : <TextIcon size={22} />}
          title={
            items.length
              ? "Nothing matches"
              : filter === "image"
                ? "No images waiting"
                : "Your clipboard is empty"
          }
          body={
            items.length ? (
              "Try a different search or filter."
            ) : filter === "image" ? (
              <>Send an image and it appears on your other devices, then clears once they have it.</>
            ) : (
              hasKeyboard ? (
                <>
                  Copy something and press <Keycap label={isApple ? "\u2318" : "Ctrl"} size={20} />{" "}
                  <Keycap label="V" size={20} /> here — or copy on your phone and it lands here.
                </>
              ) : (
                <>Tap Read clipboard to save what you copied — or copy on another device and it lands here.</>
              )
            )
          }
        />
      )}

      {visible.length > 0 && (
        <ul className="flex flex-col gap-2.5">
          {visible.map((item) => (
            <li key={item.id}>
              <ClipboardCard
                item={item}
                isNew={arrived.has(item.id)}
                selectable={filter === "image"}
                selected={selected.has(item.id)}
                onToggleSelected={() => toggleSelected(item.id)}
                onCopied={() => say("Copied")}
                onOpenImage={() => setViewing(item)}
                onDeleted={(ok) => say(ok ? "Deleted" : "Could not delete")}
              />
            </li>
          ))}
        </ul>
      )}

      {viewing && (
        <MediaViewer item={viewing} onClose={() => setViewing(null)} onToast={say} />
      )}

      {toast && (
        <div
          role="status"
          className="fixed bottom-24 left-1/2 z-30 -translate-x-1/2 rounded-full bg-brand px-4 py-2 text-sm font-medium text-[var(--color-on-accent)] shadow-lg md:bottom-8"
        >
          {toast}
        </div>
      )}
    </div>
  );
}
