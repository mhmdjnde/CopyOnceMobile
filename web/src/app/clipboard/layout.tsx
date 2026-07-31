import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { CopyOnceProvider } from "@/lib/copyonce-provider";
import { AppNav } from "@/components/app-nav";

/**
 * Guard and shell for everything behind sign-in.
 *
 * This is the authoritative gate, not the proxy. It awaits the account's
 * assurance level, which matters because the database refuses to return a
 * single clipboard row below aal2 for an account with a verified TOTP factor —
 * a half-authenticated session would otherwise see an empty list and no
 * explanation.
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

  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal?.nextLevel === "aal2" && aal.nextLevel !== aal.currentLevel) {
    redirect("/sign-in");
  }

  return (
    <CopyOnceProvider userId={user.id}>
      <div className="flex min-h-full flex-1 flex-col">
        <AppNav email={user.email ?? ""} />
        <div className="mx-auto w-full max-w-4xl flex-1 px-4 pb-24 sm:px-6">
          {children}
        </div>
      </div>
    </CopyOnceProvider>
  );
}
