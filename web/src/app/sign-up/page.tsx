"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button, ErrorBanner, Field, Wordmark } from "@/components/ui";
import { PasswordField } from "@/components/password-field";
import { validatePassword } from "@/lib/password-policy";
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

  async function handleSignUp(event: React.FormEvent) {
    event.preventDefault();

    const problem = validatePassword(password, email);
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
              We sent a {VERIFICATION_CODE_LENGTH}-digit code to {email}. Enter
              it to finish setting up.
            </p>
          </div>

          {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

          <Field
            label={`Verification code (${VERIFICATION_CODE_LENGTH} digits)`}
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={VERIFICATION_CODE_LENGTH}
            required
            autoFocus
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            placeholder={"0".repeat(VERIFICATION_CODE_LENGTH)}
            error={
              code.length > 0 && code.length < VERIFICATION_CODE_LENGTH
                ? `The code is ${VERIFICATION_CODE_LENGTH} digits.`
                : null
            }
          />

          <Button
            type="submit"
            loading={busy}
            disabled={code.length !== VERIFICATION_CODE_LENGTH}
          >
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
