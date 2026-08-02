\set ON_ERROR_STOP on
\pset pager off

-- Behaviour checks for 0005: the history ring buffer, labels, search, paging,
-- and account deletion. Runs against a throwaway Postgres, never a real project.

delete from auth.users;

create or replace function tap(label text, got boolean, want boolean)
returns void language plpgsql as $$
begin
  if got is not distinct from want then
    raise notice 'PASS  %', label;
  else
    raise exception 'FAIL  % (got %, want %)', label, got, want;
  end if;
end $$;

do $$
declare
  u uuid;
  n integer;
  oldest_id uuid;
  pinned_id uuid;
  ok boolean;
  rec record;
begin
  insert into auth.users (email) values ('platform@test.local') returning id into u;
  -- search_clipboard_items and delete_my_account read auth.uid().
  update auth._test_ctx set uid = u;

  -- ── labels ───────────────────────────────────────────────────────────────
  insert into public.clipboard_items (user_id, content, content_type, label, is_pinned)
  values (u, 'GB29 NWBK 6016 1331 9268 19', 'text', 'Bank IBAN', true)
  returning id into pinned_id;
  perform tap('labelled pin accepted', pinned_id is not null, true);

  begin
    insert into public.clipboard_items (user_id, content, content_type, label)
    values (u, 'x', 'text', repeat('a', 61));
    ok := false;
  exception when check_violation then ok := true;
  end;
  perform tap('over-long label refused', ok, true);

  -- ── search ───────────────────────────────────────────────────────────────
  insert into public.clipboard_items (user_id, content, content_type)
  values (u, 'https://example.com/deploy-guide', 'link'),
         (u, 'postgres connection string for staging', 'text');

  select count(*) into n from public.search_clipboard_items('deploy');
  perform tap('full-text finds a word', n = 1, true);

  select count(*) into n from public.search_clipboard_items('exam');
  perform tap('partial token still matches via ilike', n = 1, true);

  select count(*) into n from public.search_clipboard_items('IBAN');
  perform tap('search covers the label too', n = 1, true);

  select count(*) into n from public.search_clipboard_items(null, 'link');
  perform tap('filters by kind', n = 1, true);

  select count(*) into n from public.search_clipboard_items('nothingmatchesthis');
  perform tap('no match returns nothing', n = 0, true);

  -- ── keyset paging ────────────────────────────────────────────────────────
  select count(*) into n from public.search_clipboard_items(null, null, null, null, 2);
  perform tap('page size respected', n = 2, true);

  select ci.created_at, ci.id into rec
  from public.search_clipboard_items(null, null, null, null, 1) ci;

  select count(*) into n
  from public.search_clipboard_items(null, null, rec.created_at, rec.id, 50);
  perform tap('paging past the first row skips it', n = 2, true);

  -- ── history ring buffer ──────────────────────────────────────────────────
  delete from public.clipboard_items where user_id = u and is_pinned = false;

  -- 1000 unpinned items, oldest first.
  insert into public.clipboard_items (user_id, content, content_type, created_at)
  select u, 'item ' || g, 'text', now() - (1000 - g) * interval '1 minute'
  from generate_series(1, 1000) g;

  select count(*) into n from public.clipboard_items
   where user_id = u and content_type <> 'image' and is_pinned = false;
  perform tap('1000 unpinned items held', n = 1000, true);

  select id into oldest_id from public.clipboard_items
   where user_id = u and is_pinned = false
   order by created_at asc limit 1;

  insert into public.clipboard_items (user_id, content, content_type)
  values (u, 'the one that pushes it over', 'text');

  select count(*) into n from public.clipboard_items
   where user_id = u and content_type <> 'image' and is_pinned = false;
  perform tap('cap holds at 1000 after another insert', n = 1000, true);

  perform tap('oldest was evicted, not the new one',
    not exists (select 1 from public.clipboard_items where id = oldest_id), true);

  perform tap('newest survived',
    exists (select 1 from public.clipboard_items
             where user_id = u and content = 'the one that pushes it over'), true);

  perform tap('pinned item never evicted',
    exists (select 1 from public.clipboard_items where id = pinned_id), true);

  -- ── account deletion ─────────────────────────────────────────────────────
  insert into public.devices (user_id, install_id, name, platform)
  values (u, 'install-doomed-1', 'Doomed', 'linux');

  perform public.delete_my_account();

  perform tap('auth user gone',
    not exists (select 1 from auth.users where id = u), true);
  perform tap('clipboard rows cascaded',
    not exists (select 1 from public.clipboard_items where user_id = u), true);
  perform tap('devices cascaded',
    not exists (select 1 from public.devices where user_id = u), true);
  perform tap('settings cascaded',
    not exists (select 1 from public.user_settings where user_id = u), true);
  perform tap('profile cascaded',
    not exists (select 1 from public.profiles where id = u), true);

  raise notice '--- all platform checks passed ---';
end $$;

-- Deleting without a session must be refused rather than silently doing nothing.
update auth._test_ctx set uid = null;
do $$
declare ok boolean;
begin
  begin
    perform public.delete_my_account();
    ok := false;
  exception when others then ok := true;
  end;
  perform tap('anonymous delete refused', ok, true);
end $$;
