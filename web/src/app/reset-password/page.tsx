"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, ErrorBanner, Field, Spinner } from "@/components/ui";
import { PasswordField } from "@/components/password-field";
import { validatePassword } from "@/lib/password-policy";
import { Logo } from "@/components/logo";

/**
 * Lands here from the emailed recovery link.
 *
 * Supabase turns the link's token into a session before this renders, so the
 * check below is really "did the link work" — an expired or reused link leaves
 * no session and there is nothing to update.
 */
export default function ResetPasswordPage() {
  const router = useRouter();
  const supabase = createClient();

  const [checking, setChecking] = useState(true);
  const [hasSession, setHasSession] = useState(false);
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setHasSession(Boolean(data.session));
      setChecking(false);
    });
  }, [supabase]);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const problem = validatePassword(password);
    if (problem) return setError(problem);
    if (password !== confirm) return setError("Those passwords do not match.");

    setBusy(true);
    setError(null);

    const { error: updateError } = await supabase.auth.updateUser({ password });
    setBusy(false);

    if (updateError) return setError(updateError.message);

    router.push("/clipboard");
    router.refresh();
  }

  if (checking) {
    return (
      <main className="flex flex-1 items-center justify-center">
        <Spinner className="size-6 text-accent" />
      </main>
    );
  }

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-8 px-6 py-12">
      <span className="mx-auto">
        <Logo height={30} priority />
      </span>

      {!hasSession ? (
        <div className="flex flex-col gap-4 text-center">
          <h1 className="text-2xl font-bold text-ink">This link has expired</h1>
          <p className="text-sm leading-relaxed text-ink-soft">
            Reset links can only be used once, and they do not last long. Ask for
            a fresh one.
          </p>
          <Button variant="primary" onClick={() => router.push("/forgot-password")}>
            Request a new link
          </Button>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="flex flex-col gap-5">
          <div>
            <h1 className="text-2xl font-bold text-ink">Set a new password</h1>
            <p className="mt-1 text-sm text-ink-soft">
              This signs out your other devices.
            </p>
          </div>

          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <PasswordField
            label="New password"
            value={password}
            onChange={setPassword}
          />

          <Field
            label="Confirm password"
            type="password"
            autoComplete="new-password"
            required
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            error={confirm && confirm !== password ? "Passwords do not match." : null}
          />

          <Button type="submit" loading={busy}>
            Update password
          </Button>
        </form>
      )}
    </main>
  );
}
