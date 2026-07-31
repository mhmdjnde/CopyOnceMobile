# Supabase deployment

Migrations are applied in filename order. Everything here is idempotent — each
file can be re-run without damage — but they must go in order, because 0003
depends on `has_required_assurance()` from 0002.

## Applying migrations

With the CLI (not currently installed on the dev machine):

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

Without the CLI: paste each file into the dashboard SQL editor, oldest first.

| File | What it does | Safe to re-run |
|---|---|---|
| `0001_init_profiles.sql` | Profiles, auto-created on sign-up | yes |
| `0002_clipboard.sql` | Clipboard items, devices, settings, retention | yes |
| `0003_media.sql` | Image relay: columns, deliveries, quota, bucket, policies | yes |
| `0004_media_reaper_schedule.sql` | pg_cron job for the reaper | yes, **apply last** |

0003 is additive only — it adds columns, tables, constraints, and policies. It
drops nothing and touches no existing rows.

## Before 0004

0004 schedules a job that posts to the `reap-media` Edge Function. Deploy the
function and create its two vault secrets first, or the cron log fills with
failures against a URL that is not there yet.

```bash
supabase functions deploy reap-media
```

Then, once, in the SQL editor with real values:

```sql
select vault.create_secret(
  'https://<project-ref>.supabase.co/functions/v1/reap-media',
  'reap_media_url'
);
select vault.create_secret('<service-role-key>', 'reap_media_key');
```

The service role key must never reach the Flutter app. It lives in the vault and
is read at call time; that is the only place it belongs.

## Verifying

The relay's logic — delete-on-delivery, the quota, every constraint — is covered
by `tests/media_relay_test.sql`, which runs against a throwaway local Postgres
rather than your project:

```bash
initdb -D /tmp/copyonce-pg/data -U postgres --auth=trust
pg_ctl -D /tmp/copyonce-pg/data -o "-p 55433" -l /tmp/copyonce-pg/pg.log start
psql -p 55433 -U postgres -f tests/supabase_stubs.sql
psql -p 55433 -U postgres -f migrations/0001_init_profiles.sql
psql -p 55433 -U postgres -f migrations/0002_clipboard.sql
psql -p 55433 -U postgres -f migrations/0003_media.sql
psql -p 55433 -U postgres -f tests/media_relay_test.sql
```

`tests/supabase_stubs.sql` stands in for the Supabase-managed schemas (`auth`,
`storage`) that a plain Postgres does not have. It exists so the migrations can
be exercised offline; it is never applied to a real project.

Expect 17 `PASS` lines and `--- all behaviour checks passed ---`.

## What the reaper guarantees, and when

Two tiers, deliberately:

- **The client** clears its own account's finished images on launch. Works with
  no deployment at all, which is why the feature is correct before 0004 is
  applied. Only runs when someone opens the app.
- **`reap-media` on a 5-minute cron** clears every account whether or not anyone
  opens the app, and sweeps orphaned files.

Keep both. Free-tier projects pause after about a week idle and cron does not run
while paused — the client tier is what covers that gap.
