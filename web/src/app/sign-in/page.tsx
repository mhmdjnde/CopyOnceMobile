"use client";

import { Suspense, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { resendSignUpCode, signIn, verifyEmailCode } from "@/lib/auth";
import { Button, ErrorBanner, Field, Notice } from "@/components/ui";
import { AUTHENTICATOR_CODE_LENGTH, VERIFICATION_CODE_LENGTH } from "@/lib/types";
import { Logo } from "@/components/logo";

export default function SignInPage() {
  // useSearchParams needs a Suspense boundary or the route bails to client
  // rendering entirely.
  return (
    <Suspense fallback={null}>
      <SignInForm />
    </Suspense>
  );
}

type Stage = "credentials" | "totp" | "emailCode";

function SignInForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get("next") ?? "/clipboard";

  const [stage, setStage] = useState<Stage>("credentials");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const supabase = createClient();

  function done() {
    router.push(next);
    router.refresh();
  }

  async function handleSignIn(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const result = await signIn(supabase, { email, password });
    setBusy(false);

    switch (result.status) {
      case "signedIn":
        return done();
      case "needsTotp":
        setCode("");
        return setStage("totp");
      case "needsEmailCode":
        // The account exists but was never verified — someone closed the tab
        // before entering the code. Finishing that is the way in; registering
        // again is not.
        setBusy(true);
        try {
          await resendSignUpCode(supabase, email);
          setNotice(`We sent a fresh ${VERIFICATION_CODE_LENGTH}-digit code to ${email}.`);
        } catch {
          setNotice("Enter the code we emailed you when you signed up.");
        }
        setBusy(false);
        setCode("");
        return setStage("emailCode");
      case "failed":
        return setError(result.message);
    }
  }

  async function handleTotp(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { data: factors } = await supabase.auth.mfa.listFactors();
    const factorId = factors?.totp?.[0]?.id;
    if (!factorId) {
      setBusy(false);
      return setError("Could not find an authenticator for this account.");
    }

    const { data: challenge, error: challengeError } =
      await supabase.auth.mfa.challenge({ factorId });
    if (challengeError || !challenge) {
      setBusy(false);
      return setError("Could not start verification. Try again.");
    }

    const { error: verifyError } = await supabase.auth.mfa.verify({
      factorId,
      challengeId: challenge.id,
      code: code.trim(),
    });
    setBusy(false);

    if (verifyError) {
      setCode("");
      return setError("That code was not accepted. Try the next one.");
    }
    done();
  }

  async function handleEmailCode(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const result = await verifyEmailCode(supabase, { email, token: code });
    setBusy(false);

    if (!result.ok) {
      setCode("");
      return setError(result.message);
    }
    done();
  }

  const codeLength =
    stage === "totp" ? AUTHENTICATOR_CODE_LENGTH : VERIFICATION_CODE_LENGTH;

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-7 px-6 py-12">
      <Link href="/" className="mx-auto">
        <Logo height={30} priority />
      </Link>

      {stage === "credentials" && (
        <form onSubmit={handleSignIn} className="flex flex-col gap-5">
          <header>
            <h1 className="font-display text-2xl font-bold text-ink">Welcome back</h1>
            <p className="mt-1 text-sm text-ink-soft">Sign in to reach your clipboard.</p>
          </header>

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

      {stage === "totp" && (
        <form onSubmit={handleTotp} className="flex flex-col gap-5">
          <header>
            <h1 className="font-display text-2xl font-bold text-ink">Two-factor code</h1>
            <p className="mt-1 text-sm text-ink-soft">
              Enter the {AUTHENTICATOR_CODE_LENGTH}-digit code from your authenticator app.
            </p>
          </header>

          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <CodeField length={codeLength} value={code} onChange={setCode} />

          <Button type="submit" loading={busy} disabled={code.length !== codeLength}>
            Verify
          </Button>
        </form>
      )}

      {stage === "emailCode" && (
        <form onSubmit={handleEmailCode} className="flex flex-col gap-5">
          <header>
            <h1 className="font-display text-2xl font-bold text-ink">
              Finish setting up
            </h1>
            <p className="mt-1 text-sm text-ink-soft">
              This account was never verified. Enter the code to finish — you do not
              need to sign up again.
            </p>
          </header>

          {notice && <Notice>{notice}</Notice>}
          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <CodeField length={codeLength} value={code} onChange={setCode} />

          <Button type="submit" loading={busy} disabled={code.length !== codeLength}>
            Verify email
          </Button>

          <button
            type="button"
            onClick={async () => {
              await resendSignUpCode(supabase, email);
              setNotice("A new code is on its way.");
            }}
            className="text-sm text-ink-soft hover:text-ink"
          >
            Send another code
          </button>
        </form>
      )}
    </main>
  );
}

function CodeField({
  length,
  value,
  onChange,
}: {
  length: number;
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <Field
      label={`Code (${length} digits)`}
      inputMode="numeric"
      autoComplete="one-time-code"
      pattern="[0-9]*"
      maxLength={length}
      required
      autoFocus
      mono
      className="text-center text-lg tracking-[0.35em]"
      value={value}
      onChange={(e) => onChange(e.target.value.replace(/\D/g, ""))}
      placeholder={"0".repeat(length)}
    />
  );
}
