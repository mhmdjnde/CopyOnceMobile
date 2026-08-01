"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { resendSignUpCode, signUp, verifyEmailCode } from "@/lib/auth";
import { Button, ErrorBanner, Field, Notice } from "@/components/ui";
import { PasswordField } from "@/components/password-field";
import { validatePassword } from "@/lib/password-policy";
import { Keycap } from "@/components/icons";
import { VERIFICATION_CODE_LENGTH } from "@/lib/types";

export default function SignUpPage() {
  const router = useRouter();
  const supabase = createClient();

  const [stage, setStage] = useState<"form" | "verify">("form");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [taken, setTaken] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  async function handleSignUp(event: React.FormEvent) {
    event.preventDefault();
    setTaken(false);

    const problem = validatePassword(password, email);
    if (problem) return setError(problem);
    if (password !== confirm) return setError("Those passwords do not match.");

    setBusy(true);
    setError(null);

    try {
      const result = await signUp(supabase, { email, password, displayName });
      setBusy(false);

      if (result.status === "alreadyRegistered") {
        // Supabase stays quiet about duplicates so sign-up cannot be used to
        // discover who has an account. Saying it here is safe: the person just
        // proved they know the address by typing it.
        setTaken(true);
        return;
      }
      if (result.status === "signedIn") {
        router.push("/clipboard");
        router.refresh();
        return;
      }
      setStage("verify");
    } catch (e) {
      setBusy(false);
      setError(e instanceof Error ? e.message : "Could not create that account.");
    }
  }

  async function handleVerify(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const result = await verifyEmailCode(supabase, { email, token: code });
    setBusy(false);

    if (!result.ok) {
      setCode("");
      return setError(result.message);
    }

    router.push("/clipboard");
    router.refresh();
  }

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-7 px-6 py-12">
      <Link href="/" className="mx-auto flex items-center gap-2.5">
        <Keycap label="V" size={32} />
        <span className="font-display text-lg font-bold tracking-tight text-ink">
          Copy<span className="text-accent">Once</span>
        </span>
      </Link>

      {stage === "verify" ? (
        <form onSubmit={handleVerify} className="flex flex-col gap-5">
          <header>
            <h1 className="font-display text-2xl font-bold text-ink">Check your email</h1>
            <p className="mt-1 text-sm text-ink-soft">
              We sent a {VERIFICATION_CODE_LENGTH}-digit code to {email}.
            </p>
          </header>

          {notice && <Notice>{notice}</Notice>}
          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <Field
            label={`Code (${VERIFICATION_CODE_LENGTH} digits)`}
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={VERIFICATION_CODE_LENGTH}
            required
            autoFocus
            mono
            className="text-center text-lg tracking-[0.35em]"
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            placeholder={"0".repeat(VERIFICATION_CODE_LENGTH)}
          />

          <Button
            type="submit"
            loading={busy}
            disabled={code.length !== VERIFICATION_CODE_LENGTH}
          >
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

          <p className="text-center text-xs leading-relaxed text-ink-faint">
            You can close this page. Signing in later will ask for the same code.
          </p>
        </form>
      ) : (
        <form onSubmit={handleSignUp} className="flex flex-col gap-5">
          <header>
            <h1 className="font-display text-2xl font-bold text-ink">
              Create your account
            </h1>
            <p className="mt-1 text-sm text-ink-soft">One account, every device you own.</p>
          </header>

          {taken && (
            <div className="rounded-[--radius-m] border border-warning/40 bg-warning/10 px-3.5 py-3 text-sm text-warning">
              <p className="font-medium">That email already has an account.</p>
              <Link href="/sign-in" className="mt-1 inline-block underline">
                Sign in instead
              </Link>
            </div>
          )}
          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <Field
            label="Name"
            autoComplete="name"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="Optional"
          />
          <Field
            label="Email"
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={(e) => {
              setEmail(e.target.value);
              setTaken(false);
            }}
            placeholder="you@example.com"
          />
          <PasswordField
            label="Password"
            value={password}
            onChange={setPassword}
            email={email}
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
            Create account
          </Button>

          <p className="text-center text-sm text-ink-soft">
            Already have an account?{" "}
            <Link href="/sign-in" className="font-medium text-accent hover:underline">
              Sign in
            </Link>
          </p>
        </form>
      )}
    </main>
  );
}
