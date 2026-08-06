import { NextResponse } from "next/server";
import { QR_NOT_CONFIGURED, createAdminClient } from "@/lib/supabase/admin";

/**
 * Polled by the waiting browser. Returns a session once a device approves.
 *
 * The claim is a conditional update returning the row, so a token can only ever
 * be spent once even if two tabs poll at the same moment.
 */
export async function GET(request: Request) {
  const supabase = createAdminClient();
  if (!supabase) return NextResponse.json(QR_NOT_CONFIGURED, { status: 503 });

  const token = new URL(request.url).searchParams.get("token");
  if (!token) return NextResponse.json({ error: "bad_request" }, { status: 400 });

  const { data: row } = await supabase
    .from("login_tokens")
    .select("approved_by, claimed_at, expires_at")
    .eq("token", token)
    .maybeSingle();

  if (!row) return NextResponse.json({ status: "unknown" }, { status: 404 });
  if (row.claimed_at) return NextResponse.json({ status: "used" });
  if (new Date(row.expires_at) < new Date()) {
    return NextResponse.json({ status: "expired" });
  }
  if (!row.approved_by) return NextResponse.json({ status: "waiting" });

  // Mark it spent first. If minting fails afterwards the token is burned, which
  // is the safe direction — the alternative is a token that could be redeemed
  // twice.
  const { data: claimed } = await supabase
    .from("login_tokens")
    .update({ claimed_at: new Date().toISOString() })
    .eq("token", token)
    .is("claimed_at", null)
    .select("approved_by")
    .maybeSingle();

  if (!claimed?.approved_by) return NextResponse.json({ status: "used" });

  const { data: account } = await supabase.auth.admin.getUserById(claimed.approved_by);
  const email = account?.user?.email;
  if (!email) return NextResponse.json({ status: "failed" }, { status: 500 });

  // A magic link is the only way to hand a browser a session it did not sign in
  // for. The link is never emailed — the hash goes straight back over this
  // response and the browser exchanges it immediately.
  const { data: link, error } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email,
  });

  const hash = link?.properties?.hashed_token;
  if (error || !hash) return NextResponse.json({ status: "failed" }, { status: 500 });

  return NextResponse.json({ status: "approved", tokenHash: hash, email });
}
