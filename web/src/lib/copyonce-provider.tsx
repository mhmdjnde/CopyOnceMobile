"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { createClient } from "./supabase/client";
import { ClipboardFailure, ClipboardRepository } from "./repositories/clipboard";
import { MediaRepository } from "./repositories/media";
import {
  detectDeviceName,
  detectPlatform,
  getInstallId,
  looksLikeLink,
} from "./clipboard";
import type { ClipboardItem, DeviceRow, SyncSettings } from "./types";

type Status = "loading" | "ready" | "error";

export type ClipboardReadResult = "saved" | "empty" | "denied" | "unsupported";

interface CopyOnceValue {
  items: ClipboardItem[];
  devices: DeviceRow[];
  settings: SyncSettings | null;
  status: Status;
  error: string | null;
  isUploading: boolean;

  clearError: () => void;
  refresh: () => Promise<void>;

  captureText: (content: string) => Promise<ClipboardItem | null>;
  captureImage: (blob: Blob, filename: string) => Promise<ClipboardItem | null>;
  readSystemClipboard: () => Promise<ClipboardReadResult>;

  copyItem: (item: ClipboardItem) => Promise<void>;
  deleteItem: (item: ClipboardItem) => Promise<boolean>;
  togglePinned: (item: ClipboardItem) => Promise<void>;
  clearHistory: () => Promise<void>;

  thumbnailUrl: (item: ClipboardItem) => Promise<string | null>;
  openOriginal: (item: ClipboardItem) => Promise<Blob | null>;

  saveSettings: (patch: Partial<SyncSettings>) => Promise<void>;
  removeDevice: (id: string) => Promise<void>;
}

const CopyOnceContext = createContext<CopyOnceValue | null>(null);

export function useCopyOnce(): CopyOnceValue {
  const value = useContext(CopyOnceContext);
  if (!value) throw new Error("useCopyOnce must be used inside CopyOnceProvider");
  return value;
}

/**
 * Owns the synced clipboard for the web client: the list, capture, media, and
 * device registration.
 *
 * The web counterpart of ClipboardController in the Flutter app, keeping the
 * same division of labour — rules live here, screens stay presentational.
 */
export function CopyOnceProvider({
  userId,
  children,
}: {
  userId: string;
  children: React.ReactNode;
}) {
  const supabase = useMemo(() => createClient(), []);
  const clipboard = useMemo(() => new ClipboardRepository(supabase), [supabase]);
  const media = useMemo(() => new MediaRepository(supabase), [supabase]);

  const [items, setItems] = useState<ClipboardItem[]>([]);
  const [devices, setDevices] = useState<DeviceRow[]>([]);
  const [settings, setSettings] = useState<SyncSettings | null>(null);
  const [status, setStatus] = useState<Status>("loading");
  const [error, setError] = useState<string | null>(null);
  const [isUploading, setUploading] = useState(false);

  /** This browser's device row id, learned at registration. */
  const deviceRowId = useRef<string | null>(null);

  /**
   * The last value this browser captured or copied out.
   *
   * In memory only, and only so re-reading the clipboard does not save the same
   * thing twice. Never written to storage.
   */
  const lastSeen = useRef<string | null>(null);

  /** Latest items, for callbacks that must not re-create on every list change. */
  const itemsRef = useRef<ClipboardItem[]>([]);
  useEffect(() => {
    itemsRef.current = items;
  }, [items]);

  const settingsRef = useRef<SyncSettings | null>(null);
  useEffect(() => {
    settingsRef.current = settings;
  }, [settings]);

  const report = useCallback((e: unknown) => {
    setError(
      e instanceof ClipboardFailure
        ? e.message
        : "Something went wrong. Please try again.",
    );
  }, []);

  const refresh = useCallback(async () => {
    try {
      setItems(await clipboard.fetchItems());
      setStatus("ready");
      setError(null);
    } catch (e) {
      report(e);
      setStatus("error");
    }
  }, [clipboard, report]);

  // ── Startup ────────────────────────────────────────────────────────────────
  useEffect(() => {
    let cancelled = false;

    void (async () => {
      // Retention first, so expired items never flash up before being removed.
      try {
        await clipboard.pruneExpired();
      } catch {
        // Not fatal — the list still loads.
      }
      try {
        await media.reapExpired();
      } catch {
        // Best effort. The scheduled reaper collects what this misses, and on a
        // backend without the media migration applied this always fails.
      }

      if (cancelled) return;
      await refresh();

      try {
        const id = await clipboard.registerDevice({
          installId: getInstallId(),
          name: detectDeviceName(),
          platform: detectPlatform(),
        });
        if (cancelled) return;
        deviceRowId.current = id;
        setDevices(await clipboard.fetchDevices());
      } catch {
        // A missing device row costs a label, not the feature.
      }

      try {
        const loaded = await clipboard.loadSettings();
        if (!cancelled) setSettings(loaded);
      } catch {
        // Defaults are fine.
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [clipboard, media, refresh]);

  // ── Realtime ───────────────────────────────────────────────────────────────
  useEffect(() => {
    const channel = clipboard.watchItems(userId, () => {
      // The payload carries the changed row, but a refetch keeps ordering and
      // the pinned-first rule in one place rather than duplicating them here.
      void refresh();
    });

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [clipboard, supabase, userId, refresh]);

  // Release object URLs when the provider unmounts.
  useEffect(() => () => media.releaseAll(), [media]);

  // ── Capture ────────────────────────────────────────────────────────────────

  const captureText = useCallback(
    async (content: string) => {
      const trimmed = content.trim();
      if (!trimmed) return null;
      if (trimmed === lastSeen.current) return null;

      const isLink = looksLikeLink(trimmed);
      const s = settingsRef.current;
      if (s && ((isLink && !s.capture_links) || (!isLink && !s.capture_text))) {
        // Remembered anyway, so a filtered value is not re-examined every time.
        lastSeen.current = trimmed;
        return null;
      }

      try {
        const saved = await clipboard.addItem({
          content: trimmed,
          type: isLink ? "link" : "text",
          deviceId: getInstallId(),
          deviceName: detectDeviceName(),
          devicePlatform: detectPlatform(),
          newestContent: itemsRef.current[0]?.content ?? null,
        });
        lastSeen.current = trimmed;
        if (saved) {
          setItems((current) => [saved, ...current]);
          setError(null);
        }
        return saved;
      } catch (e) {
        report(e);
        return null;
      }
    },
    [clipboard, report],
  );

  const captureImage = useCallback(
    async (blob: Blob, filename: string) => {
      if (isUploading) return null;
      setUploading(true);
      setError(null);

      try {
        const saved = await media.upload({
          blob,
          filename,
          deviceId: getInstallId(),
          deviceName: detectDeviceName(),
          devicePlatform: detectPlatform(),
        });

        // This browser holds the original already — it is the one that sent it.
        // Recording that now is what lets a single-device account reap straight
        // away instead of waiting out the whole 24 hours.
        if (deviceRowId.current) {
          try {
            await media.markDelivered(saved.id, deviceRowId.current);
          } catch {
            // A lost receipt only delays deletion to the backstop.
          }
        }

        setItems((current) => [saved, ...current]);
        return saved;
      } catch (e) {
        report(e);
        return null;
      } finally {
        setUploading(false);
      }
    },
    [media, isUploading, report],
  );

  /**
   * Pulls whatever is on the system clipboard right now.
   *
   * Browsers will not let a page watch the clipboard in the background, so this
   * needs a deliberate action — a button, or returning to the tab where the
   * browser allows it. Ctrl+V is handled separately and is the path that always
   * works.
   */
  const readSystemClipboard = useCallback(async (): Promise<ClipboardReadResult> => {
    if (typeof navigator === "undefined" || !navigator.clipboard?.read) {
      return "unsupported";
    }

    try {
      const contents = await navigator.clipboard.read();

      for (const entry of contents) {
        const imageType = entry.types.find((t) => t.startsWith("image/"));
        if (imageType) {
          const blob = await entry.getType(imageType);
          const saved = await captureImage(
            blob,
            `Pasted image.${imageType.split("/")[1] ?? "png"}`,
          );
          return saved ? "saved" : "empty";
        }
        if (entry.types.includes("text/plain")) {
          const text = await (await entry.getType("text/plain")).text();
          const saved = await captureText(text);
          return saved ? "saved" : "empty";
        }
      }
      return "empty";
    } catch {
      // Firefox has no read() at all, and Chrome throws when permission is
      // refused or the document is not focused. To the user it all means the
      // same thing: press Ctrl+V instead.
      return "denied";
    }
  }, [captureText, captureImage]);

  // ── Item actions ───────────────────────────────────────────────────────────

  const copyItem = useCallback(async (item: ClipboardItem) => {
    await navigator.clipboard.writeText(item.content);
    // Remembered so the next clipboard read does not treat our own paste as a
    // fresh capture and duplicate the row.
    lastSeen.current = item.content;
  }, []);

  const deleteItem = useCallback(
    async (item: ClipboardItem) => {
      const previous = itemsRef.current;
      setItems((current) => current.filter((i) => i.id !== item.id));

      try {
        // Files before the row, the same order the reaper uses.
        if (item.content_type === "image") await media.deleteFiles(item);
        await clipboard.deleteItem(item.id);
        return true;
      } catch (e) {
        setItems(previous);
        report(e);
        return false;
      }
    },
    [clipboard, media, report],
  );

  const togglePinned = useCallback(
    async (item: ClipboardItem) => {
      try {
        await clipboard.setPinned(item.id, !item.is_pinned);
        await refresh();
      } catch (e) {
        report(e);
      }
    },
    [clipboard, refresh, report],
  );

  const clearHistory = useCallback(async () => {
    try {
      await clipboard.clearHistory();
      setItems([]);
      setError(null);
    } catch (e) {
      report(e);
    }
  }, [clipboard, report]);

  // ── Media reads ────────────────────────────────────────────────────────────

  const thumbnailUrl = useCallback(
    (item: ClipboardItem) => media.thumbnailUrl(item),
    [media],
  );

  /**
   * The full-resolution original — and the moment this browser counts as having
   * received it.
   *
   * If that receipt completes the set, the image is deleted here rather than at
   * the next page load. The database collapses the expiry when the last device
   * reports in, but something still has to do the deleting, and the client
   * holding the final copy is right here. The 24-hour backstop is unchanged and
   * still covers devices that never come back.
   */
  const openOriginal = useCallback(
    async (item: ClipboardItem) => {
      try {
        const blob = await media.original(item);
        if (deviceRowId.current) {
          try {
            await media.markDelivered(item.id, deviceRowId.current);
            // Cheap when nothing is due: the reaper asks for expired rows and
            // gets an empty list back.
            const removed = await media.reapExpired();
            if (removed > 0) await refresh();
          } catch {
            // Silent by design: a lost receipt only delays deletion to the
            // backstop.
          }
        }
        return blob;
      } catch (e) {
        report(e);
        return null;
      }
    },
    [media, report, refresh],
  );

  // ── Settings and devices ───────────────────────────────────────────────────

  const saveSettings = useCallback(
    async (patch: Partial<SyncSettings>) => {
      const previous = settingsRef.current;
      setSettings((s) => (s ? { ...s, ...patch } : s));
      try {
        await clipboard.saveSettings(patch);
      } catch (e) {
        setSettings(previous);
        report(e);
      }
    },
    [clipboard, report],
  );

  const removeDevice = useCallback(
    async (id: string) => {
      try {
        await clipboard.removeDevice(id);
        setDevices((current) => current.filter((d) => d.id !== id));
      } catch (e) {
        report(e);
      }
    },
    [clipboard, report],
  );

  const clearError = useCallback(() => setError(null), []);

  const value = useMemo<CopyOnceValue>(
    () => ({
      items,
      devices,
      settings,
      status,
      error,
      isUploading,
      clearError,
      refresh,
      captureText,
      captureImage,
      readSystemClipboard,
      copyItem,
      deleteItem,
      togglePinned,
      clearHistory,
      thumbnailUrl,
      openOriginal,
      saveSettings,
      removeDevice,
    }),
    [
      items,
      devices,
      settings,
      status,
      error,
      isUploading,
      clearError,
      refresh,
      captureText,
      captureImage,
      readSystemClipboard,
      copyItem,
      deleteItem,
      togglePinned,
      clearHistory,
      thumbnailUrl,
      openOriginal,
      saveSettings,
      removeDevice,
    ],
  );

  return (
    <CopyOnceContext.Provider value={value}>{children}</CopyOnceContext.Provider>
  );
}
