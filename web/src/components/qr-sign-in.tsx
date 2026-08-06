"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import QRCode from "qrcode";
import { createClient } from "@/lib/supabase/client";
import { Button, Spinner } from "./ui";
import { RefreshIcon } from "./icons";

type Phase = "idle" | "waiting" | "approved" | "expired" | "unavailable" | "failed";

/** Matches the two-minute window the server sets on the token. */
const POLL_MS = 2000;

/**
 * Sign in by scanning a code with the app.
 *
 * The browser never learns anything about the account until a signed-in device
 * approves: the QR carries an opaque token that grants nothing on its own. The
 * session that arrives is minted fresh for this browser, not borrowed from the
 * phone.
 */
export function QrSignIn({ onSignedIn }: { onSignedIn: () => void }) {
  const [phase, setPhase] = useState<Phase>("idle");
  const [dataUrl, setDataUrl] = useState<string | null>(null);
  const [secondsLeft, setSecondsLeft] = useState(0);
  const pollRef = useRef<number | null>(null);
  const tickRef = useRef<number | null>(null);

  const stop = useCallback(() => {
    if (pollRef.current) window.clearInterval(pollRef.current);
    if (tickRef.current) window.clearInterval(tickRef.current);
    pollRef.current = null;
    tickRef.current = null;
  }, []);

  useEffect(() => stop, [stop]);

  const begin = useCallback(async () => {
    stop();
    setPhase("idle");
    setDataUrl(null);

    const response = await fetch("/api/qr/start", { method: "POST" });
    if (response.status === 503) return setPhase("unavailable");
    if (!response.ok) return setPhase("failed");

    const { token, expiresInSeconds } = (await response.json()) as {
      token: string;
      expiresInSeconds: number;
    };

    // The QR carries a URL rather than a bare token so a phone camera that is
    // not the app still does something sensible instead of showing gibberish.
    const payload = `${window.location.origin}/link#${token}`;

    setDataUrl(
      await QRCode.toDataURL(payload, {
        margin: 1,
        width: 480,
        // Fixed black on white: a QR has to be readable by a camera, which is
        // not a place to express a colour scheme.
        color: { dark: "#0f120f", light: "#ffffff" },
      }),
    );
    setSecondsLeft(expiresInSeconds);
    setPhase("waiting");

    tickRef.current = window.setInterval(() => {
      setSecondsLeft((s) => {
        if (s <= 1) {
          stop();
          setPhase("expired");
          return 0;
        }
        return s - 1;
      });
    }, 1000);

    pollRef.current = window.setInterval(async () => {
      const poll = await fetch(`/api/qr/claim?token=${encodeURIComponent(token)}`);
      if (!poll.ok && poll.status !== 404) return;

      const result = (await poll.json()) as {
        status: string;
        tokenHash?: string;
        email?: string;
      };

      if (result.status === "waiting") return;
      stop();

      if (result.status === "approved" && result.tokenHash && result.email) {
        const supabase = createClient();
        const { error } = await supabase.auth.verifyOtp({
          type: "magiclink",
          token_hash: result.tokenHash,
        });
        if (error) return setPhase("failed");
        setPhase("approved");
        onSignedIn();
        return;
      }

      setPhase(result.status === "expired" ? "expired" : "failed");
    }, POLL_MS);
  }, [stop, onSignedIn]);

  if (phase === "unavailable") return null;

  return (
    <div className="flex flex-col items-center gap-4 rounded-[--radius-l] border border-divider bg-card p-5 text-center">
      <div>
        <h2 className="font-display text-sm font-semibold text-ink">
          Sign in with your phone
        </h2>
        <p className="mt-1 text-xs leading-relaxed text-ink-soft">
          Open CopyOnce on a phone that is already signed in, and scan this.
        </p>
      </div>

      {phase === "idle" && !dataUrl && (
        <Button variant="secondary" onClick={begin}>
          Show a code
        </Button>
      )}

      {dataUrl && phase === "waiting" && (
        <>
          {/* White plate always: a camera needs the contrast, whatever the theme. */}
          <div className="rounded-[--radius-m] bg-white p-3">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={dataUrl} alt="Sign-in QR code" className="size-44" />
          </div>
          <p className="flex items-center gap-2 text-xs text-ink-faint">
            <Spinner className="size-3" />
            Waiting for approval · {secondsLeft}s
          </p>
        </>
      )}

      {phase === "approved" && (
        <p className="text-sm font-medium text-success">Approved — signing you in…</p>
      )}

      {(phase === "expired" || phase === "failed") && (
        <>
          <p className="text-sm text-ink-soft">
            {phase === "expired"
              ? "That code expired."
              : "That did not work. Try once more."}
          </p>
          <Button variant="secondary" icon={<RefreshIcon size={15} />} onClick={begin}>
            New code
          </Button>
        </>
      )}
    </div>
  );
}
