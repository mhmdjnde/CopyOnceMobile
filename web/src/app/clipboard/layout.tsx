import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { CopyOnceProvider } from "@/lib/copyonce-provider";
import { AppNav } from "@/components/app-nav";

/**
 * Guard and shell for everything behind sign-in.
 *
 * One network call, not two. `getUser()` verifies the token with Supabase and
 * returns the account's factors in the same response, and the current assurance
 * level is a claim on the token it just validated — so asking the MFA endpoint
 * separately was a second round trip for something already in hand. That call
 * ran on every navigation, and removing it is most of why moving between pages
 * now feels immediate.
 *
 * This is the authoritative gate, not the proxy. The database still refuses to
 * return a clipboard row below aal2 for an account with a verified factor; this
 * only decides which screen to show.
 */
export default async function ClipboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/sign-in");

  const hasVerifiedFactor = (user.factors ?? []).some(
    (factor) => factor.status === "verified",
  );

  if (hasVerifiedFactor) {
    // Read locally from the token getUser() just validated, rather than asking
    // the server again.
    const {
      data: { session },
    } = await supabase.auth.getSession();

    if (currentAal(session?.access_token) !== "aal2") redirect("/sign-in");
  }

  return (
    <CopyOnceProvider userId={user.id}>
      <AppNav email={user.email ?? ""} />
      {/* Offsets: the rail on desktop, the bottom bar on a phone. */}
      <div className="flex-1 md:pl-56">
        <div className="mx-auto w-full max-w-3xl px-4 pb-28 sm:px-6 md:pb-10">
          {children}
        </div>
      </div>
    </CopyOnceProvider>
  );
}

/**
 * The `aal` claim from an access token.
 *
 * Decoded without verifying, which is safe only because this runs after
 * `getUser()` has already checked the same token against Supabase. Never trust
 * this on its own.
 */
function currentAal(accessToken: string | undefined): string | null {
  if (!accessToken) return null;
  try {
    const payload = accessToken.split(".")[1];
    const json = Buffer.from(payload, "base64url").toString("utf8");
    return (JSON.parse(json) as { aal?: string }).aal ?? null;
  } catch {
    return null;
  }
}
