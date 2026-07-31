/**
 * Shapes shared with the Flutter client.
 *
 * These mirror lib/models/clipboard_item.dart and the tables in
 * supabase/migrations/. The database is the contract between the two clients;
 * if a column changes there, it changes in both places or neither.
 */

export type ClipboardItemType = "text" | "link" | "image";

/**
 * Platforms the `devices.platform` check constraint accepts.
 *
 * There is deliberately no "web" value — adding one would mean a migration and
 * a matching change in the Flutter enum. A browser reports the OS it is running
 * on instead, and says it is a browser in the device *name* ("Chrome on
 * Windows"), which reads better in the device list anyway.
 */
export type DevicePlatform = "ios" | "android" | "macos" | "windows" | "linux";

export interface ClipboardItem {
  id: string;
  content: string;
  content_type: ClipboardItemType;
  device_id: string | null;
  device_name: string | null;
  device_platform: DevicePlatform | null;
  is_pinned: boolean;
  created_at: string;

  // Image payload. Null on text and link rows — the bytes live in Storage and
  // these are pointers to them.
  storage_path: string | null;
  thumb_path: string | null;
  byte_size: number | null;
  mime_type: string | null;
  expires_at: string | null;
}

export interface DeviceRow {
  id: string;
  install_id: string;
  name: string;
  platform: DevicePlatform;
  last_seen_at: string;
  created_at: string;
}

export interface SyncSettings {
  auto_sync: boolean;
  wifi_only: boolean;
  sync_alerts: boolean;
  retention_days: number;
  capture_text: boolean;
  capture_links: boolean;
  capture_images: boolean;
}

/** Retention values the picker offers, matching the check constraint in 0002. */
export const RETENTION_OPTIONS = [
  { value: 0, label: "Keep until I delete" },
  { value: 1, label: "1 day" },
  { value: 7, label: "7 days" },
  { value: 30, label: "30 days" },
  { value: 90, label: "90 days" },
  { value: 365, label: "1 year" },
] as const;

/** Image types the relay accepts. Must agree with the bucket and 0003's check. */
export const ALLOWED_IMAGE_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
  "image/heic",
] as const;

/** Matches MediaRepository.maxImageBytes and the bucket's file_size_limit. */
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

/** Live images per account, enforced by the trigger in 0003. */
export const MAX_LIVE_IMAGES = 10;
