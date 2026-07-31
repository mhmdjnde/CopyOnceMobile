"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useCopyOnce } from "@/lib/copyonce-provider";
import { Button, EmptyState, ErrorBanner, Spinner, cn } from "@/components/ui";
import { ClipboardCard } from "@/components/clipboard-card";
import { MediaViewer } from "@/components/media-viewer";
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
  } = useCopyOnce();

  const [filter, setFilter] = useState<Filter>("all");
  const [query, setQuery] = useState("");
  const [toast, setToast] = useState<string | null>(null);
  const [viewing, setViewing] = useState<ClipboardItem | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const say = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(null), 2600);
  }, []);

  /**
   * Ctrl+V anywhere on the page captures.
   *
   * This is the path that always works. A browser will not let a page watch the
   * clipboard in the background — no API exists, on any platform — so the user
   * pressing paste is the one moment the content is unambiguously offered to
   * us. It also handles screenshots, which is the case the phone cannot do at
   * all.
   */
  useEffect(() => {
    async function onPaste(event: ClipboardEvent) {
      // Let paste behave normally inside the search box.
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

      const imageItem = Array.from(data.items).find((i) =>
        i.type.startsWith("image/"),
      );

      if (imageItem) {
        event.preventDefault();
        const blob = imageItem.getAsFile();
        if (!blob) return;
        const extension = imageItem.type.split("/")[1] ?? "png";
        const saved = await captureImage(blob, `Pasted image.${extension}`);
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

  async function handleReadClipboard() {
    const result = await readSystemClipboard();
    say(
      result === "saved"
        ? "Saved to CopyOnce"
        : result === "empty"
          ? "Nothing new on the clipboard"
          : "Your browser will not share the clipboard on request — press Ctrl+V instead",
    );
  }

  async function handleFilePicked(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;

    const saved = await captureImage(file, file.name);
    if (saved) say("Image sent to your devices");
  }

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items.filter((item) => {
      const matchesType = filter === "all" || item.content_type === filter;
      const matchesQuery = !q || item.content.toLowerCase().includes(q);
      return matchesType && matchesQuery;
    });
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
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search clipboard…"
          aria-label="Search clipboard"
          className="w-full flex-1 rounded-[--radius-m] border border-divider bg-card px-3.5 py-2.5 text-sm text-ink placeholder:text-ink-faint focus:border-transparent focus:outline-none focus:ring-2 focus:ring-accent"
        />

        <div className="flex shrink-0 gap-2">
          <Button variant="secondary" onClick={handleReadClipboard}>
            Read clipboard
          </Button>
          <Button
            variant="primary"
            loading={isUploading}
            onClick={() => fileInput.current?.click()}
          >
            {isUploading ? "Sending…" : "Add image"}
          </Button>
          <input
            ref={fileInput}
            type="file"
            accept="image/*"
            className="sr-only"
            onChange={handleFilePicked}
            tabIndex={-1}
          />
        </div>
      </div>

      <p className="text-xs text-ink-faint">
        Press <kbd className="rounded bg-surface px-1.5 py-0.5 font-sans">Ctrl</kbd>{" "}
        + <kbd className="rounded bg-surface px-1.5 py-0.5 font-sans">V</kbd>{" "}
        anywhere on this page to save what you copied — text, a link, or a
        screenshot.
      </p>

      <div className="flex flex-wrap gap-2" role="tablist" aria-label="Filter by type">
        {FILTERS.map((f) => (
          <button
            key={f.id}
            role="tab"
            aria-selected={filter === f.id}
            onClick={() => setFilter(f.id)}
            className={cn(
              "rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors",
              filter === f.id
                ? "border-brand bg-brand text-white"
                : "border-divider bg-card text-ink-soft hover:bg-surface",
            )}
          >
            {f.label} {counts[f.id]}
          </button>
        ))}
      </div>

      {error && <ErrorBanner message={error} onDismiss={clearError} />}

      {status === "loading" && (
        <div className="flex justify-center py-20">
          <Spinner className="size-6 text-accent" />
        </div>
      )}

      {status === "error" && !items.length && (
        <EmptyState
          icon={<span aria-hidden>⚠</span>}
          title="Cannot reach your clipboard"
          body="Check your connection and try again."
          action={
            <Button variant="secondary" onClick={() => void refresh()}>
              Try again
            </Button>
          }
        />
      )}

      {status === "ready" && visible.length === 0 && (
        <EmptyState
          icon={<span aria-hidden>{filter === "image" ? "🖼" : "📋"}</span>}
          title={
            items.length
              ? "No matches"
              : filter === "image"
                ? "No images waiting"
                : "Nothing here yet"
          }
          body={
            items.length
              ? "Try a different search or filter."
              : filter === "image"
                ? "Send an image and it appears on your other devices.\nIt clears once they have it, or after 24 hours."
                : "Copy something and press Ctrl+V here —\nor copy on another device and it lands here."
          }
        />
      )}

      {visible.length > 0 && (
        <ul className="flex flex-col gap-2.5">
          {visible.map((item) => (
            <li key={item.id}>
              <ClipboardCard
                item={item}
                onCopied={() => say("Copied to clipboard")}
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
          className="fixed bottom-6 left-1/2 z-30 -translate-x-1/2 rounded-[--radius-m] bg-brand px-4 py-2.5 text-sm text-white shadow-lg"
        >
          {toast}
        </div>
      )}
    </div>
  );
}
