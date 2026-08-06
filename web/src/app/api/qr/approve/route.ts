import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { QR_NOT_CONFIGURED, createAdminClient } from "@/lib/supabase/admin";

/**
 * Approves a pending sign-in, on behalf of the device that scanned it.
 *
 * The caller proves who it is with its own access token in the Authorization
 * header, which is verified against Supabase rather than trusted. Approving
 * does not share that session — it only records who said yes, so the server can
 * mint a separate one for the browser.
 */
export async function POST(request: Request) {
  const admin = createAdminClient();
  if (!admin) return NextResponse.json(QR_NOT_CONFIGURED, { status: 503 });

  const accessToken = request.headers.get("authorization")?.replace(/^Bearer /i, "");
  if (!accessToken) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  let token: string | undefined;
  try {
    ({ token } = (await request.json()) as { token?: string });
  } catch {
    return NextResponse.json({ error: "bad_request" }, { status: 400 });
  }
  if (!token) return NextResponse.json({ error: "bad_request" }, { status: 400 });

  // Verify the caller's token with the auth service. Decoding it here would
  // accept anything shaped like a JWT.
  const anon = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    { auth: { persistSession: false } },
  );
  const {
    data: { user },
    error: userError,
  } = await anon.auth.getUser(accessToken);

  if (userError || !user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  // Only an unapproved, unclaimed, unexpired request can be approved, and the
  // conditions live in the UPDATE so two scans cannot both win.
  const { data, error } = await admin
    .from("login_tokens")
    .update({ approved_by: user.id, approved_at: new Date().toISOString() })
    .eq("token", token)
    .is("approved_by", null)
    .is("claimed_at", null)
    .gt("expires_at", new Date().toISOString())
    .select("id, requester_label")
    .maybeSingle();

  if (error) return NextResponse.json({ error: "could_not_approve" }, { status: 500 });
  if (!data) {
    return NextResponse.json(
      { error: "expired_or_used", message: "That code has expired. Ask for a new one." },
      { status: 410 },
    );
  }

  return NextResponse.json({ ok: true, requesterLabel: data.requester_label });
}
