"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, ErrorBanner, Field, Spinner } from "@/components/ui";
import { PasswordField } from "@/components/password-field";
import { validatePassword } from "@/lib/password-policy";
import { AUTHENTICATOR_CODE_LENGTH } from "@/lib/types";

interface Factor {
  id: string;
  friendly_name?: string;
}

export default function SecurityPage() {
  const supabase = createClient();

  const [factors, setFactors] = useState<Factor[]>([]);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refreshFactors = useCallback(async () => {
    const { data } = await supabase.auth.mfa.listFactors();
    setFactors((data?.totp ?? []) as Factor[]);
    setLoading(false);
  }, [supabase]);

  // Subscribing to an external system (the auth service) is what effects are
  // for. The state lands in the promise callback, not in the effect body.
  useEffect(() => {
    let cancelled = false;

    supabase.auth.mfa
      .listFactors()
      .then(({ data }) => {
        if (cancelled) return;
        setFactors((data?.totp ?? []) as Factor[]);
        setLoading(false);
      })
      .catch(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [supabase]);

  return (
    <div className="flex flex-col gap-5 py-5">
      <div>
        <h1 className="text-xl font-bold text-ink">Security</h1>
        <p className="mt-1 text-sm text-ink-soft">
          Your clipboard is only as private as this account.
        </p>
      </div>

      {notice && (
        <div
          role="status"
          className="rounded-[--radius-m] border border-success/30 bg-success/10 px-4 py-3 text-sm text-success"
        >
          {notice}
        </div>
      )}
      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      <ChangePassword onDone={setNotice} onError={setError} />

      {loading ? (
        <Card className="flex justify-center p-8">
          <Spinner className="size-5 text-accent" />
        </Card>
      ) : (
        <TwoFactor
          factors={factors}
          onChanged={refreshFactors}
          onDone={setNotice}
          onError={setError}
        />
      )}
    </div>
  );
}

function ChangePassword({
  onDone,
  onError,
}: {
  onDone: (message: string) => void;
  onError: (message: string) => void;
}) {
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const problem = validatePassword(password);
    if (problem) return onError(problem);
    if (password !== confirm) return onError("Those passwords do not match.");

    setBusy(true);
    const { error } = await createClient().auth.updateUser({ password });
    setBusy(false);

    if (error) return onError(error.message);

    setPassword("");
    setConfirm("");
    onDone("Password updated. Your other devices will need to sign in again.");
  }

  return (
    <Card className="p-4">
      <h2 className="text-sm font-semibold text-ink">Change password</h2>
      <form onSubmit={handleSubmit} className="mt-3 flex flex-col gap-4">
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
        <Button type="submit" loading={busy} className="self-start">
          Update password
        </Button>
      </form>
    </Card>
  );
}

/**
 * TOTP enrolment.
 *
 * Worth being precise about why this matters here: the database's
 * has_required_assurance() refuses to return a clipboard row below aal2 once a
 * verified factor exists. Turning this on genuinely gates the data, not just
 * the screens.
 */
function TwoFactor({
  factors,
  onChanged,
  onDone,
  onError,
}: {
  factors: Factor[];
  onChanged: () => Promise<void>;
  onDone: (message: string) => void;
  onError: (message: string) => void;
}) {
  const supabase = createClient();

  const [enrolling, setEnrolling] = useState<{
    factorId: string;
    qr: string;
    secret: string;
  } | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);

  const enrolled = factors.length > 0;

  async function startEnrol() {
    setBusy(true);
    const { data, error } = await supabase.auth.mfa.enroll({
      factorType: "totp",
      friendlyName: `CopyOnce web ${new Date().toISOString().slice(0, 10)}`,
    });
    setBusy(false);

    if (error || !data) return onError(error?.message ?? "Could not start setup.");

    setEnrolling({
      factorId: data.id,
      qr: data.totp.qr_code,
      secret: data.totp.secret,
    });
  }

  async function confirmEnrol(event: React.FormEvent) {
    event.preventDefault();
    if (!enrolling) return;

    setBusy(true);
    const { data: challenge, error: challengeError } =
      await supabase.auth.mfa.challenge({ factorId: enrolling.factorId });

    if (challengeError || !challenge) {
      setBusy(false);
      return onError("Could not start verification. Please try again.");
    }

    const { error: verifyError } = await supabase.auth.mfa.verify({
      factorId: enrolling.factorId,
      challengeId: challenge.id,
      code: code.trim(),
    });
    setBusy(false);

    if (verifyError) {
      setCode("");
      return onError("That code was not accepted. Try the next one.");
    }

    setEnrolling(null);
    setCode("");
    await onChanged();
    onDone("Two-factor authentication is on.");
  }

  async function removeFactor(factorId: string) {
    setBusy(true);
    const { error } = await supabase.auth.mfa.unenroll({ factorId });
    setBusy(false);

    if (error) return onError(error.message);
    await onChanged();
    onDone("Two-factor authentication is off.");
  }

  return (
    <Card className="p-4">
      <div className="flex items-start gap-3">
        <div className="flex-1">
          <h2 className="text-sm font-semibold text-ink">
            Two-factor authentication
          </h2>
          <p className="mt-0.5 text-xs leading-relaxed text-ink-faint">
            {enrolled
              ? "On. Your clipboard stays locked until you enter a code, on every device."
              : "Add a code from an authenticator app on top of your password."}
          </p>
        </div>
        {enrolled && !enrolling && (
          <span className="rounded-[--radius-s] bg-success/15 px-2 py-0.5 text-[11px] font-semibold text-success">
            On
          </span>
        )}
      </div>

      {enrolling ? (
        <form onSubmit={confirmEnrol} className="mt-4 flex flex-col gap-4">
          <p className="text-sm text-ink-soft">
            Scan this with your authenticator app, then enter the code it shows.
          </p>

          {/* Supabase returns the QR as an SVG data URL. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={enrolling.qr}
            alt="Two-factor setup QR code"
            className="size-44 self-start rounded-[--radius-m] bg-white p-2"
          />

          <details className="text-xs text-ink-faint">
            <summary className="cursor-pointer">
              Can&apos;t scan? Enter this key by hand
            </summary>
            <code className="mt-2 block break-all rounded-[--radius-s] bg-surface p-2 text-ink">
              {enrolling.secret}
            </code>
          </details>

          <Field
            label="Code from your app"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={AUTHENTICATOR_CODE_LENGTH}
            required
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            placeholder="000000"
          />

          <div className="flex gap-2">
            <Button type="submit" loading={busy} disabled={code.length !== AUTHENTICATOR_CODE_LENGTH}>
              Turn on
            </Button>
            <Button
              type="button"
              variant="ghost"
              onClick={() => {
                setEnrolling(null);
                setCode("");
              }}
            >
              Cancel
            </Button>
          </div>
        </form>
      ) : (
        <div className="mt-3">
          {enrolled ? (
            <Button
              variant="secondary"
              loading={busy}
              onClick={() => void removeFactor(factors[0].id)}
            >
              Turn off
            </Button>
          ) : (
            <Button variant="primary" loading={busy} onClick={startEnrol}>
              Set up
            </Button>
          )}
        </div>
      )}
    </Card>
  );
}
