"use client";

import { useEffect, useState } from "react";
import { useCopyOnce } from "@/lib/copyonce-provider";
import { expiryLabel, readableSize } from "@/lib/clipboard";
import type { ClipboardItem } from "@/lib/types";
import { Button, Spinner } from "./ui";

/**
 * Full-resolution view of a relayed image, with a download.
 *
 * Opening this is what marks the image as received on this browser: the
 * original is downloaded here, and once every device has pulled it the relay
 * lets it go. So the blob is held in state and the download button reuses it
 * rather than fetching again — otherwise saving could fail on an image the
 * user is looking at.
 */
export function MediaViewer({
  item,
  onClose,
  onToast,
}: {
  item: ClipboardItem;
  onClose: () => void;
  onToast: (message: string) => void;
}) {
  const { openOriginal } = useCopyOnce();
  const [blob, setBlob] = useState<Blob | null>(null);
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    let objectUrl: string | null = null;

    void openOriginal(item).then((data) => {
      if (cancelled) return;
      if (!data) return setFailed(true);
      objectUrl = URL.createObjectURL(data);
      setBlob(data);
      setUrl(objectUrl);
    });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [item, openOriginal]);

  // Escape closes, matching every other modal on the web.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  function download() {
    if (!blob || !url) return;
    const link = document.createElement("a");
    link.href = url;
    link.download = item.content || "copyonce-image";
    link.click();
    onToast("Downloaded at full resolution");
  }

  const expiry = expiryLabel(item);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={item.content}
      className="fixed inset-0 z-40 flex flex-col bg-ink/95"
      onClick={onClose}
    >
      <div
        className="flex items-center gap-3 px-4 py-3 text-white"
        onClick={(e) => e.stopPropagation()}
      >
        <p className="min-w-0 flex-1 truncate text-sm">{item.content}</p>
        {blob && (
          <Button variant="secondary" onClick={download}>
            Download
          </Button>
        )}
        <button
          onClick={onClose}
          aria-label="Close"
          className="flex size-9 items-center justify-center rounded-[--radius-m] text-white/80 hover:bg-white/10 hover:text-white"
        >
          ✕
        </button>
      </div>

      <div
        className="flex flex-1 items-center justify-center overflow-auto p-4"
        onClick={(e) => e.stopPropagation()}
      >
        {failed ? (
          <p className="max-w-sm text-center text-sm leading-relaxed text-white/80">
            That image could not be loaded. It may have already been delivered
            to all your devices and cleared.
          </p>
        ) : url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={url}
            alt={item.content}
            className="max-h-full max-w-full object-contain"
          />
        ) : (
          <Spinner className="size-7 text-white" />
        )}
      </div>

      <div
        className="px-4 py-4 text-xs text-white/60"
        onClick={(e) => e.stopPropagation()}
      >
        <p>
          {item.device_name ?? "Unknown device"}
          {item.byte_size ? ` · ${readableSize(item.byte_size)}` : ""}
        </p>
        {expiry && (
          <p className="mt-1">
            {expiry === "Delivered"
              ? "Every device has this image now, so CopyOnce is letting it go."
              : `Clears in ${expiry.replace(" left", "")}, or as soon as your other devices have it.`}
          </p>
        )}
      </div>
    </div>
  );
}
