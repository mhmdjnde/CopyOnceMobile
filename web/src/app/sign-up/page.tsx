"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, ErrorBanner, Field, Wordmark } from "@/components/ui";

/** Mirrors the password rules in lib/utils/password_policy.dart. */
function passwordProblem(password: string): string | null {
  if (password.length < 8) return "Use at least 8 characters.";
  if (!/[a-z]/.test(password)) return "Include a lowercase letter.";
  if (!/[A-Z]/.test(password)) return "Include an uppercase letter.";
  if (!/[0-9]/.test(password)) return "Include a number.";
  return null;
}

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

  const problem = password ? passwordProblem(password) : null;

  async function handleSignUp(event: React.FormEvent) {
    event.preventDefault();
    if (problem) return setError(problem);
    if (password !== confirm) return setError("Those passwords do not match.");

    setBusy(true);
    setError(null);

    const { data, error: signUpError } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: { data: { display_name: displayName.trim() || null } },
    });

    setBusy(false);

    if (signUpError) return setError(signUpError.message);

    // A session straight away means the project has email confirmation off.
    if (data.session) {
      router.push("/clipboard");
      router.refresh();
      return;
    }
    setStage("verify");
  }

  async function handleVerify(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { error: verifyError } = await supabase.auth.verifyOtp({
      email: email.trim(),
      token: code.trim(),
      type: "signup",
    });

    setBusy(false);

    if (verifyError) {
      setError("That code was not accepted. Check it and try again.");
      setCode("");
      return;
    }

    router.push("/clipboard");
    router.refresh();
  }

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-8 px-6 py-12">
      <Link href="/" className="mx-auto">
        <Wordmark className="text-lg text-ink" />
      </Link>

      {stage === "verify" ? (
        <form onSubmit={handleVerify} className="flex flex-col gap-5">
          <div>
            <h1 className="text-2xl font-bold text-ink">Check your email</h1>
            <p className="mt-1 text-sm text-ink-soft">
              We sent a code to {email}. Enter it to finish setting up.
            </p>
          </div>

          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <Field
            label="Verification code"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            required
            autoFocus
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            placeholder="000000"
          />

          <Button type="submit" loading={busy} disabled={code.length !== 6}>
            Verify email
          </Button>
        </form>
      ) : (
        <form onSubmit={handleSignUp} className="flex flex-col gap-5">
          <div>
            <h1 className="text-2xl font-bold text-ink">Create your account</h1>
            <p className="mt-1 text-sm text-ink-soft">
              One account, every device you own.
            </p>
          </div>

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
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
          />

          <Field
            label="Password"
            type="password"
            autoComplete="new-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            hint="At least 8 characters, with upper, lower, and a number."
            error={password ? problem : null}
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
