"use client";

import { useCallback, useSyncExternalStore } from "react";
import { MonitorIcon, MoonIcon, SunIcon } from "./icons";
import { cn } from "./ui";

type Choice = "system" | "light" | "dark";

const KEY = "copyonce.theme";

const OPTIONS: Array<{ value: Choice; label: string; Icon: typeof SunIcon }> = [
  { value: "light", label: "Light", Icon: SunIcon },
  { value: "system", label: "Match system", Icon: MonitorIcon },
  { value: "dark", label: "Dark", Icon: MoonIcon },
];

// localStorage is an external store, so React reads it as one. The server has
// no localStorage, so its snapshot is always "system" — the blocking script in
// the document head has already applied the real attribute by then, leaving
// nothing to correct.
const listeners = new Set<() => void>();
function subscribe(listener: () => void) {
  listeners.add(listener);
  window.addEventListener("storage", listener);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", listener);
  };
}
function readChoice(): Choice {
  const stored = localStorage.getItem(KEY);
  return stored === "light" || stored === "dark" ? stored : "system";
}

/**
 * Light / system / dark, remembered on this device.
 *
 * "System" clears the override rather than storing a resolved value, so a
 * laptop that switches at sunset still follows along.
 */
export function ThemeToggle({ compact = false }: { compact?: boolean }) {
  const choice = useSyncExternalStore(subscribe, readChoice, () => "system" as Choice);

  const apply = useCallback((next: Choice) => {
    if (next === "system") {
      localStorage.removeItem(KEY);
      document.documentElement.removeAttribute("data-theme");
    } else {
      localStorage.setItem(KEY, next);
      document.documentElement.setAttribute("data-theme", next);
    }
    for (const listener of listeners) listener();
  }, []);

  return (
    <div
      role="radiogroup"
      aria-label="Colour theme"
      className={cn(
        "inline-flex items-center gap-0.5 rounded-full border border-divider bg-card p-0.5",
        compact && "scale-95",
      )}
    >
      {OPTIONS.map(({ value, label, Icon }) => (
        <button
          key={value}
          role="radio"
          aria-checked={choice === value}
          aria-label={label}
          title={label}
          onClick={() => apply(value)}
          className={cn(
            "flex size-7 items-center justify-center rounded-full transition-colors",
            choice === value
              ? "bg-accent text-[var(--color-on-accent)]"
              : "text-ink-faint hover:text-ink",
          )}
        >
          <Icon size={15} />
        </button>
      ))}
    </div>
  );
}
