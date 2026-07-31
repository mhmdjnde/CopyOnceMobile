import { createBrowserClient } from "@supabase/ssr";

/**
 * Supabase client for the browser.
 *
 * Points at the same project as the Flutter app, which is the whole reason the
 * two clients share accounts and data without a line of sync code between them.
 *
 * The publishable key is meant to ship to clients. Row Level Security is what
 * actually keeps one account's clipboard away from another's — see
 * supabase/migrations/0002_clipboard.sql.
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  );
}
