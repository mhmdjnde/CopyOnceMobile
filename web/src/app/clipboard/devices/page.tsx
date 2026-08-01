"use client";

import { useCopyOnce } from "@/lib/copyonce-provider";
import { getInstallId, formatTimestamp } from "@/lib/clipboard";
import { Button, Card, EmptyState, Spinner } from "@/components/ui";
import { useSyncExternalStore } from "react";

/**
 * This browser's install id, read safely across the server/client boundary.
 *
 * localStorage does not exist during server rendering, so the server snapshot
 * is null and the client fills it in — useSyncExternalStore is built for
 * exactly this, and avoids both a hydration mismatch and a setState-in-effect.
 */
const NOOP_SUBSCRIBE = () => () => {};

function useInstallId(): string | null {
  return useSyncExternalStore(
    NOOP_SUBSCRIBE,
    () => getInstallId(),
    () => null,
  );
}

const PLATFORM_ICON: Record<string, string> = {
  ios: "",
  android: "🤖",
  macos: "🖥",
  windows: "🪟",
  linux: "🐧",
};

export default function DevicesPage() {
  const { devices, removeDevice, status } = useCopyOnce();

  const installId = useInstallId();

  if (status === "loading" && devices.length === 0) {
    return (
      <div className="flex justify-center py-20">
        <Spinner className="size-6 text-accent" />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4 py-5">
      <div>
        <h1 className="text-xl font-bold text-ink">Your devices</h1>
        <p className="mt-1 text-sm text-ink-soft">
          Everything signed in to this account. Images relay until every device
          here has fetched them.
        </p>
      </div>

      {devices.length === 0 ? (
        <EmptyState
          icon={<span aria-hidden>💻</span>}
          title="No devices yet"
          body="Sign in on another device and it appears here."
        />
      ) : (
        <ul className="flex flex-col gap-2.5">
          {devices.map((device) => {
            const isThis = device.install_id === installId;
            return (
              <li key={device.id}>
                <Card className="flex items-center gap-3 p-4">
                  <span className="text-xl" aria-hidden>
                    {PLATFORM_ICON[device.platform] ?? "💻"}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-ink">
                      {device.name}
                      {isThis && (
                        <span className="ml-2 rounded-[--radius-s] bg-success/15 px-1.5 py-0.5 text-[11px] font-semibold text-success">
                          This device
                        </span>
                      )}
                    </p>
                    <p className="mt-0.5 text-xs text-ink-faint">
                      Last seen {formatTimestamp(device.last_seen_at)}
                    </p>
                  </div>
                  {!isThis && (
                    <Button
                      variant="ghost"
                      onClick={() => void removeDevice(device.id)}
                    >
                      Forget
                    </Button>
                  )}
                </Card>
              </li>
            );
          })}
        </ul>
      )}

      <p className="text-xs leading-relaxed text-ink-faint">
        Forgetting a device is a tidy-up, not a way to revoke access — it
        reappears next time that device connects. Changing your password is what
        signs it out.
      </p>
    </div>
  );
}
