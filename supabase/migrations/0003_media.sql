-- CopyOnce — image relay.
--
-- Images are a relay, not a shelf. One lives only until every device on the
-- account has fetched it, or 24 hours, whichever comes first. CopyOnce moves
-- things between your devices; it is not a place to keep them.
--
-- The bytes live in Supabase Storage, never in clipboard_items.content:
-- watch_items streams whole rows over realtime, so image bytes in that column
-- would be pushed to every device on every change.
--
-- THE ORPHAN RULE, which every path here is built around:
--   Deleting a row does NOT delete the file in Storage.
--   Always delete the storage object FIRST, then the row.
-- Postgres cannot reach Storage, so nothing in this file deletes a file. The
-- trigger below only collapses expires_at, marking an image for the reaper.
-- File deletion happens in exactly one place (the reaper), which is what makes
-- the ordering rule enforceable.

-- ── Image columns on clipboard_items ──────────────────────────────────────────
alter table public.clipboard_items
  add column if not exists storage_path text,
  add column if not exists thumb_path text,
  add column if not exists byte_size bigint,
  add column if not exists mime_type text,
  add column if not exists expires_at timestamptz;

-- An image row must carry a path and an expiry; a text/link row must not carry
-- a path. Without this, a malformed client could create an "image" with nothing
-- behind it, or a text row that the reaper would try to delete a file for.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clipboard_items_image_shape'
  ) then
    alter table public.clipboard_items
      add constraint clipboard_items_image_shape check (
        (
          content_type = 'image'
          and storage_path is not null
          and thumb_path is not null
          and expires_at is not null
          and byte_size is not null
          and mime_type is not null
        )
        or (
          content_type <> 'image'
          and storage_path is null
          and thumb_path is null
          and expires_at is null
        )
      );
  end if;
end
$$;

-- 10 MB. Covers any phone photo or screenshot; excludes RAW. The bucket carries
-- the same limit, so an oversized upload is refused before the row is written.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clipboard_items_byte_size_sane'
  ) then
    alter table public.clipboard_items
      add constraint clipboard_items_byte_size_sane check (
        byte_size is null or (byte_size > 0 and byte_size <= 10485760)
      );
  end if;
end
$$;

-- SVG is deliberately absent: it can carry script, and clipboard content is
-- untrusted input.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clipboard_items_mime_allowed'
  ) then
    alter table public.clipboard_items
      add constraint clipboard_items_mime_allowed check (
        mime_type is null
        or mime_type in (
          'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic'
        )
      );
  end if;
end
$$;

-- Images are never pinned. prune_expired_clipboard_items exempts pinned rows,
-- so a pinnable image would be a hole in the 24-hour guarantee.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clipboard_items_images_unpinned'
  ) then
    alter table public.clipboard_items
      add constraint clipboard_items_images_unpinned check (
        content_type <> 'image' or is_pinned = false
      );
  end if;
end
$$;

-- The reaper's working index: expired images, oldest first.
create index if not exists clipboard_items_media_expiry_idx
  on public.clipboard_items (expires_at)
  where content_type = 'image';

-- ── Deliveries ────────────────────────────────────────────────────────────────
-- One row per (image, device that has fetched it). This is what makes
-- delete-on-delivery possible: when the count matches the account's device
-- count, the image has done its job.
--
-- Keyed on devices.id rather than the install_id text so that removing a device
-- cascades its delivery rows away. Both sides of the comparison then drop
-- together and a pending image can still complete.
create table if not exists public.clipboard_deliveries (
  item_id uuid not null references public.clipboard_items (id) on delete cascade,
  device_id uuid not null references public.devices (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  delivered_at timestamptz not null default now(),

  primary key (item_id, device_id)
);

create index if not exists clipboard_deliveries_user_idx
  on public.clipboard_deliveries (user_id);

alter table public.clipboard_deliveries enable row level security;

-- Same owner scoping and assurance gate as the items themselves: a delivery
-- receipt reveals that an image exists and when a device was active.
drop policy if exists "deliveries_select_own" on public.clipboard_deliveries;
create policy "deliveries_select_own" on public.clipboard_deliveries
  for select using (
    auth.uid() = user_id and public.has_required_assurance()
  );

drop policy if exists "deliveries_insert_own" on public.clipboard_deliveries;
create policy "deliveries_insert_own" on public.clipboard_deliveries
  for insert with check (
    auth.uid() = user_id and public.has_required_assurance()
  );

drop policy if exists "deliveries_delete_own" on public.clipboard_deliveries;
create policy "deliveries_delete_own" on public.clipboard_deliveries
  for delete using (
    auth.uid() = user_id and public.has_required_assurance()
  );

-- No update policy: a receipt is a fact about the past and is never edited.

-- ── Delete on delivery ────────────────────────────────────────────────────────
-- When the last device fetches an image, collapse its expiry to now so the
-- reaper picks it up on the next pass.
--
-- Does not delete anything itself — see the orphan rule at the top of this file.
create or replace function public.collapse_delivered_media()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  device_total integer;
  delivered_total integer;
begin
  select count(*) into device_total
  from public.devices d
  where d.user_id = new.user_id;

  select count(*) into delivered_total
  from public.clipboard_deliveries dl
  where dl.item_id = new.item_id;

  -- device_total > 0 guards the degenerate case: an account with no registered
  -- devices would otherwise satisfy "everyone has it" vacuously and reap an
  -- image the instant it was uploaded.
  if device_total > 0 and delivered_total >= device_total then
    update public.clipboard_items
    set expires_at = now()
    where id = new.item_id
      and content_type = 'image';
  end if;

  return new;
end;
$$;

drop trigger if exists on_delivery_recorded on public.clipboard_deliveries;
create trigger on_delivery_recorded
  after insert on public.clipboard_deliveries
  for each row execute function public.collapse_delivered_media();

-- Removing a device can complete a delivery: if the only device that had not
-- fetched an image is forgotten, the remaining devices already have it.
create or replace function public.recheck_media_after_device_removal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  device_total integer;
begin
  select count(*) into device_total
  from public.devices d
  where d.user_id = old.user_id;

  if device_total > 0 then
    update public.clipboard_items ci
    set expires_at = now()
    where ci.user_id = old.user_id
      and ci.content_type = 'image'
      and ci.expires_at > now()
      and (
        select count(*)
        from public.clipboard_deliveries dl
        where dl.item_id = ci.id
      ) >= device_total;
  end if;

  return old;
end;
$$;

drop trigger if exists on_device_removed_recheck_media on public.devices;
create trigger on_device_removed_recheck_media
  after delete on public.devices
  for each row execute function public.recheck_media_after_device_removal();

-- ── Live image quota ──────────────────────────────────────────────────────────
-- Ten images live at once. Deliberately a concurrent cap rather than a monthly
-- allowance: with 24-hour expiry the count is self-healing, so this needs no
-- counter table, no reset job, and cannot strand a user for three weeks after a
-- busy afternoon.
create or replace function public.enforce_media_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  live_count integer;
begin
  if new.content_type <> 'image' then
    return new;
  end if;

  -- Expired-but-not-yet-reaped images do not count: reaper lag is not the
  -- user's problem.
  select count(*) into live_count
  from public.clipboard_items ci
  where ci.user_id = new.user_id
    and ci.content_type = 'image'
    and ci.expires_at > now();

  if live_count >= 10 then
    -- 54000 is program_limit_exceeded; the client maps it to a friendly message.
    raise exception 'media_quota_exceeded'
      using errcode = '54000';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_media_quota_on_insert on public.clipboard_items;
create trigger enforce_media_quota_on_insert
  before insert on public.clipboard_items
  for each row execute function public.enforce_media_quota();

-- ── Capture filter ────────────────────────────────────────────────────────────
-- 0002 left this out on purpose, pending image sync. It exists now.
alter table public.user_settings
  add column if not exists capture_images boolean not null default true;

-- ── Storage ───────────────────────────────────────────────────────────────────
-- Private bucket. Layout is {user_id}/{item_id}/full.{ext} and
-- {user_id}/{item_id}/thumb.jpg, so the first path segment is the owner and
-- deleting the item prefix takes the thumbnail with it.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'clipboard-media',
  'clipboard-media',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Storage policies are evaluated separately from the table policies, so the
-- assurance gate has to be repeated here. Without it, someone holding only the
-- password could pull images through the Storage API while the app's UI blocks
-- them — which would make two-factor authentication cosmetic for the most
-- sensitive content type in the product.
drop policy if exists "media_select_own" on storage.objects;
create policy "media_select_own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'clipboard-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and public.has_required_assurance()
  );

drop policy if exists "media_insert_own" on storage.objects;
create policy "media_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'clipboard-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and public.has_required_assurance()
  );

drop policy if exists "media_delete_own" on storage.objects;
create policy "media_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'clipboard-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and public.has_required_assurance()
  );

-- No update policy: an uploaded image is immutable. Replacing one means
-- deleting it and uploading again, which keeps the delivery receipts honest.

-- ── Reaper, tier one ──────────────────────────────────────────────────────────
-- Lists the caller's reapable images so the client can delete the files through
-- the Storage SDK and then call reap_media_rows below.
--
-- Security invoker: RLS applies, so this can only ever surface the caller's own
-- rows. Returns paths, never content.
create or replace function public.expired_media_paths()
returns table (id uuid, storage_path text, thumb_path text)
language sql
security invoker
set search_path = ''
as $$
  select ci.id, ci.storage_path, ci.thumb_path
  from public.clipboard_items ci
  where ci.user_id = auth.uid()
    and ci.content_type = 'image'
    and ci.expires_at <= now()
  order by ci.expires_at
  limit 100;
$$;

revoke all on function public.expired_media_paths() from public;
grant execute on function public.expired_media_paths() to authenticated;

-- Removes rows whose files the caller has just deleted. Separate from the
-- listing call so the row only disappears after the file is actually gone —
-- the orphan rule, expressed as two steps the client must take in order.
create or replace function public.reap_media_rows(item_ids uuid[])
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  removed integer;
begin
  with deleted as (
    delete from public.clipboard_items
    where user_id = auth.uid()
      and content_type = 'image'
      and expires_at <= now()
      and id = any(item_ids)
    returning 1
  )
  select count(*) into removed from deleted;

  return removed;
end;
$$;

revoke all on function public.reap_media_rows(uuid[]) from public;
grant execute on function public.reap_media_rows(uuid[]) to authenticated;
