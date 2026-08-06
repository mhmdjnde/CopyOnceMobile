"use client";

import { useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Button, ErrorBanner, Field } from "@/components/ui";
import { Logo } from "@/components/logo";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { error: resetError } = await createClient().auth.resetPasswordForEmail(
      email.trim(),
      { redirectTo: `${window.location.origin}/reset-password` },
    );

    setBusy(false);

    if (resetError) {
      setError(resetError.message);
      return;
    }
    setSent(true);
  }

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-8 px-6 py-12">
      <Link href="/" className="mx-auto">
        <Logo height={30} priority />
      </Link>

      {sent ? (
        <div className="flex flex-col gap-4 text-center">
          <h1 className="text-2xl font-bold text-ink">Check your email</h1>
          <p className="text-sm leading-relaxed text-ink-soft">
            If an account exists for {email}, a reset link is on its way. The
            link opens this site and lets you set a new password.
          </p>
          <Link href="/sign-in">
            <Button variant="secondary" className="w-full">
              Back to sign in
            </Button>
          </Link>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="flex flex-col gap-5">
          <div>
            <h1 className="text-2xl font-bold text-ink">Reset your password</h1>
            <p className="mt-1 text-sm text-ink-soft">
              We&apos;ll email you a link to set a new one.
            </p>
          </div>

          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <Field
            label="Email"
            type="email"
            autoComplete="email"
            required
            autoFocus
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
          />

          <Button type="submit" loading={busy}>
            Send reset link
          </Button>

          <p className="text-center text-sm text-ink-soft">
            Remembered it?{" "}
            <Link href="/sign-in" className="font-medium text-accent hover:underline">
              Sign in
            </Link>
          </p>
        </form>
      )}
    </main>
  );
}
