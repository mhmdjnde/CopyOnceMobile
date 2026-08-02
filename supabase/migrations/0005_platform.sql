-- CopyOnce — history limits, account deletion, search, and snippet labels.
--
-- Everything here is additive. No column is dropped and no existing row is
-- touched, so the migration can be applied to a live project while clients on
-- the previous version keep working.

-- ── Snippet labels ────────────────────────────────────────────────────────────
-- A pinned item with a name is a snippet: an address, an IBAN, a block of code
-- worth keeping. Without a label a pin is just an item that will not expire,
-- which is not a reason to open the app.
alter table public.clipboard_items
  add column if not exists label text
    check (label is null or char_length(label) between 1 and 60);

-- ── Sensitive content ─────────────────────────────────────────────────────────
-- Whether things that look like secrets — private keys, API tokens, card
-- numbers — are synced at all.
--
-- Defaults to true, because refusing to carry something the user deliberately
-- copied would be surprising. Masking in the list is always on regardless, and
-- costs nothing if the guess is wrong.
alter table public.user_settings
  add column if not exists capture_sensitive boolean not null default true;

-- ── Full-text search ──────────────────────────────────────────────────────────
-- The clients filtered client-side over the newest 200 rows, so anything older
-- was unfindable. Searching in Postgres removes that ceiling.
--
-- 'simple' rather than 'english': clipboard content is as often an identifier,
-- a URL, or a code as it is prose, and stemming "running" to "run" hurts more
-- than it helps when you are hunting for an exact string.
alter table public.clipboard_items
  add column if not exists content_search tsvector
    generated always as (to_tsvector('simple', coalesce(label, '') || ' ' || content)) stored;

create index if not exists clipboard_items_search_idx
  on public.clipboard_items using gin (content_search);

-- Paging reads newest-first within an account, which this index serves directly.
create index if not exists clipboard_items_user_created_id_idx
  on public.clipboard_items (user_id, created_at desc, id desc);

-- ── History limit ─────────────────────────────────────────────────────────────
-- Text and links had no cap at all: a loop could fill the database.
--
-- Enforced as a ring buffer rather than an error. A clipboard history is
-- inherently a rolling window — refusing to save what you just copied because
-- of something from three months ago would be the wrong answer. Pinned items
-- are never evicted, because pinning is the user saying "keep this".
create or replace function public.enforce_history_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  keep constant integer := 1000;
  surplus integer;
begin
  -- Images have their own quota and their own lifecycle; leave them alone.
  if new.content_type = 'image' then
    return new;
  end if;

  select count(*) - keep into surplus
  from public.clipboard_items
  where user_id = new.user_id
    and content_type <> 'image'
    and is_pinned = false;

  if surplus is null or surplus <= 0 then
    return new;
  end if;

  delete from public.clipboard_items
  where id in (
    select id
    from public.clipboard_items
    where user_id = new.user_id
      and content_type <> 'image'
      and is_pinned = false
    order by created_at asc, id asc
    limit surplus
  );

  return new;
end;
$$;

drop trigger if exists enforce_history_limit_on_insert on public.clipboard_items;
create trigger enforce_history_limit_on_insert
  after insert on public.clipboard_items
  for each row execute function public.enforce_history_limit();

-- ── Account deletion ──────────────────────────────────────────────────────────
-- There was no way to leave. Removing the auth user cascades to profiles,
-- clipboard_items, devices, deliveries, and settings through the foreign keys
-- already declared in 0001–0003.
--
-- Security definer because `authenticated` cannot write to auth.users, and
-- scoped to auth.uid() so it can only ever delete the caller. There is no
-- parameter to get wrong — a caller cannot name someone else's account.
--
-- Storage objects are NOT removed here: Postgres cannot reach the bucket. The
-- client deletes its files first and then calls this, which is the same
-- files-before-rows order the reaper uses. Anything missed is collected by the
-- orphan sweep, because the rows pointing at it are gone.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  delete from auth.users where id = caller;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- ── Paged search ──────────────────────────────────────────────────────────────
-- One entry point for the list, so both clients page and search identically.
--
-- Security invoker: RLS applies, so this can only ever return the caller's own
-- rows, and the assurance gate on clipboard_items still holds.
create or replace function public.search_clipboard_items(
  search text default null,
  kind text default null,
  before_created_at timestamptz default null,
  before_id uuid default null,
  page_size integer default 50
)
returns setof public.clipboard_items
language sql
security invoker
set search_path = ''
as $$
  select ci.*
  from public.clipboard_items ci
  where ci.user_id = auth.uid()
    and (kind is null or ci.content_type = kind::public.clipboard_content_type)
    and (
      search is null
      or btrim(search) = ''
      or ci.content_search @@ plainto_tsquery('simple', search)
      -- Falls back to a substring match so a partial token still finds
      -- something; full-text alone would miss "exam" inside "example".
      or ci.content ilike '%' || search || '%'
    )
    -- Keyset paging on (created_at, id): stable when rows are inserted while
    -- the user is scrolling, which offset paging is not.
    and (
      before_created_at is null
      or (ci.created_at, ci.id) < (before_created_at, before_id)
    )
  order by ci.created_at desc, ci.id desc
  limit least(greatest(page_size, 1), 100);
$$;

revoke all on function public.search_clipboard_items(text, text, timestamptz, uuid, integer) from public;
grant execute on function public.search_clipboard_items(text, text, timestamptz, uuid, integer) to authenticated;
