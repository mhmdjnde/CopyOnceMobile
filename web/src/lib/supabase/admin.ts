import { createClient } from "@supabase/supabase-js";

/**
 * Privileged Supabase client, for server code only.
 *
 * The service role bypasses Row Level Security entirely, so this must never be
 * imported into anything that ships to a browser. It lives behind route
 * handlers, which run on the server by definition.
 *
 * Read from `SUPABASE_SERVICE_ROLE_KEY` — deliberately without the
 * `NEXT_PUBLIC_` prefix, because that prefix is what inlines a value into the
 * client bundle.
 */
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) return null;

  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Whether QR sign-in is configured on this deployment.
 *
 * The feature needs a key the rest of the site does not, so it is treated as
 * optional: without it every QR endpoint answers politely and the sign-in page
 * simply does not offer the option. A missing key should never take the site
 * down.
 */
export function qrSignInConfigured(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY,
  );
}

export const QR_NOT_CONFIGURED = {
  error: "qr_not_configured",
  message:
    "Sign-in by QR is not set up on this deployment. Add SUPABASE_SERVICE_ROLE_KEY.",
} as const;
