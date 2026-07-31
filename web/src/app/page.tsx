import Link from "next/link";
import { Button, Wordmark } from "@/components/ui";

/**
 * Landing page.
 *
 * The copy deliberately does not claim end-to-end encryption. Traffic is
 * encrypted and rows are owner-scoped by RLS, but content is readable at rest
 * by the database — see the note at the top of
 * supabase/migrations/0002_clipboard.sql. Claiming more would be a privacy
 * promise the backend does not currently keep.
 */
export default function LandingPage() {
  const features = [
    {
      title: "Text, links, and images",
      body: "Paste anything with Ctrl+V — including screenshots.",
    },
    {
      title: "Every device you own",
      body: "Android, iOS, Windows, macOS, and Linux, through any browser.",
    },
    {
      title: "Images don't linger",
      body: "An image clears once your devices have it, or after 24 hours.",
    },
  ];

  return (
    <main className="flex flex-1 flex-col">
      <header className="mx-auto flex w-full max-w-5xl items-center justify-between px-6 py-6">
        <Wordmark className="text-lg text-ink" />
        <nav className="flex items-center gap-2">
          <Link href="/sign-in">
            <Button variant="ghost">Sign in</Button>
          </Link>
          <Link href="/sign-up">
            <Button variant="primary">Get started</Button>
          </Link>
        </nav>
      </header>

      <section className="mx-auto flex w-full max-w-3xl flex-1 flex-col items-center justify-center gap-6 px-6 py-16 text-center">
        <h1 className="text-4xl font-bold leading-tight tracking-tight text-ink sm:text-5xl">
          Copy once,
          <br />
          access everywhere.
        </h1>
        <p className="max-w-xl text-lg leading-relaxed text-ink-soft">
          Your clipboard, shared between your own devices. Copy on your phone,
          paste on your laptop — text, links, and images.
        </p>

        <div className="flex flex-col gap-3 sm:flex-row">
          <Link href="/sign-up">
            <Button variant="primary" className="w-full px-6 py-3 sm:w-auto">
              Get started
            </Button>
          </Link>
          <Link href="/sign-in">
            <Button variant="secondary" className="w-full px-6 py-3 sm:w-auto">
              I already have an account
            </Button>
          </Link>
        </div>

        <ul className="mt-8 grid w-full gap-4 text-left sm:grid-cols-3">
          {features.map((feature) => (
            <li
              key={feature.title}
              className="rounded-[--radius-l] border border-divider bg-card p-4"
            >
              <h2 className="text-sm font-semibold text-ink">{feature.title}</h2>
              <p className="mt-1 text-sm leading-relaxed text-ink-soft">
                {feature.body}
              </p>
            </li>
          ))}
        </ul>
      </section>

      <footer className="mx-auto w-full max-w-5xl px-6 py-8 text-center text-xs text-ink-faint">
        Your clipboard is private to your account. Traffic is encrypted in
        transit.
      </footer>
    </main>
  );
}
