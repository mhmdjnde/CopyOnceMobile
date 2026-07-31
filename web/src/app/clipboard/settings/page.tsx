"use client";

import { useState } from "react";
import { useCopyOnce } from "@/lib/copyonce-provider";
import { RETENTION_OPTIONS } from "@/lib/types";
import { Button, Card, Spinner } from "@/components/ui";

export default function SettingsPage() {
  const { settings, saveSettings, clearHistory } = useCopyOnce();
  const [confirmingClear, setConfirmingClear] = useState(false);

  if (!settings) {
    return (
      <div className="flex justify-center py-20">
        <Spinner className="size-6 text-accent" />
      </div>
    );
  }

  const toggles = [
    {
      key: "capture_text" as const,
      label: "Capture text",
      hint: "Save plain text you copy.",
    },
    {
      key: "capture_links" as const,
      label: "Capture links",
      hint: "Save URLs you copy.",
    },
    {
      key: "capture_images" as const,
      label: "Capture images",
      hint: "Allow images to relay to this account.",
    },
    {
      key: "sync_alerts" as const,
      label: "Sync alerts",
      hint: "Announce items arriving from another device.",
    },
  ];

  return (
    <div className="flex flex-col gap-5 py-5">
      <div>
        <h1 className="text-xl font-bold text-ink">Settings</h1>
        <p className="mt-1 text-sm text-ink-soft">
          These apply to your account, so they follow you to every device.
        </p>
      </div>

      <Card className="divide-y divide-divider">
        {toggles.map((toggle) => (
          <label
            key={toggle.key}
            className="flex cursor-pointer items-center gap-4 p-4"
          >
            <div className="flex-1">
              <p className="text-sm font-medium text-ink">{toggle.label}</p>
              <p className="mt-0.5 text-xs text-ink-faint">{toggle.hint}</p>
            </div>
            <input
              type="checkbox"
              checked={settings[toggle.key]}
              onChange={(e) =>
                void saveSettings({ [toggle.key]: e.target.checked })
              }
              className="size-5 accent-[var(--color-accent)]"
            />
          </label>
        ))}
      </Card>

      <Card className="p-4">
        <label htmlFor="retention" className="text-sm font-medium text-ink">
          Keep history for
        </label>
        <p className="mt-0.5 text-xs text-ink-faint">
          Text and links older than this are removed. Images ignore this — they
          always clear once delivered, or after 24 hours.
        </p>
        <select
          id="retention"
          value={settings.retention_days}
          onChange={(e) =>
            void saveSettings({ retention_days: Number(e.target.value) })
          }
          className="mt-3 w-full rounded-[--radius-m] border border-divider bg-card px-3.5 py-2.5 text-sm text-ink focus:outline-none focus:ring-2 focus:ring-accent"
        >
          {RETENTION_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </Card>

      <Card className="border-danger/30 p-4">
        <p className="text-sm font-medium text-ink">Clear synced history</p>
        <p className="mt-0.5 text-xs leading-relaxed text-ink-faint">
          Deletes every item stored for this account, on all devices. Your
          device&apos;s own clipboard is left alone. This cannot be undone.
        </p>

        {confirmingClear ? (
          <div className="mt-3 flex gap-2">
            <Button
              variant="danger"
              onClick={async () => {
                await clearHistory();
                setConfirmingClear(false);
              }}
            >
              Yes, delete everything
            </Button>
            <Button variant="ghost" onClick={() => setConfirmingClear(false)}>
              Cancel
            </Button>
          </div>
        ) : (
          <Button
            variant="secondary"
            className="mt-3"
            onClick={() => setConfirmingClear(true)}
          >
            Clear history
          </Button>
        )}
      </Card>
    </div>
  );
}
