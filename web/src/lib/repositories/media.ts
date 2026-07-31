import type { SupabaseClient } from "@supabase/supabase-js";
import {
  buildThumbnail,
  extensionFor,
  isAllowedImageType,
  MediaError,
  sniffMimeType,
} from "../media-encoder";
import { MAX_IMAGE_BYTES, type ClipboardItem, type DevicePlatform } from "../types";
import { ClipboardFailure } from "./clipboard";

/** Bucket holding both originals and thumbnails. */
export const MEDIA_BUCKET = "clipboard-media";

/** How long an undelivered image survives. The database is the authority. */
const RELAY_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * The only place the web client talks to the image bucket.
 *
 * Mirrors lib/repositories/media_repository.dart, including the rule that
 * matters most:
 *
 *   Delete the storage object FIRST, then the row.
 *
 * A row is the only remaining pointer to its files. Lose it first and the bytes
 * are stranded in the bucket with nothing left to find them by.
 */
export class MediaRepository {
  /** Thumbnails fetched this session, keyed by storage path. */
  private thumbnails = new Map<string, string>();

  constructor(private readonly supabase: SupabaseClient) {}

  private async userId(): Promise<string> {
    const {
      data: { user },
    } = await this.supabase.auth.getUser();
    if (!user) throw new ClipboardFailure("Sign in to share images.");
    return user.id;
  }

  /**
   * Uploads an image and returns the stored row.
   *
   * Files go up first, the row last. A row without its files renders as a
   * broken card the reaper then tries to delete objects for; files without a
   * row are invisible and the orphan sweep collects them. The second failure is
   * much cheaper than the first.
   */
  async upload(params: {
    blob: Blob;
    filename: string;
    deviceId?: string;
    deviceName?: string;
    devicePlatform?: DevicePlatform;
  }): Promise<ClipboardItem> {
    const userId = await this.userId();
    const { blob, filename } = params;

    if (blob.size === 0) throw new ClipboardFailure("That image is empty.");
    if (blob.size > MAX_IMAGE_BYTES) {
      throw new ClipboardFailure("Images have to be under 10 MB.");
    }

    // The extension is a claim; the leading bytes are evidence.
    const mimeType = await sniffMimeType(blob);
    if (!isAllowedImageType(mimeType)) {
      throw new ClipboardFailure(
        "That file type is not supported. Try a JPEG, PNG, GIF, or WebP image.",
      );
    }

    let thumbnail: Blob;
    try {
      thumbnail = await buildThumbnail(blob);
    } catch (error) {
      throw new ClipboardFailure(
        error instanceof MediaError ? error.message : "Could not process that image.",
      );
    }

    // Generated here rather than by the database so the storage paths exist
    // before the row does — 0003's shape constraint requires an image row to
    // carry its paths from the moment it is inserted.
    const itemId = crypto.randomUUID();
    const fullPath = `${userId}/${itemId}/full.${extensionFor(mimeType!)}`;
    const thumbPath = `${userId}/${itemId}/thumb.jpg`;

    const up = await this.supabase.storage
      .from(MEDIA_BUCKET)
      .upload(fullPath, blob, { contentType: mimeType!, upsert: false });
    if (up.error) throw this.storageFailure(up.error);

    try {
      const upThumb = await this.supabase.storage
        .from(MEDIA_BUCKET)
        .upload(thumbPath, thumbnail, {
          contentType: "image/jpeg",
          upsert: false,
        });
      if (upThumb.error) throw this.storageFailure(upThumb.error);

      const { data, error } = await this.supabase
        .from("clipboard_items")
        .insert({
          id: itemId,
          user_id: userId,
          content: safeFilename(filename),
          content_type: "image",
          storage_path: fullPath,
          thumb_path: thumbPath,
          byte_size: blob.size,
          mime_type: mimeType,
          expires_at: new Date(Date.now() + RELAY_WINDOW_MS).toISOString(),
          device_id: params.deviceId ?? null,
          device_name: params.deviceName ?? null,
          device_platform: params.devicePlatform ?? null,
        })
        .select()
        .single();

      if (error) throw this.postgrestFailure(error);
      return data as ClipboardItem;
    } catch (error) {
      // The row never landed, so nothing will ever reference these files.
      // Clean them up now rather than waiting for the orphan sweep.
      await this.discard([fullPath, thumbPath]);
      throw error;
    }
  }

  /**
   * An object URL for the item's thumbnail, cached for this session.
   *
   * Object URLs rather than signed URLs: the bytes come down through the
   * authenticated client under RLS, so no URL that could be shared or logged is
   * ever created.
   */
  async thumbnailUrl(item: ClipboardItem): Promise<string | null> {
    if (!item.thumb_path) return null;

    const cached = this.thumbnails.get(item.thumb_path);
    if (cached) return cached;

    const { data, error } = await this.supabase.storage
      .from(MEDIA_BUCKET)
      .download(item.thumb_path);

    if (error || !data) return null;

    const url = URL.createObjectURL(data);
    this.thumbnails.set(item.thumb_path, url);
    return url;
  }

  /** The untouched original, for viewing and download. */
  async original(item: ClipboardItem): Promise<Blob> {
    if (!item.storage_path) {
      throw new ClipboardFailure("That item has no image attached.");
    }

    const { data, error } = await this.supabase.storage
      .from(MEDIA_BUCKET)
      .download(item.storage_path);

    if (error || !data) throw this.storageFailure(error);
    return data;
  }

  /**
   * Records that this browser now holds the image.
   *
   * The database decides what that means: a trigger collapses the image's
   * expiry once every device on the account has a receipt.
   */
  async markDelivered(itemId: string, deviceRowId: string): Promise<void> {
    const userId = await this.userId();
    const { error } = await this.supabase.from("clipboard_deliveries").upsert(
      { item_id: itemId, device_id: deviceRowId, user_id: userId },
      { onConflict: "item_id,device_id", ignoreDuplicates: true },
    );
    if (error) throw this.postgrestFailure(error);
  }

  /**
   * Deletes this account's finished images: files first, then rows.
   *
   * The client half of the reaper. The scheduled Edge Function covers every
   * account whether or not anyone opens a client; this exists because free-tier
   * projects pause when idle and cron does not run while paused.
   */
  async reapExpired(): Promise<number> {
    const { data, error } = await this.supabase.rpc("expired_media_paths");
    if (error) throw this.postgrestFailure(error);

    const rows = (data ?? []) as Array<{
      id: string;
      storage_path: string | null;
      thumb_path: string | null;
    }>;
    if (rows.length === 0) return 0;

    const ids = rows.map((r) => r.id);
    const paths = rows
      .flatMap((r) => [r.storage_path, r.thumb_path])
      .filter((p): p is string => Boolean(p));

    // Files first. If this fails the rows stay, and they are the only remaining
    // pointer to the files.
    const removal = await this.supabase.storage.from(MEDIA_BUCKET).remove(paths);
    if (removal.error) throw this.storageFailure(removal.error);
    for (const path of paths) this.forget(path);

    const { data: removed, error: rowError } = await this.supabase.rpc(
      "reap_media_rows",
      { item_ids: ids },
    );
    if (rowError) throw this.postgrestFailure(rowError);

    return (removed as number | null) ?? 0;
  }

  /** Deletes one image's files, for when the user removes it by hand. */
  async deleteFiles(item: ClipboardItem): Promise<void> {
    const paths = [item.storage_path, item.thumb_path].filter(
      (p): p is string => Boolean(p),
    );
    if (paths.length === 0) return;

    const { error } = await this.supabase.storage.from(MEDIA_BUCKET).remove(paths);
    if (error) throw this.storageFailure(error);
    for (const path of paths) this.forget(path);
  }

  /** Releases every cached object URL. Call when tearing the session down. */
  releaseAll(): void {
    for (const url of this.thumbnails.values()) URL.revokeObjectURL(url);
    this.thumbnails.clear();
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  private forget(path: string): void {
    const url = this.thumbnails.get(path);
    if (url) {
      URL.revokeObjectURL(url);
      this.thumbnails.delete(path);
    }
  }

  /** Best-effort cleanup of files whose row failed to land. */
  private async discard(paths: string[]): Promise<void> {
    try {
      await this.supabase.storage.from(MEDIA_BUCKET).remove(paths);
    } catch {
      // The orphan sweep will collect them. Surfacing this would replace the
      // real error the caller is about to see.
    }
  }

  private storageFailure(error: unknown): ClipboardFailure {
    const status = (error as { statusCode?: string } | null)?.statusCode ?? "";
    if (status === "413") return new ClipboardFailure("That image is too large to send.");
    if (status === "403" || status === "401") {
      return new ClipboardFailure(
        "Your session needs to be verified again. Sign in once more.",
      );
    }
    if (status === "404") {
      return new ClipboardFailure(
        "That image has already been delivered and cleared.",
      );
    }
    return new ClipboardFailure("Could not transfer that image. Please try again.");
  }

  private postgrestFailure(error: { code?: string; message?: string }): ClipboardFailure {
    // 54000 is program_limit_exceeded, raised by the media quota trigger.
    if (error.code === "54000" || error.message?.includes("media_quota_exceeded")) {
      return new ClipboardFailure(
        "You can have 10 images waiting at once. They clear as your devices pick them up, or after 24 hours.",
      );
    }
    if (error.code === "42501" || error.code === "PGRST301") {
      return new ClipboardFailure(
        "Your session needs to be verified again. Sign in once more.",
      );
    }
    if (error.code === "42P01" || error.code === "PGRST205") {
      // The media migration has not been applied to this project yet.
      return new ClipboardFailure(
        "Image sync is not set up on this account's backend yet.",
      );
    }
    return new ClipboardFailure(
      "Something went wrong sending that image. Please try again.",
    );
  }
}

/**
 * A filename safe to store and show.
 *
 * The name is untrusted input that ends up in a list row, so path separators
 * and control characters go and the length is capped. Never empty: the content
 * column rejects a blank string.
 */
function safeFilename(raw: string): string {
  const base = raw.split(/[/\\]/).pop() ?? raw;
  // eslint-disable-next-line no-control-regex
  const cleaned = base.replace(/[\x00-\x1F\x7F]/g, "").trim();
  if (!cleaned) return "Image";
  return cleaned.length > 120 ? cleaned.slice(0, 120) : cleaned;
}
