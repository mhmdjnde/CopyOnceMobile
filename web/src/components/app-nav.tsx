"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { ThemeToggle } from "./theme-toggle";
import { cn } from "./ui";
import {
  DevicesIcon,
  Keycap,
  ShieldIcon,
  SignOutIcon,
  SlidersIcon,
  TextIcon,
} from "./icons";

const TABS = [
  { href: "/clipboard", label: "Clipboard", Icon: TextIcon },
  { href: "/clipboard/devices", label: "Devices", Icon: DevicesIcon },
  { href: "/clipboard/security", label: "Security", Icon: ShieldIcon },
  { href: "/clipboard/settings", label: "Settings", Icon: SlidersIcon },
] as const;

function useIsActive() {
  const pathname = usePathname();
  return (href: string) =>
    href === "/clipboard" ? pathname === "/clipboard" : pathname.startsWith(href);
}

/**
 * A rail on desktop, a bar along the bottom on a phone.
 *
 * Both render from the same list, and both mount at once — the rail hides below
 * `md`, the bar hides above it. Nothing re-renders on a breakpoint change, and
 * there is only one place to add a destination.
 */
export function AppNav({ email }: { email: string }) {
  const router = useRouter();
  const isActive = useIsActive();

  async function signOut() {
    await createClient().auth.signOut();
    router.push("/sign-in");
    router.refresh();
  }

  return (
    <>
      {/* Desktop rail */}
      <aside className="fixed inset-y-0 left-0 z-20 hidden w-56 flex-col border-r border-divider bg-card px-3 py-5 md:flex">
        <Link href="/clipboard" className="mb-7 flex items-center gap-2.5 px-2">
          <Keycap label="V" size={30} />
          <span className="font-display text-[17px] font-bold tracking-tight text-ink">
            Copy<span className="text-accent">Once</span>
          </span>
        </Link>

        <nav aria-label="Main" className="flex flex-col gap-0.5">
          {TABS.map(({ href, label, Icon }) => {
            const active = isActive(href);
            return (
              <Link
                key={href}
                href={href}
                prefetch
                aria-current={active ? "page" : undefined}
                className={cn(
                  "flex items-center gap-3 rounded-[--radius-m] px-3 py-2.5 text-sm font-medium transition-colors",
                  active
                    ? "bg-surface text-ink"
                    : "text-ink-soft hover:bg-surface/60 hover:text-ink",
                )}
              >
                <Icon size={18} />
                {label}
              </Link>
            );
          })}
        </nav>

        <div className="mt-auto flex flex-col gap-3 px-1">
          <ThemeToggle />
          <p className="truncate px-1 text-xs text-ink-faint" title={email}>
            {email}
          </p>
          <button
            onClick={signOut}
            className="flex items-center gap-2.5 rounded-[--radius-m] px-2 py-2 text-sm text-ink-soft hover:bg-surface hover:text-ink"
          >
            <SignOutIcon size={17} />
            Sign out
          </button>
        </div>
      </aside>

      {/* Phone: a compact header for identity and theme… */}
      <header className="sticky top-0 z-20 flex items-center justify-between border-b border-divider bg-canvas/90 px-4 py-2.5 backdrop-blur md:hidden">
        <Link href="/clipboard" className="flex items-center gap-2">
          <Keycap label="V" size={24} />
          <span className="font-display text-[15px] font-bold text-ink">
            Copy<span className="text-accent">Once</span>
          </span>
        </Link>
        <div className="flex items-center gap-2">
          <ThemeToggle compact />
          <button
            onClick={signOut}
            aria-label="Sign out"
            className="flex size-8 items-center justify-center rounded-full text-ink-faint hover:bg-surface hover:text-ink"
          >
            <SignOutIcon size={17} />
          </button>
        </div>
      </header>

      {/* …and a bar at the bottom, where a thumb reaches. */}
      <nav
        aria-label="Main"
        className="fixed inset-x-0 bottom-0 z-20 flex border-t border-divider bg-card pb-[env(safe-area-inset-bottom)] md:hidden"
      >
        {TABS.map(({ href, label, Icon }) => {
          const active = isActive(href);
          return (
            <Link
              key={href}
              href={href}
              prefetch
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex flex-1 flex-col items-center gap-1 py-2.5 text-[11px] font-medium transition-colors",
                active ? "text-accent" : "text-ink-faint",
              )}
            >
              <Icon size={19} />
              {label}
            </Link>
          );
        })}
      </nav>
    </>
  );
}
