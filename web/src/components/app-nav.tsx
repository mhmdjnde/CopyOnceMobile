"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Wordmark, cn } from "./ui";

const TABS = [
  { href: "/clipboard", label: "Clipboard" },
  { href: "/clipboard/devices", label: "Devices" },
  { href: "/clipboard/settings", label: "Settings" },
] as const;

export function AppNav({ email }: { email: string }) {
  const pathname = usePathname();
  const router = useRouter();

  async function signOut() {
    await createClient().auth.signOut();
    router.push("/sign-in");
    router.refresh();
  }

  return (
    <header className="sticky top-0 z-20 border-b border-divider bg-canvas/85 backdrop-blur">
      <div className="mx-auto flex w-full max-w-4xl items-center justify-between gap-4 px-4 py-3 sm:px-6">
        <Link href="/clipboard">
          <Wordmark className="text-base text-ink" />
        </Link>

        <nav className="flex items-center gap-1" aria-label="Main">
          {TABS.map((tab) => {
            const active =
              tab.href === "/clipboard"
                ? pathname === "/clipboard"
                : pathname.startsWith(tab.href);

            return (
              <Link
                key={tab.href}
                href={tab.href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "rounded-[--radius-m] px-3 py-1.5 text-sm font-medium transition-colors",
                  active
                    ? "bg-surface text-ink"
                    : "text-ink-soft hover:bg-surface/60 hover:text-ink",
                )}
              >
                {tab.label}
              </Link>
            );
          })}
        </nav>

        <div className="flex items-center gap-3">
          <span
            className="hidden max-w-[14rem] truncate text-xs text-ink-faint sm:block"
            title={email}
          >
            {email}
          </span>
          <button
            onClick={signOut}
            className="rounded-[--radius-m] px-2.5 py-1.5 text-sm text-ink-soft hover:bg-surface hover:text-ink"
          >
            Sign out
          </button>
        </div>
      </div>
    </header>
  );
}
