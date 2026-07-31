import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  ClipboardItem,
  ClipboardItemType,
  DevicePlatform,
  DeviceRow,
  SyncSettings,
} from "../types";

/**
 * Raised for clipboard failures, carrying a message safe to show.
 *
 * Never carries clipboard content. An error string can end up in a console, a
 * log drain, or a bug report, and the content must not follow it there — the
 * same rule ClipboardFailure follows in the Flutter client.
 */
export class ClipboardFailure extends Error {}

/** Longest text accepted, matching the check constraint in 0002. */
export const MAX_CONTENT_LENGTH = 100_000;

/**
 * The only place the web client talks to the clipboard tables.
 *
 * Every query is owner-scoped by Row Level Security; the explicit `user_id`
 * filters are for index use and clarity, not access control.
 */
export class ClipboardRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  private async userId(): Promise<string> {
    const {
      data: { user },
    } = await this.supabase.auth.getUser();
    if (!user) throw new ClipboardFailure("Sign in to sync your clipboard.");
    return user.id;
  }

  /** The account's items, newest first, pinned ahead of the rest. */
  async fetchItems(limit = 200): Promise<ClipboardItem[]> {
    const userId = await this.userId();
    const { data, error } = await this.supabase
      .from("clipboard_items")
      .select("*")
      .eq("user_id", userId)
      .order("is_pinned", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(limit);

    if (error) throw this.friendly(error);
    return (data ?? []) as ClipboardItem[];
  }

  /**
   * Live updates for this account's rows.
   *
   * Postgres changes carry the whole row, which is exactly why image bytes live
   * in Storage and only their paths live here — otherwise every image would be
   * pushed down this socket to every open tab.
   */
  watchItems(userId: string, onChange: () => void) {
    return this.supabase
      .channel(`clipboard:${userId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "clipboard_items",
          filter: `user_id=eq.${userId}`,
        },
        onChange,
      )
      .subscribe();
  }

  /**
   * Saves a captured value.
   *
   * Returns null when the content is blank or already the newest item — a
   * re-copy of what is already at the top is not worth a new row.
   */
  async addItem(params: {
    content: string;
    type: ClipboardItemType;
    deviceId?: string;
    deviceName?: string;
    devicePlatform?: DevicePlatform;
    /**
     * Content of the item currently at the top, if any. Supplied by the caller
     * because the UI already holds the list — re-querying for a duplicate check
     * would be a round trip to learn something already on screen.
     */
    newestContent?: string | null;
  }): Promise<ClipboardItem | null> {
    const userId = await this.userId();
    const trimmed = params.content.trim();
    if (!trimmed) return null;

    const capped = trimmed.slice(0, MAX_CONTENT_LENGTH);
    if (params.newestContent === capped) return null;

    const { data, error } = await this.supabase
      .from("clipboard_items")
      .insert({
        user_id: userId,
        content: capped,
        content_type: params.type,
        device_id: params.deviceId ?? null,
        device_name: params.deviceName ?? null,
        device_platform: params.devicePlatform ?? null,
      })
      .select()
      .single();

    if (error) throw this.friendly(error);
    return data as ClipboardItem;
  }

  async deleteItem(id: string): Promise<void> {
    const userId = await this.userId();
    const { error } = await this.supabase
      .from("clipboard_items")
      .delete()
      .eq("id", id)
      .eq("user_id", userId);

    if (error) throw this.friendly(error);
  }

  async setPinned(id: string, isPinned: boolean): Promise<void> {
    const userId = await this.userId();
    const { error } = await this.supabase
      .from("clipboard_items")
      .update({ is_pinned: isPinned })
      .eq("id", id)
      .eq("user_id", userId);

    if (error) throw this.friendly(error);
  }

  /**
   * Clears the account's synced history.
   *
   * Only touches stored rows. The browser's own clipboard is left alone — the
   * user asked to forget what CopyOnce kept, not to reach into the clipboard
   * they may still be pasting from.
   */
  async clearHistory(): Promise<void> {
    const userId = await this.userId();
    const { error } = await this.supabase
      .from("clipboard_items")
      .delete()
      .eq("user_id", userId);

    if (error) throw this.friendly(error);
  }

  /** Applies the account's retention period, returning how many items went. */
  async pruneExpired(): Promise<number> {
    const { data, error } = await this.supabase.rpc(
      "prune_expired_clipboard_items",
    );
    if (error) throw this.friendly(error);
    return (data as number | null) ?? 0;
  }

  // ── Devices ────────────────────────────────────────────────────────────────

  /**
   * Records this browser and refreshes its last-seen time.
   *
   * Returns the device row id, which image delivery receipts are keyed on.
   */
  async registerDevice(params: {
    installId: string;
    name: string;
    platform: DevicePlatform;
  }): Promise<string> {
    const userId = await this.userId();
    const { data, error } = await this.supabase
      .from("devices")
      .upsert(
        {
          user_id: userId,
          install_id: params.installId,
          name: params.name,
          platform: params.platform,
          last_seen_at: new Date().toISOString(),
        },
        { onConflict: "user_id,install_id" },
      )
      .select("id")
      .single();

    if (error) throw this.friendly(error);
    return (data as { id: string }).id;
  }

  async fetchDevices(): Promise<DeviceRow[]> {
    const userId = await this.userId();
    const { data, error } = await this.supabase
      .from("devices")
      .select("*")
      .eq("user_id", userId)
      .order("last_seen_at", { ascending: false });

    if (error) throw this.friendly(error);
    return (data ?? []) as DeviceRow[];
  }

  async removeDevice(id: string): Promise<void> {
    const userId = await this.userId();
    const { error } = await this.supabase
      .from("devices")
      .delete()
      .eq("id", id)
      .eq("user_id", userId);

    if (error) throw this.friendly(error);
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  async loadSettings(): Promise<SyncSettings> {
    const userId = await this.userId();
    const { data, error } = await this.supabase
      .from("user_settings")
      .select("*")
      .eq("user_id", userId)
      .maybeSingle();

    if (error) throw this.friendly(error);

    // A trigger creates this row on sign-up, but an account made before that
    // trigger existed will not have one. Defaults match the column defaults.
    return (
      (data as SyncSettings | null) ?? {
        auto_sync: true,
        wifi_only: false,
        sync_alerts: true,
        retention_days: 7,
        capture_text: true,
        capture_links: true,
        capture_images: true,
      }
    );
  }

  async saveSettings(settings: Partial<SyncSettings>): Promise<void> {
    const userId = await this.userId();
    const { error } = await this.supabase
      .from("user_settings")
      .upsert({ user_id: userId, ...settings }, { onConflict: "user_id" });

    if (error) throw this.friendly(error);
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /**
   * Turns a Postgres error into something safe to put on screen.
   *
   * Deliberately drops the raw error: it can echo the row being written, and
   * that row is clipboard content.
   */
  private friendly(error: { code?: string; message?: string }): ClipboardFailure {
    const code = error.code ?? "";

    // 42501 is insufficient_privilege: RLS refused the row. With the assurance
    // check in place, the usual cause is a session that has not cleared 2FA.
    if (code === "42501" || code === "PGRST301") {
      return new ClipboardFailure(
        "Your session needs to be verified again. Sign in once more.",
      );
    }
    if (code === "23514") {
      return new ClipboardFailure("That item is too large to sync.");
    }
    return new ClipboardFailure("Something went wrong syncing. Please try again.");
  }
}
