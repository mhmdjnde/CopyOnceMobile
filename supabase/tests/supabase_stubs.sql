-- Minimal stand-ins for the Supabase-managed objects the migrations reference.
-- Only enough to let Postgres parse and execute the real migration files.

create role anon;
create role authenticated;
create role service_role;

create schema if not exists auth;
create schema if not exists storage;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  raw_user_meta_data jsonb default '{}'::jsonb
);

create table auth.mfa_factors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null
);

-- Swappable current-user, so tests can act as a given account.
create table auth._test_ctx (uid uuid);
insert into auth._test_ctx values (null);

create or replace function auth.uid() returns uuid
language sql stable as $$ select uid from auth._test_ctx limit 1 $$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$ select '{"aal":"aal1"}'::jsonb $$;

create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid
);

alter table storage.objects enable row level security;

create or replace function storage.foldername(name text) returns text[]
language plpgsql immutable as $$
declare
  parts text[];
begin
  parts := string_to_array(name, '/');
  return parts[1:array_length(parts, 1) - 1];
end
$$;

grant usage on schema auth, storage, public to authenticated, anon, service_role;
