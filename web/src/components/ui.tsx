import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from "react";
import { AlertIcon, CloseIcon } from "./icons";

export function cn(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(" ");
}

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost" | "danger";
  loading?: boolean;
  icon?: ReactNode;
};

export function Button({
  variant = "primary",
  loading = false,
  icon,
  className,
  children,
  disabled,
  ...rest
}: ButtonProps) {
  const base =
    "inline-flex items-center justify-center gap-2 rounded-[--radius-m] px-4 py-2.5 text-sm font-semibold " +
    "transition-[background-color,border-color,color,transform] active:translate-y-px " +
    "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:translate-y-0";

  const variants = {
    primary: "bg-brand text-[var(--color-on-accent)] hover:opacity-90",
    secondary: "border border-divider bg-card text-ink hover:bg-surface",
    ghost: "text-ink-soft hover:bg-surface hover:text-ink",
    danger: "bg-danger text-white hover:opacity-90",
  } as const;

  return (
    <button
      className={cn(base, variants[variant], className)}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? <Spinner /> : icon}
      {children}
    </button>
  );
}

export function Spinner({ className }: { className?: string }) {
  return (
    <span
      role="status"
      aria-label="Loading"
      className={cn(
        "inline-block size-4 shrink-0 animate-spin rounded-full border-2 border-current border-t-transparent",
        className,
      )}
    />
  );
}

type FieldProps = InputHTMLAttributes<HTMLInputElement> & {
  label: string;
  hint?: string;
  error?: string | null;
  mono?: boolean;
};

export function Field({
  label,
  hint,
  error,
  id,
  className,
  mono = false,
  ...rest
}: FieldProps) {
  const inputId = id ?? `f-${label.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`;
  const describedBy = error ? `${inputId}-error` : hint ? `${inputId}-hint` : undefined;

  return (
    <div className="flex flex-col gap-1.5">
      <label
        htmlFor={inputId}
        className="text-xs font-semibold uppercase tracking-wider text-ink-soft"
      >
        {label}
      </label>
      <input
        id={inputId}
        aria-describedby={describedBy}
        aria-invalid={error ? true : undefined}
        className={cn(
          "w-full rounded-[--radius-m] border bg-card px-3.5 py-2.5 text-sm text-ink placeholder:text-ink-faint",
          "transition-colors focus:border-transparent focus:outline-none focus:ring-2 focus:ring-accent",
          mono && "font-mono tracking-tight",
          error ? "border-danger" : "border-divider",
          className,
        )}
        {...rest}
      />
      {hint && !error && (
        <p id={`${inputId}-hint`} className="text-xs text-ink-faint">
          {hint}
        </p>
      )}
      {error && (
        <p id={`${inputId}-error`} className="text-xs text-danger">
          {error}
        </p>
      )}
    </div>
  );
}

export function Card({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("rounded-[--radius-l] border border-divider bg-card", className)}>
      {children}
    </div>
  );
}

/** States an error plainly and says what to do, without apologising. */
export function ErrorBanner({
  message,
  onDismiss,
}: {
  message: string;
  onDismiss?: () => void;
}) {
  return (
    <div
      role="alert"
      className="flex items-start gap-2.5 rounded-[--radius-m] border border-danger/30 bg-danger/10 px-3.5 py-3 text-sm text-danger"
    >
      <AlertIcon size={17} className="mt-px shrink-0" />
      <span className="flex-1">{message}</span>
      {onDismiss && (
        <button onClick={onDismiss} aria-label="Dismiss" className="shrink-0 opacity-70 hover:opacity-100">
          <CloseIcon size={15} />
        </button>
      )}
    </div>
  );
}

export function Notice({ children }: { children: ReactNode }) {
  return (
    <div
      role="status"
      className="rounded-[--radius-m] border border-success/30 bg-success/10 px-3.5 py-3 text-sm text-success"
    >
      {children}
    </div>
  );
}

/** An empty screen is an invitation to act, so it always offers the next step. */
export function EmptyState({
  icon,
  title,
  body,
  action,
}: {
  icon: ReactNode;
  title: string;
  body: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-16 text-center">
      <div className="flex size-14 items-center justify-center rounded-2xl border border-divider bg-surface text-ink-faint">
        {icon}
      </div>
      <h2 className="font-display text-lg font-semibold text-ink">{title}</h2>
      <div className="max-w-sm text-sm leading-relaxed text-ink-soft">{body}</div>
      {action && <div className="mt-1">{action}</div>}
    </div>
  );
}

/** Placeholder rows, so a loading list occupies the space the real one will. */
export function SkeletonList({ rows = 4 }: { rows?: number }) {
  return (
    <ul className="flex flex-col gap-2.5" aria-hidden="true">
      {Array.from({ length: rows }).map((_, i) => (
        <li
          key={i}
          className="skeleton h-[92px] rounded-[--radius-l] border border-divider"
          style={{ animationDelay: `${i * 90}ms` }}
        />
      ))}
    </ul>
  );
}
