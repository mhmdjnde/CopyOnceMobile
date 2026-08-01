"use client";

import { useId, useState } from "react";
import {
  assessPassword,
  PASSWORD_RULES,
  RULE_LABELS,
  STRENGTH_LABELS,
  type PasswordStrength,
} from "@/lib/password-policy";
import { cn } from "./ui";

const STRENGTH_STYLE: Record<PasswordStrength, { bar: string; text: string; fill: string }> = {
  empty: { bar: "bg-divider", text: "text-ink-faint", fill: "w-0" },
  weak: { bar: "bg-danger", text: "text-danger", fill: "w-1/4" },
  fair: { bar: "bg-warning", text: "text-warning", fill: "w-2/4" },
  good: { bar: "bg-accent", text: "text-accent", fill: "w-3/4" },
  strong: { bar: "bg-success", text: "text-success", fill: "w-full" },
};

/**
 * Password entry with a live checklist and strength meter.
 *
 * Shows every outstanding requirement at once rather than revealing them one
 * refusal at a time — the same approach as PasswordStrengthField in the app, so
 * setting a password feels identical on both.
 */
export function PasswordField({
  label,
  value,
  onChange,
  email,
  autoComplete = "new-password",
  showChecklist = true,
  required = true,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  /** Checked against, so a password cannot just restate the address. */
  email?: string;
  autoComplete?: string;
  showChecklist?: boolean;
  required?: boolean;
}) {
  const id = useId();
  const [visible, setVisible] = useState(false);
  const [touched, setTouched] = useState(false);

  const assessment = assessPassword(value, email);
  const style = STRENGTH_STYLE[assessment.strength];
  const showRules = showChecklist && (touched || value.length > 0);

  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-sm font-medium text-ink">
        {label}
      </label>

      <div className="relative">
        <input
          id={id}
          type={visible ? "text" : "password"}
          value={value}
          required={required}
          autoComplete={autoComplete}
          onChange={(e) => onChange(e.target.value)}
          onBlur={() => setTouched(true)}
          aria-describedby={showRules ? `${id}-rules` : undefined}
          className="w-full rounded-[--radius-m] border border-divider bg-card px-3.5 py-2.5 pr-20 text-sm text-ink placeholder:text-ink-faint focus:border-transparent focus:outline-none focus:ring-2 focus:ring-accent"
        />
        <button
          type="button"
          onClick={() => setVisible((v) => !v)}
          className="absolute right-2 top-1/2 -translate-y-1/2 rounded-[--radius-s] px-2 py-1 text-xs font-medium text-ink-soft hover:bg-surface hover:text-ink"
          aria-label={visible ? "Hide password" : "Show password"}
        >
          {visible ? "Hide" : "Show"}
        </button>
      </div>

      {value.length > 0 && (
        <div className="flex items-center gap-2">
          <div className="h-1 flex-1 overflow-hidden rounded-full bg-divider">
            <div
              className={cn("h-full rounded-full transition-all", style.bar, style.fill)}
            />
          </div>
          <span className={cn("text-xs font-medium", style.text)}>
            {STRENGTH_LABELS[assessment.strength]}
          </span>
        </div>
      )}

      {showRules && (
        <ul id={`${id}-rules`} className="mt-1 flex flex-col gap-1">
          {PASSWORD_RULES.map((rule) => {
            const met = assessment.satisfied.has(rule);
            return (
              <li
                key={rule}
                className={cn(
                  "flex items-center gap-2 text-xs",
                  met ? "text-success" : "text-ink-faint",
                )}
              >
                <span aria-hidden className="w-3">
                  {met ? "✓" : "○"}
                </span>
                <span>{RULE_LABELS[rule]}</span>
                <span className="sr-only">{met ? "met" : "not met yet"}</span>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
