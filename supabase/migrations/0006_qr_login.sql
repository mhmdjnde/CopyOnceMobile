-- CopyOnce — sign in by scanning a code.
--
-- The site shows a QR, a signed-in phone scans and approves it, and the site
-- receives a session. The phone never hands over its own credentials: it
-- approves a request, and the server mints a fresh session for the browser.
--
-- Every row here is written and read by the server with the service role.
-- Clients get no access at all — see the RLS section. A token that a browser
-- could read would let anyone who guessed one wait for someone else's approval.

create table if not exists public.login_tokens (
  id uuid primary key default gen_random_uuid(),

  -- What the QR carries. Random, opaque, and useless until approved.
  token text not null unique check (char_length(token) between 32 and 128),

  -- Who approved it. Null until a signed-in device says yes.
  approved_by uuid references auth.users (id) on delete cascade,
  approved_at timestamptz,

  -- Set the moment the session is handed to the browser, so a token cannot be
  -- redeemed twice even if it is intercepted afterwards.
  claimed_at timestamptz,

  -- Shown to the person approving, so they can tell their own laptop from
  -- someone else's. A QR login is only as safe as the approver's ability to
  -- recognise what they are approving.
  requester_label text check (
    requester_label is null or char_length(requester_label) <= 120
  ),

  created_at timestamptz not null default now(),

  -- Two minutes. Long enough to pick up a phone, short enough that a code
  -- photographed off a screen is worthless by the time it is used.
  expires_at timestamptz not null default now() + interval '2 minutes'
);

create index if not exists login_tokens_token_idx on public.login_tokens (token);
create index if not exists login_tokens_expiry_idx on public.login_tokens (expires_at);

alter table public.login_tokens enable row level security;

-- No policies, deliberately.
--
-- RLS with zero policies denies everything to `anon` and `authenticated`. The
-- service role bypasses RLS, so the server still works. This is the whole
-- security model: a browser cannot read, poll, or forge a token row directly.
revoke all on public.login_tokens from anon, authenticated;

-- ── Housekeeping ──────────────────────────────────────────────────────────────
-- Expired and spent tokens have no value and should not accumulate. Called by
-- the server on each new request, which is often enough for a table this small
-- and avoids depending on a scheduled job.
create or replace function public.purge_login_tokens()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.login_tokens
  where expires_at < now() - interval '1 hour'
     or claimed_at < now() - interval '1 hour';
$$;

revoke all on function public.purge_login_tokens() from public, anon, authenticated;
