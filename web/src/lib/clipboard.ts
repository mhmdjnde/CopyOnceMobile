import type { ClipboardItem, DevicePlatform } from "./types";

/**
 * Whether `content` looks like a URL, deciding how it is stored and shown.
 *
 * Ported from ClipboardItem.looksLikeLink in the Flutter client, and
 * deliberately just as strict: a bare word with a dot in it is not a link, and
 * only http(s) counts so a captured `javascript:` or `file:` string is never
 * presented as something safe to click.
 */
export function looksLikeLink(content: string): boolean {
  const trimmed = content.trim();
  if (!trimmed || /\s/.test(trimmed)) return false;

  try {
    const url = new URL(trimmed);
    return (
      (url.protocol === "http:" || url.protocol === "https:") &&
      url.hostname.length > 0
    );
  } catch {
    return false;
  }
}

export function isImage(item: ClipboardItem): boolean {
  return item.content_type === "image";
}

/**
 * How long until an image is reaped, in milliseconds.
 *
 * Clamped at zero: an expired-but-not-yet-swept image reads as "gone" rather
 * than showing a negative countdown.
 */
export function timeLeftMs(item: ClipboardItem): number | null {
  if (!item.expires_at) return null;
  const remaining = new Date(item.expires_at).getTime() - Date.now();
  return remaining < 0 ? 0 : remaining;
}

/** "3h left", "12m left", or "Delivered" once the relay is done. */
export function expiryLabel(item: ClipboardItem): string | null {
  const ms = timeLeftMs(item);
  if (ms === null) return null;
  if (ms === 0) return "Delivered";

  const minutes = Math.floor(ms / 60_000);
  if (minutes >= 60) return `${Math.floor(minutes / 60)}h left`;
  if (minutes >= 1) return `${minutes}m left`;
  return "Expiring";
}

export function readableSize(bytes: number | null): string {
  if (bytes === null) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** Relative time for the list, matching the app's phrasing. */
export function formatTimestamp(iso: string): string {
  const then = new Date(iso).getTime();
  const seconds = Math.floor((Date.now() - then) / 1000);

  if (seconds < 60) return "Just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3600)}h ago`;
  if (seconds < 604_800) return `${Math.floor(seconds / 86_400)}d ago`;

  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

/** The domain of a link, for the card's headline. */
export function linkDomain(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}

/**
 * Which OS this browser is running on, mapped onto the platforms the database
 * accepts.
 *
 * Falls back to linux rather than throwing: an unrecognised user agent should
 * cost an icon, not the ability to register a device.
 */
export function detectPlatform(): DevicePlatform {
  if (typeof navigator === "undefined") return "linux";

  const ua = navigator.userAgent;
  if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
  if (/Android/i.test(ua)) return "android";
  if (/Mac OS X|Macintosh/i.test(ua)) return "macos";
  if (/Windows/i.test(ua)) return "windows";
  return "linux";
}

/** A human label for this browser, shown in the device list. */
export function detectDeviceName(): string {
  if (typeof navigator === "undefined") return "Browser";

  const ua = navigator.userAgent;
  const browser = /Edg\//.test(ua)
    ? "Edge"
    : /OPR\//.test(ua)
      ? "Opera"
      : /Firefox\//.test(ua)
        ? "Firefox"
        : /Chrome\//.test(ua)
          ? "Chrome"
          : /Safari\//.test(ua)
            ? "Safari"
            : "Browser";

  const os = /Windows/i.test(ua)
    ? "Windows"
    : /Mac OS X|Macintosh/i.test(ua)
      ? "macOS"
      : /Android/i.test(ua)
        ? "Android"
        : /iPhone|iPad|iPod/i.test(ua)
          ? "iOS"
          : "Linux";

  return `${browser} on ${os}`;
}

/**
 * This browser's stable install id.
 *
 * Kept in localStorage so the same browser keeps one row in the device list
 * across visits, the way the Flutter client uses its own install id. Clearing
 * site data produces a new device, which is the honest outcome — it is a
 * different install as far as anyone can tell.
 */
export function getInstallId(): string {
  const KEY = "copyonce.install_id";
  let id = localStorage.getItem(KEY);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(KEY, id);
  }
  return id;
}
