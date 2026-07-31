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
import { Card, cn } from "./ui";

const TYPE_BADGE = {
  text: { label: "Text", className: "bg-brand/10 text-brand" },
  link: { label: "Link", className: "bg-link/10 text-link" },
  image: { label: "Image", className: "bg-accent/15 text-accent" },
} as const;

export function ClipboardCard({
  item,
  onCopied,
  onOpenImage,
  onDeleted,
}: {
  item: ClipboardItem;
  onCopied: () => void;
  onOpenImage: () => void;
  onDeleted: (ok: boolean) => void;
}) {
  const { copyItem, deleteItem, togglePinned } = useCopyOnce();
  const [copied, setCopied] = useState(false);
  const isImage = item.content_type === "image";
  const badge = TYPE_BADGE[item.content_type];

  async function handlePrimary() {
    if (isImage) return onOpenImage();

    await copyItem(item);
    setCopied(true);
    onCopied();
    window.setTimeout(() => setCopied(false), 2000);
  }

  return (
    <Card className="p-4">
      <div className="flex items-center gap-2">
        <span
          className={cn(
            "rounded-[--radius-s] px-2 py-0.5 text-[11px] font-semibold",
            badge.className,
          )}
        >
          {badge.label}
        </span>

        {item.is_pinned && (
          <span className="text-xs text-ink-faint" title="Pinned">
            📌
          </span>
        )}

        {isImage && <ExpiryChip item={item} />}

        <div className="ml-auto flex items-center gap-1">
          {!isImage && (
            <IconButton
              label={item.is_pinned ? "Unpin" : "Pin"}
              onClick={() => void togglePinned(item)}
            >
              {item.is_pinned ? "📌" : "📍"}
            </IconButton>
          )}
          <IconButton
            label={isImage ? "Open image" : copied ? "Copied" : "Copy"}
            onClick={handlePrimary}
            active={copied}
          >
            {isImage ? "⤢" : copied ? "✓" : "⧉"}
          </IconButton>
          <IconButton
            label="Delete"
            onClick={async () => onDeleted(await deleteItem(item))}
          >
            🗑
          </IconButton>
        </div>
      </div>

      <button
        onClick={handlePrimary}
        className="mt-3 block w-full cursor-pointer text-left"
      >
        {isImage ? (
          <ImagePreview item={item} />
        ) : item.content_type === "link" ? (
          <>
            <p className="text-sm font-semibold text-link">
              {linkDomain(item.content)}
            </p>
            <p className="mt-0.5 truncate text-xs text-ink-faint">{item.content}</p>
          </>
        ) : (
          <p className="line-clamp-2 whitespace-pre-wrap break-words text-sm leading-relaxed text-ink">
            {item.content}
          </p>
        )}
      </button>

      <div className="mt-3 flex items-center gap-2 text-[11px] text-ink-faint">
        <span>{item.device_name ?? "Unknown device"}</span>
        <span aria-hidden>·</span>
        <span>{formatTimestamp(item.created_at)}</span>
      </div>
    </Card>
  );
}

function ExpiryChip({ item }: { item: ClipboardItem }) {
  const label = expiryLabel(item);
  if (!label) return null;

  return (
    <span
      className={cn(
        "rounded-[--radius-s] bg-surface px-2 py-0.5 text-[11px] font-medium",
        label === "Delivered" ? "text-success" : "text-ink-faint",
      )}
    >
      {label}
    </span>
  );
}

/**
 * The list preview of a relayed image.
 *
 * Fetches only the generated thumbnail. A list of full-resolution photos would
 * cost megabytes to scroll past, which is what the thumbnail exists to avoid.
 */
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
      <div className="flex size-14 shrink-0 items-center justify-center overflow-hidden rounded-[--radius-m] border border-divider bg-surface">
        {url ? (
          // Object URL from an authenticated download, not a remote host —
          // next/image would want a configured domain and gain nothing here.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={url} alt="" className="size-full object-cover" />
        ) : (
          <span className="text-ink-faint" aria-hidden>
            {failed ? "⊘" : "…"}
          </span>
        )}
      </div>
      <div className="min-w-0">
        <p className="truncate text-sm font-medium text-ink">{item.content}</p>
        <p className="mt-0.5 text-xs text-ink-faint">
          {readableSize(item.byte_size)} · click to open
        </p>
      </div>
    </div>
  );
}

function IconButton({
  label,
  onClick,
  active,
  children,
}: {
  label: string;
  onClick: () => void;
  active?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className={cn(
        "flex size-8 items-center justify-center rounded-[--radius-s] text-sm transition-colors",
        active ? "bg-success/15 text-success" : "bg-surface text-ink-soft hover:text-ink",
      )}
    >
      {children}
    </button>
  );
}
