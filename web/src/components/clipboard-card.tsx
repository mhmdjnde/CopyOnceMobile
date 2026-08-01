"use client";

import { useEffect, useState } from "react";
import { useCopyOnce } from "@/lib/copyonce-provider";
import {
  expiryLabel,
  formatTimestamp,
  linkDomain,
  readableSize,
} from "@/lib/clipboard";
import type { ClipboardItem } from "@/lib/types";
import { cn } from "./ui";
import {
  CheckIcon,
  CopyIcon,
  ExpandIcon,
  ImageIcon,
  LinkIcon,
  PinIcon,
  TextIcon,
  TrashIcon,
} from "./icons";

/**
 * The type spine.
 *
 * A coloured edge down the left of each row, rather than a badge. It encodes
 * something true — what kind of thing this is — and reads at a glance while
 * scanning, which a badge competing with the content does not.
 */
const TYPE = {
  text: { Icon: TextIcon, label: "Text", spine: "bg-ink-faint", tint: "text-ink-soft" },
  link: { Icon: LinkIcon, label: "Link", spine: "bg-link", tint: "text-link" },
  image: { Icon: ImageIcon, label: "Image", spine: "bg-accent", tint: "text-accent" },
} as const;

export function ClipboardCard({
  item,
  isNew,
  onCopied,
  onOpenImage,
  onDeleted,
}: {
  item: ClipboardItem;
  /** Arrived from another device since this list last rendered. */
  isNew?: boolean;
  onCopied: () => void;
  onOpenImage: () => void;
  onDeleted: (ok: boolean) => void;
}) {
  const { copyItem, deleteItem, togglePinned } = useCopyOnce();
  const [copied, setCopied] = useState(false);
  const isImage = item.content_type === "image";
  const type = TYPE[item.content_type];

  async function handlePrimary() {
    if (isImage) return onOpenImage();
    await copyItem(item);
    setCopied(true);
    onCopied();
    window.setTimeout(() => setCopied(false), 1800);
  }

  return (
    <div
      className={cn(
        "group relative overflow-hidden rounded-[--radius-l] border border-divider bg-card",
        "transition-colors hover:border-ink-faint/50",
        isNew && "arrive",
      )}
    >
      <span className={cn("absolute inset-y-0 left-0 w-[3px]", type.spine)} aria-hidden />

      <div className="flex items-start gap-3 py-3 pl-4 pr-3">
        <button
          onClick={handlePrimary}
          className="min-w-0 flex-1 text-left"
          aria-label={isImage ? `Open ${item.content}` : `Copy ${type.label.toLowerCase()}`}
        >
          <div className="mb-1.5 flex items-center gap-2">
            <type.Icon size={13} className={type.tint} />
            <span className={cn("text-[11px] font-semibold uppercase tracking-wider", type.tint)}>
              {type.label}
            </span>
            {item.is_pinned && <PinIcon filled size={12} className="text-ink-faint" />}
            {isImage && <ExpiryChip item={item} />}
          </div>

          {isImage ? (
            <ImagePreview item={item} />
          ) : item.content_type === "link" ? (
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-ink">
                {linkDomain(item.content)}
              </p>
              <p className="truncate font-mono text-xs text-ink-faint">{item.content}</p>
            </div>
          ) : (
            // Mono, because copied text is usually a URL, a token, or a snippet,
            // and the whole promise is that it arrived character for character.
            <p className="line-clamp-2 whitespace-pre-wrap break-all font-mono text-[13px] leading-relaxed text-ink">
              {item.content}
            </p>
          )}
        </button>

        <div className="flex shrink-0 items-center gap-0.5">
          {!isImage && (
            <IconButton
              label={item.is_pinned ? "Unpin" : "Pin"}
              onClick={() => void togglePinned(item)}
              active={item.is_pinned}
            >
              <PinIcon filled={item.is_pinned} size={16} />
            </IconButton>
          )}
          <IconButton
            label={isImage ? "Open" : copied ? "Copied" : "Copy"}
            onClick={handlePrimary}
            active={copied}
          >
            {isImage ? <ExpandIcon size={16} /> : copied ? <CheckIcon size={16} /> : <CopyIcon size={16} />}
          </IconButton>
          <IconButton
            label="Delete"
            danger
            onClick={async () => onDeleted(await deleteItem(item))}
          >
            <TrashIcon size={16} />
          </IconButton>
        </div>
      </div>

      <div className="flex items-center gap-2 border-t border-divider/60 px-4 py-1.5 text-[11px] text-ink-faint">
        <span className="truncate">{item.device_name ?? "Unknown device"}</span>
        <span aria-hidden>·</span>
        <span>{formatTimestamp(item.created_at)}</span>
      </div>
    </div>
  );
}

function ExpiryChip({ item }: { item: ClipboardItem }) {
  const label = expiryLabel(item);
  if (!label) return null;

  return (
    <span
      className={cn(
        "rounded-full px-1.5 py-px text-[10px] font-semibold",
        label === "Delivered" ? "bg-success/15 text-success" : "bg-surface text-ink-faint",
      )}
    >
      {label}
    </span>
  );
}

function ImagePreview({ item }: { item: ClipboardItem }) {
  const { thumbnailUrl } = useCopyOnce();
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void thumbnailUrl(item).then((u) => {
      if (cancelled) return;
      if (u) setUrl(u);
      else setFailed(true);
    });
    return () => {
      cancelled = true;
    };
  }, [item, thumbnailUrl]);

  return (
    <div className="flex items-center gap-3">
      <div className="flex size-12 shrink-0 items-center justify-center overflow-hidden rounded-[--radius-m] border border-divider bg-surface">
        {url ? (
          // An object URL from an authenticated download, not a remote host —
          // next/image would need a configured domain and gain nothing.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={url} alt="" className="size-full object-cover" />
        ) : failed ? (
          <ImageIcon size={16} className="text-ink-faint" />
        ) : (
          <span className="skeleton size-full" />
        )}
      </div>
      <div className="min-w-0">
        <p className="truncate text-sm font-medium text-ink">{item.content}</p>
        <p className="text-xs text-ink-faint">{readableSize(item.byte_size)}</p>
      </div>
    </div>
  );
}

function IconButton({
  label,
  onClick,
  active,
  danger,
  children,
}: {
  label: string;
  onClick: () => void;
  active?: boolean;
  danger?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className={cn(
        "flex size-8 items-center justify-center rounded-[--radius-s] transition-colors",
        active
          ? "text-success"
          : danger
            ? "text-ink-faint hover:bg-danger/10 hover:text-danger"
            : "text-ink-faint hover:bg-surface hover:text-ink",
      )}
    >
      {children}
    </button>
  );
}
