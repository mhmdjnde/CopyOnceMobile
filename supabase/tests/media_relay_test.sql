\set ON_ERROR_STOP on
\pset pager off

-- Fresh slate each run.
delete from auth.users;
delete from storage.objects;

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
  d1 uuid;
  d2 uuid;
  img uuid;
  exp_before timestamptz;
  exp_after timestamptz;
  n integer;
  ok boolean;
begin
  -- ── setup ────────────────────────────────────────────────────────────────
  insert into auth.users (email) values ('relay@test.local') returning id into u;

  insert into public.devices (user_id, install_id, name, platform)
  values (u, 'install-phone-01', 'Phone', 'android') returning id into d1;
  insert into public.devices (user_id, install_id, name, platform)
  values (u, 'install-laptop-1', 'Laptop', 'linux') returning id into d2;

  -- ── 1. an image row inserts and keeps its 24h expiry ─────────────────────
  insert into public.clipboard_items
    (user_id, content, content_type, storage_path, thumb_path,
     byte_size, mime_type, expires_at)
  values
    (u, 'holiday.jpg', 'image',
     u || '/aaa/full.jpg', u || '/aaa/thumb.webp',
     512000, 'image/jpeg', now() + interval '24 hours')
  returning id, expires_at into img, exp_before;

  perform tap('image row accepted', img is not null, true);
  perform tap('expiry is ~24h out',
    exp_before > now() + interval '23 hours', true);

  -- ── 2. first device delivery does NOT reap (2 devices registered) ────────
  insert into public.clipboard_deliveries (item_id, device_id, user_id)
  values (img, d1, u);

  select expires_at into exp_after from public.clipboard_items where id = img;
  perform tap('1 of 2 delivered -> still live', exp_after > now(), true);

  -- ── 3. last device delivery collapses expiry ─────────────────────────────
  insert into public.clipboard_deliveries (item_id, device_id, user_id)
  values (img, d2, u);

  select expires_at into exp_after from public.clipboard_items where id = img;
  perform tap('2 of 2 delivered -> reapable', exp_after <= now(), true);

  -- ── 4. device removal can complete a pending delivery ────────────────────
  delete from public.clipboard_items where id = img;

  insert into public.clipboard_items
    (user_id, content, content_type, storage_path, thumb_path,
     byte_size, mime_type, expires_at)
  values (u, 'pending.png', 'image', u || '/bbb/full.png',
          u || '/bbb/thumb.webp', 4096, 'image/png',
          now() + interval '24 hours')
  returning id into img;

  insert into public.clipboard_deliveries (item_id, device_id, user_id)
  values (img, d1, u);

  select expires_at into exp_after from public.clipboard_items where id = img;
  perform tap('pending on laptop -> still live', exp_after > now(), true);

  delete from public.devices where id = d2;   -- forget the laggard

  select expires_at into exp_after from public.clipboard_items where id = img;
  perform tap('laggard removed -> reapable', exp_after <= now(), true);

  -- restore two-device state
  insert into public.devices (user_id, install_id, name, platform)
  values (u, 'install-laptop-1', 'Laptop', 'linux') returning id into d2;
  delete from public.clipboard_items where user_id = u;

  -- ── 5. quota: 10 live images allowed, 11th refused ───────────────────────
  for n in 1..10 loop
    insert into public.clipboard_items
      (user_id, content, content_type, storage_path, thumb_path,
       byte_size, mime_type, expires_at)
    values (u, 'q' || n || '.jpg', 'image',
            u || '/q' || n || '/full.jpg', u || '/q' || n || '/thumb.webp',
            1024, 'image/jpeg', now() + interval '24 hours');
  end loop;

  select count(*) into n from public.clipboard_items
   where user_id = u and content_type = 'image';
  perform tap('10 images accepted', n = 10, true);

  begin
    insert into public.clipboard_items
      (user_id, content, content_type, storage_path, thumb_path,
       byte_size, mime_type, expires_at)
    values (u, 'eleventh.jpg', 'image', u || '/q11/full.jpg',
            u || '/q11/thumb.webp', 1024, 'image/jpeg',
            now() + interval '24 hours');
    ok := false;
  exception when program_limit_exceeded then
    ok := true;
  end;
  perform tap('11th image refused with 54000', ok, true);

  -- ── 6. expired images do not count against the quota ─────────────────────
  update public.clipboard_items
     set expires_at = now() - interval '1 minute'
   where user_id = u and content = 'q1.jpg';

  begin
    insert into public.clipboard_items
      (user_id, content, content_type, storage_path, thumb_path,
       byte_size, mime_type, expires_at)
    values (u, 'after-expiry.jpg', 'image', u || '/q12/full.jpg',
            u || '/q12/thumb.webp', 1024, 'image/jpeg',
            now() + interval '24 hours');
    ok := true;
  exception when program_limit_exceeded then
    ok := false;
  end;
  perform tap('expired image frees a slot', ok, true);

  -- ── 7. text rows are unaffected by the quota ─────────────────────────────
  insert into public.clipboard_items (user_id, content, content_type)
  values (u, 'just some text', 'text');
  perform tap('text insert unaffected by media quota', true, true);

  delete from public.clipboard_items where user_id = u;

  -- ── 8. shape constraints ─────────────────────────────────────────────────
  begin
    insert into public.clipboard_items (user_id, content, content_type)
    values (u, 'no-path.jpg', 'image');
    ok := false;
  exception when check_violation then ok := true;
  end;
  perform tap('image without storage_path refused', ok, true);

  begin
    insert into public.clipboard_items
      (user_id, content, content_type, storage_path)
    values (u, 'hello', 'text', u || '/x/full.jpg');
    ok := false;
  exception when check_violation then ok := true;
  end;
  perform tap('text row with storage_path refused', ok, true);

  begin
    insert into public.clipboard_items
      (user_id, content, content_type, storage_path, thumb_path,
       byte_size, mime_type, expires_at, is_pinned)
    values (u, 'pinned.jpg', 'image', u || '/p/full.jpg',
            u || '/p/thumb.webp', 1024, 'image/jpeg',
            now() + interval '24 hours', true);
    ok := false;
  exception when check_violation then ok := true;
  end;
  perform tap('pinned image refused', ok, true);

  begin
    insert into public.clipboard_items
      (user_id, content, content_type, storage_path, thumb_path,
       byte_size, mime_type, expires_at)
    values (u, 'evil.svg', 'image', u || '/s/full.svg',
            u || '/s/thumb.webp', 1024, 'image/svg+xml',
            now() + interval '24 hours');
    ok := false;
  exception when check_violation then ok := true;
  end;
  perform tap('svg mime refused', ok, true);

  begin
    insert into public.clipboard_items
      (user_id, content, content_type, storage_path, thumb_path,
       byte_size, mime_type, expires_at)
    values (u, 'huge.jpg', 'image', u || '/h/full.jpg',
            u || '/h/thumb.webp', 10485761, 'image/jpeg',
            now() + interval '24 hours');
    ok := false;
  exception when check_violation then ok := true;
  end;
  perform tap('over-10MB image refused', ok, true);

  -- ── 9. deleting an item cascades its delivery receipts ───────────────────
  insert into public.clipboard_items
    (user_id, content, content_type, storage_path, thumb_path,
     byte_size, mime_type, expires_at)
  values (u, 'cascade.jpg', 'image', u || '/c/full.jpg',
          u || '/c/thumb.webp', 1024, 'image/jpeg',
          now() + interval '24 hours')
  returning id into img;

  insert into public.clipboard_deliveries (item_id, device_id, user_id)
  values (img, d1, u);

  delete from public.clipboard_items where id = img;
  select count(*) into n from public.clipboard_deliveries where item_id = img;
  perform tap('receipts cascade with the item', n = 0, true);

  -- ── 10. single-device account reaps on its own upload ────────────────────
  delete from public.devices where user_id = u and id = d2;
  delete from public.clipboard_items where user_id = u;

  insert into public.clipboard_items
    (user_id, content, content_type, storage_path, thumb_path,
     byte_size, mime_type, expires_at)
  values (u, 'solo.jpg', 'image', u || '/solo/full.jpg',
          u || '/solo/thumb.webp', 1024, 'image/jpeg',
          now() + interval '24 hours')
  returning id into img;

  insert into public.clipboard_deliveries (item_id, device_id, user_id)
  values (img, d1, u);

  select expires_at into exp_after from public.clipboard_items where id = img;
  perform tap('single-device upload reaps immediately', exp_after <= now(), true);

  raise notice '--- all behaviour checks passed ---';
end $$;
