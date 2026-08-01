import Link from "next/link";
import { Button } from "@/components/ui";
import { ThemeToggle } from "@/components/theme-toggle";
import { DevicesIcon, ImageIcon, Keycap, TextIcon } from "@/components/icons";

/**
 * Landing page.
 *
 * The hero is the gesture, not a headline about it: two keycaps, the thing you
 * actually press. CopyOnce is one motion repeated on every device you own, so
 * the key is the honest opening image.
 *
 * The copy does not claim end-to-end encryption. Traffic is encrypted and rows
 * are owner-scoped by RLS, but content is readable at rest by the database —
 * see the note atop supabase/migrations/0002_clipboard.sql.
 */
export default function LandingPage() {
  const features = [
    {
      Icon: TextIcon,
      title: "Text and links",
      body: "Copy on one device, paste on another. Nothing to press on the other end.",
    },
    {
      Icon: ImageIcon,
      title: "Images that clear themselves",
      body: "An image stays until your devices have it, then goes. 24 hours at the outside.",
    },
    {
      Icon: DevicesIcon,
      title: "Everything you own",
      body: "Android and iOS, plus any browser on Windows, macOS, or Linux.",
    },
  ];

  return (
    <main className="flex flex-1 flex-col">
      <header className="mx-auto flex w-full max-w-5xl items-center justify-between px-6 py-5">
        <span className="flex items-center gap-2.5">
          <Keycap label="V" size={30} />
          <span className="font-display text-[17px] font-bold tracking-tight text-ink">
            Copy<span className="text-accent">Once</span>
          </span>
        </span>
        <div className="flex items-center gap-3">
          <ThemeToggle />
          <Link href="/sign-in">
            <Button variant="ghost">Sign in</Button>
          </Link>
        </div>
      </header>

      <section className="mx-auto flex w-full max-w-3xl flex-1 flex-col items-center justify-center gap-8 px-6 py-14 text-center">
        {/* The gesture itself, at hero scale. */}
        <div className="flex items-end gap-2" aria-hidden="true">
          <Keycap label="⌘" size={72} />
          <Keycap label="V" size={92} />
        </div>

        <div className="flex flex-col gap-4">
          <h1 className="font-display text-4xl font-bold leading-[1.05] tracking-tight text-ink sm:text-6xl">
            One clipboard.
            <br />
            Every device.
          </h1>
          <p className="mx-auto max-w-lg text-lg leading-relaxed text-ink-soft">
            Copy on your phone. Paste on your laptop. CopyOnce carries text,
            links, and images between the devices you already own.
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <Link href="/sign-up">
            <Button variant="primary" className="w-full px-7 py-3 text-base sm:w-auto">
              Get started
            </Button>
          </Link>
          <Link href="/sign-in">
            <Button variant="secondary" className="w-full px-7 py-3 text-base sm:w-auto">
              I have an account
            </Button>
          </Link>
        </div>

        <ul className="mt-6 grid w-full gap-3 text-left sm:grid-cols-3">
          {features.map(({ Icon, title, body }) => (
            <li
              key={title}
              className="rounded-[--radius-l] border border-divider bg-card p-4"
            >
              <Icon size={19} className="text-accent" />
              <h2 className="mt-2.5 font-display text-sm font-semibold text-ink">
                {title}
              </h2>
              <p className="mt-1 text-[13px] leading-relaxed text-ink-soft">{body}</p>
            </li>
          ))}
        </ul>
      </section>

      <footer className="mx-auto w-full max-w-5xl px-6 py-8 text-center text-xs text-ink-faint">
        Your clipboard is private to your account. Traffic is encrypted in transit.
      </footer>
    </main>
  );
}
