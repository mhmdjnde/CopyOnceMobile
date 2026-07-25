-- CopyOnce — clipboard, devices, and per-user sync settings.
--
-- Every table is owner-scoped through Row Level Security: the publishable key
-- ships inside the app, so RLS is the only thing standing between one user's
-- clipboard and another's.
--
-- Not encrypted at rest beyond Postgres' own storage encryption. End-to-end
-- encryption would mean deriving a key per account and syncing it between
-- devices, which is a design decision of its own — tracked, not forgotten.

-- ── Content types ─────────────────────────────────────────────────────────────
-- 'image' exists so the enum does not need a migration when image sync lands;
-- the clients only write 'text' and 'link' today.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'clipboard_content_type') then
    create type public.clipboard_content_type as enum ('text', 'link', 'image');
  end if;
end
$$;

-- ── Assurance helper ──────────────────────────────────────────────────────────
-- True when the caller has cleared every factor their account requires.
--
-- Supabase issues a usable session at assurance level 1 *before* a TOTP factor
-- is verified. Without this check, someone holding only the password could read
-- the clipboard through the API even though the app's UI blocks them — which
-- would make two-factor authentication cosmetic.
--
-- Security definer because `authenticated` cannot read auth.mfa_factors, with
-- search_path pinned so the function cannot be hijacked by a shadowing schema.
create or replace function public.has_required_assurance()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(auth.jwt() -> 'aal' #>> '{}', '') = 'aal2'
    or not exists (
      select 1
      from auth.mfa_factors f
      where f.user_id = auth.uid()
        and f.status = 'verified'
    );
$$;

revoke all on function public.has_required_assurance() from public;
grant execute on function public.has_required_assurance() to authenticated;

-- ── Clipboard items ───────────────────────────────────────────────────────────
create table if not exists public.clipboard_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  -- Clipboard content is untrusted input. The cap keeps one runaway copy from
  -- filling the table; clients truncate before sending so this is a backstop.
  content text not null check (
    char_length(content) > 0 and char_length(content) <= 100000
  ),
  content_type public.clipboard_content_type not null default 'text',

  -- Which device produced it. Free text rather than a hard reference so an
  -- item outlives the device that created it.
  device_id text,
  device_name text check (device_name is null or char_length(device_name) <= 100),
  device_platform text check (
    device_platform is null
    or device_platform in ('ios', 'android', 'macos', 'windows', 'linux')
  ),

  is_pinned boolean not null default false,
  created_at timestamptz not null default now(),

  -- Cheap equality check for de-duplicating a re-copied value without
  -- comparing full contents. A hash of the content, never the content itself.
  content_hash text generated always as (md5(content)) stored
);

create index if not exists clipboard_items_user_created_idx
  on public.clipboard_items (user_id, created_at desc);

create index if not exists clipboard_items_user_hash_idx
  on public.clipboard_items (user_id, content_hash);

alter table public.clipboard_items enable row level security;

drop policy if exists "clipboard_select_own" on public.clipboard_items;
create policy "clipboard_select_own" on public.clipboard_items
  for select using (
    auth.uid() = user_id and public.has_required_assurance()
  );

drop policy if exists "clipboard_insert_own" on public.clipboard_items;
create policy "clipboard_insert_own" on public.clipboard_items
  for insert with check (
    auth.uid() = user_id and public.has_required_assurance()
  );

drop policy if exists "clipboard_update_own" on public.clipboard_items;
create policy "clipboard_update_own" on public.clipboard_items
  for update using (
    auth.uid() = user_id and public.has_required_assurance()
  ) with check (
    auth.uid() = user_id and public.has_required_assurance()
  );

drop policy if exists "clipboard_delete_own" on public.clipboard_items;
create policy "clipboard_delete_own" on public.clipboard_items
  for delete using (
    auth.uid() = user_id and public.has_required_assurance()
  );

-- ── Devices ───────────────────────────────────────────────────────────────────
-- One row per installation, so the app can show where items came from and when
-- each device was last seen.
create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  -- Stable per install, generated on the device. Not a hardware identifier:
  -- nothing here should let two accounts be linked to the same handset.
  install_id text not null check (char_length(install_id) between 8 and 100),

  name text not null check (char_length(name) between 1 and 100),
  platform text not null check (
    platform in ('ios', 'android', 'macos', 'windows', 'linux')
  ),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  unique (user_id, install_id)
);

create index if not exists devices_user_idx on public.devices (user_id);

alter table public.devices enable row level security;

drop policy if exists "devices_select_own" on public.devices;
create policy "devices_select_own" on public.devices
  for select using (auth.uid() = user_id and public.has_required_assurance());

drop policy if exists "devices_insert_own" on public.devices;
create policy "devices_insert_own" on public.devices
  for insert with check (
    auth.uid() = user_id and public.has_required_assurance()
  );

drop policy if exists "devices_update_own" on public.devices;
create policy "devices_update_own" on public.devices
  for update using (
    auth.uid() = user_id and public.has_required_assurance()
  ) with check (
    auth.uid() = user_id and public.has_required_assurance()
  );

drop policy if exists "devices_delete_own" on public.devices;
create policy "devices_delete_own" on public.devices
  for delete using (auth.uid() = user_id and public.has_required_assurance());

-- ── Sync settings ─────────────────────────────────────────────────────────────
-- One row per user, so preferences follow the account across devices.
create table if not exists public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,

  auto_sync boolean not null default true,
  wifi_only boolean not null default false,
  sync_alerts boolean not null default true,

  -- 0 means keep until deleted by hand. Constrained to the values the picker
  -- offers so a bad client cannot invent a retention period.
  retention_days integer not null default 7
    check (retention_days in (0, 1, 7, 30, 90, 365)),

  -- Capture filters. Images are deliberately absent until image sync exists.
  capture_text boolean not null default true,
  capture_links boolean not null default true,

  updated_at timestamptz not null default now()
);

alter table public.user_settings enable row level security;

-- Settings are readable at aal1: the app needs them before it can decide what
-- to show, and they contain no clipboard content.
drop policy if exists "settings_select_own" on public.user_settings;
create policy "settings_select_own" on public.user_settings
  for select using (auth.uid() = user_id);

drop policy if exists "settings_insert_own" on public.user_settings;
create policy "settings_insert_own" on public.user_settings
  for insert with check (auth.uid() = user_id);

drop policy if exists "settings_update_own" on public.user_settings;
create policy "settings_update_own" on public.user_settings
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop trigger if exists set_user_settings_updated_at on public.user_settings;
create trigger set_user_settings_updated_at
  before update on public.user_settings
  for each row execute function public.set_updated_at();

-- Give every new account a settings row. Existing accounts are covered by the
-- client's upsert-on-first-load, so both paths converge.
create or replace function public.handle_new_user_settings()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_settings on auth.users;
create trigger on_auth_user_created_settings
  after insert on auth.users
  for each row execute function public.handle_new_user_settings();

-- ── Retention ─────────────────────────────────────────────────────────────────
-- Deletes the caller's expired items and reports how many went.
--
-- Runs as the caller (security invoker) so RLS still applies and this can never
-- reach another user's rows. Clients call it on launch; a scheduled job can
-- call the same logic later for users who never open the app — until then,
-- retention is enforced whenever a client connects.
create or replace function public.prune_expired_clipboard_items()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  keep_days integer;
  removed integer;
begin
  select s.retention_days into keep_days
  from public.user_settings s
  where s.user_id = auth.uid();

  -- No settings row yet, or "keep forever".
  if keep_days is null or keep_days = 0 then
    return 0;
  end if;

  with deleted as (
    delete from public.clipboard_items
    where user_id = auth.uid()
      and is_pinned = false
      and created_at < now() - make_interval(days => keep_days)
    returning 1
  )
  select count(*) into removed from deleted;

  return removed;
end;
$$;

revoke all on function public.prune_expired_clipboard_items() from public;
grant execute on function public.prune_expired_clipboard_items() to authenticated;
