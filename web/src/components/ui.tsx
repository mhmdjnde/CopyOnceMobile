import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from "react";

export function cn(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(" ");
}

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost" | "danger";
  loading?: boolean;
};

export function Button({
  variant = "primary",
  loading = false,
  className,
  children,
  disabled,
  ...rest
}: ButtonProps) {
  const base =
    "inline-flex items-center justify-center gap-2 rounded-[--radius-m] px-4 py-2.5 text-sm font-semibold transition-colors disabled:opacity-50 disabled:cursor-not-allowed";

  const variants = {
    primary: "bg-brand text-white hover:bg-brand/90",
    secondary:
      "bg-surface text-ink hover:bg-surface/70 border border-divider",
    ghost: "text-ink-soft hover:text-ink hover:bg-surface",
    danger: "bg-danger text-white hover:bg-danger/90",
  } as const;

  return (
    <button
      className={cn(base, variants[variant], className)}
      disabled={disabled || loading}
      {...rest}
    >
      {loading && <Spinner />}
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
        "inline-block size-4 animate-spin rounded-full border-2 border-current border-t-transparent",
        className,
      )}
    />
  );
}

type FieldProps = InputHTMLAttributes<HTMLInputElement> & {
  label: string;
  hint?: string;
  error?: string | null;
};

export function Field({ label, hint, error, id, className, ...rest }: FieldProps) {
  const inputId = id ?? `field-${label.toLowerCase().replace(/\s+/g, "-")}`;
  const describedBy = error ? `${inputId}-error` : hint ? `${inputId}-hint` : undefined;

  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={inputId} className="text-sm font-medium text-ink">
        {label}
      </label>
      <input
        id={inputId}
        aria-describedby={describedBy}
        aria-invalid={error ? true : undefined}
        className={cn(
          "w-full rounded-[--radius-m] border bg-card px-3.5 py-2.5 text-sm text-ink placeholder:text-ink-faint",
          "focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent",
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
    <div
      className={cn(
        "rounded-[--radius-l] border border-divider bg-card",
        className,
      )}
    >
      {children}
    </div>
  );
}

/** Inline error banner. Never renders anything but the message it is given. */
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
      className="flex items-start gap-3 rounded-[--radius-m] border border-danger/30 bg-danger/10 px-4 py-3 text-sm text-danger"
    >
      <span className="flex-1">{message}</span>
      {onDismiss && (
        <button
          onClick={onDismiss}
          aria-label="Dismiss error"
          className="shrink-0 opacity-70 hover:opacity-100"
        >
          ✕
        </button>
      )}
    </div>
  );
}

export function EmptyState({
  icon,
  title,
  body,
  action,
}: {
  icon: ReactNode;
  title: string;
  body: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-20 text-center">
      <div className="flex size-16 items-center justify-center rounded-full bg-surface text-ink-faint">
        {icon}
      </div>
      <h2 className="text-lg font-semibold text-ink">{title}</h2>
      <p className="max-w-sm whitespace-pre-line text-sm leading-relaxed text-ink-soft">
        {body}
      </p>
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}

/** The CopyOnce wordmark, drawn rather than loaded so it themes with the page. */
export function Wordmark({ className }: { className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-2 font-semibold", className)}>
      <svg
        viewBox="0 0 24 24"
        fill="none"
        aria-hidden="true"
        className="size-5 text-accent"
      >
        <rect
          x="7" y="3" width="10" height="14" rx="2"
          stroke="currentColor" strokeWidth="1.8"
        />
        <path
          d="M5 7v12a2 2 0 0 0 2 2h8"
          stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"
        />
      </svg>
      <span>
        Copy<span className="text-accent">Once</span>
      </span>
    </span>
  );
}
