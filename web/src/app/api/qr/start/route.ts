import { NextResponse } from "next/server";
import {
  QR_NOT_CONFIGURED,
  createAdminClient,
} from "@/lib/supabase/admin";

/**
 * Opens a sign-in request and returns the code the browser should display.
 *
 * The token is random and opaque: on its own it grants nothing. It becomes
 * useful only after a signed-in device approves it, and only once.
 */
export async function POST(request: Request) {
  const supabase = createAdminClient();
  if (!supabase) return NextResponse.json(QR_NOT_CONFIGURED, { status: 503 });

  // 32 random bytes, hex. Guessing one inside the two-minute window is not a
  // realistic attack, and a guess still has to be approved by a human.
  const token = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString("hex");

  // Shown to whoever approves, so they can tell their own laptop from a
  // stranger's. A QR sign-in is only as safe as the approver recognising what
  // they are approving.
  const agent = request.headers.get("user-agent") ?? "";
  const requesterLabel = describeBrowser(agent);

  // Cheap housekeeping instead of a scheduled job; the table stays tiny.
  await supabase.rpc("purge_login_tokens");

  const { error } = await supabase
    .from("login_tokens")
    .insert({ token, requester_label: requesterLabel });

  if (error) {
    return NextResponse.json({ error: "could_not_start" }, { status: 500 });
  }

  return NextResponse.json({ token, requesterLabel, expiresInSeconds: 120 });
}

/** "Chrome on Windows" — enough to recognise, nothing identifying. */
function describeBrowser(ua: string): string {
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
            : "A browser";

  const os = /Windows/i.test(ua)
    ? "Windows"
    : /Mac OS X|Macintosh/i.test(ua)
      ? "macOS"
      : /Android/i.test(ua)
        ? "Android"
        : /iPhone|iPad/i.test(ua)
          ? "iOS"
          : "Linux";

  return `${browser} on ${os}`;
}
