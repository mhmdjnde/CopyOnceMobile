"use client";

import { Suspense, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, ErrorBanner, Field, Wordmark } from "@/components/ui";

export default function SignInPage() {
  // useSearchParams needs a Suspense boundary or the whole route bails out to
  // client rendering.
  return (
    <Suspense fallback={null}>
      <SignInForm />
    </Suspense>
  );
}

function SignInForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get("next") ?? "/clipboard";

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [needsMfa, setNeedsMfa] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const supabase = createClient();

  /**
   * Signs in, then checks whether this account still owes a second factor.
   *
   * Supabase hands back a usable session at assurance level 1 before TOTP is
   * verified. The database's has_required_assurance() refuses to return any
   * clipboard row until aal2, so stopping here would show an empty list rather
   * than an error — which is why the MFA step is part of signing in, not an
   * optional extra.
   */
  async function handleSignIn(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    if (signInError) {
      setError(signInError.message);
      setBusy(false);
      return;
    }

    const { data: aal } =
      await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

    if (aal?.nextLevel === "aal2" && aal.nextLevel !== aal.currentLevel) {
      setNeedsMfa(true);
      setBusy(false);
      return;
    }

    router.push(next);
    router.refresh();
  }

  async function handleVerify(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { data: factors, error: factorError } =
      await supabase.auth.mfa.listFactors();

    if (factorError || !factors?.totp?.length) {
      setError("Could not find an authenticator for this account.");
      setBusy(false);
      return;
    }

    const factorId = factors.totp[0].id;
    const { data: challenge, error: challengeError } =
      await supabase.auth.mfa.challenge({ factorId });

    if (challengeError || !challenge) {
      setError("Could not start verification. Please try again.");
      setBusy(false);
      return;
    }

    const { error: verifyError } = await supabase.auth.mfa.verify({
      factorId,
      challengeId: challenge.id,
      code: code.trim(),
    });

    if (verifyError) {
      setError("That code was not accepted. Try the next one.");
      setCode("");
      setBusy(false);
      return;
    }

    router.push(next);
    router.refresh();
  }

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-8 px-6 py-12">
      <Link href="/" className="mx-auto">
        <Wordmark className="text-lg text-ink" />
      </Link>

      {needsMfa ? (
        <form onSubmit={handleVerify} className="flex flex-col gap-5">
          <div>
            <h1 className="text-2xl font-bold text-ink">Two-factor code</h1>
            <p className="mt-1 text-sm text-ink-soft">
              Enter the 6-digit code from your authenticator app.
            </p>
          </div>

          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <Field
            label="Authentication code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]*"
            maxLength={6}
            required
            autoFocus
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            placeholder="000000"
          />

          <Button type="submit" loading={busy} disabled={code.length !== 6}>
            Verify
          </Button>
        </form>
      ) : (
        <form onSubmit={handleSignIn} className="flex flex-col gap-5">
          <div>
            <h1 className="text-2xl font-bold text-ink">Welcome back</h1>
            <p className="mt-1 text-sm text-ink-soft">
              Sign in to reach your clipboard.
            </p>
          </div>

          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <Field
            label="Email"
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
          />

          <Field
            label="Password"
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />

          <Button type="submit" loading={busy}>
            Sign in
          </Button>

          <div className="flex items-center justify-between text-sm">
            <Link href="/forgot-password" className="text-ink-soft hover:text-ink">
              Forgot password?
            </Link>
            <Link href="/sign-up" className="font-medium text-accent hover:underline">
              Create account
            </Link>
          </div>
        </form>
      )}
    </main>
  );
}
