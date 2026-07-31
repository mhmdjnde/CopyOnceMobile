// CopyOnce — media reaper.
//
// Deletes images whose relay is finished: either every device on the account
// has fetched them (the delivery trigger collapsed expires_at to now), or the
// 24-hour backstop elapsed.
//
// THE ORPHAN RULE: delete the storage object FIRST, then the row.
//
// If the file goes and the row survives, the next pass retries and remove() is
// idempotent — harmless. The reverse leaks a file permanently, with nothing
// left pointing at it to find it by. That asymmetry is why the order is fixed.
//
// Runs with the service role, so it is the only code here that sees across
// accounts. It never reads image bytes and never logs a path — only counts.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const BUCKET = 'clipboard-media';

// Bounded so a backlog cannot stall the function past its timeout. Whatever is
// left is picked up on the next scheduled pass.
const BATCH = 200;

interface ExpiredRow {
  id: string;
  user_id: string;
  storage_path: string;
  thumb_path: string;
}

Deno.serve(async (req: Request) => {
  // The scheduler holds the service role key; refuse anything else. Without
  // this the endpoint would be an unauthenticated mass-delete.
  const auth = req.headers.get('Authorization');
  const expected = `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`;
  if (auth !== expected) {
    return json({ error: 'unauthorized' }, 401);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  try {
    const reaped = await reapExpired(supabase);
    const orphans = await sweepOrphans(supabase);
    return json({ ok: true, reaped, orphans });
  } catch (error) {
    // Message only. An error object from the storage client can echo object
    // paths, and a path contains a user id.
    const message = error instanceof Error ? error.message : 'unknown error';
    console.error('reap failed:', message);
    return json({ error: 'reap failed' }, 500);
  }
});

/** Deletes images past their expiry, files before rows. */
async function reapExpired(supabase: ReturnType<typeof createClient>) {
  const { data, error } = await supabase
    .from('clipboard_items')
    .select('id, user_id, storage_path, thumb_path')
    .eq('content_type', 'image')
    .lte('expires_at', new Date().toISOString())
    .limit(BATCH);

  if (error) throw error;

  const rows = (data ?? []) as unknown as ExpiredRow[];
  if (rows.length === 0) return 0;

  const paths = rows.flatMap((r) => [r.storage_path, r.thumb_path]).filter(Boolean);

  // Step one: the files.
  const { error: removeError } = await supabase.storage.from(BUCKET).remove(paths);

  // A failure here means the rows stay put and we try again next pass. Leaving
  // the row is the safe direction: it is the only remaining pointer to the file.
  if (removeError) throw removeError;

  // Step two, and only now: the rows.
  const { error: deleteError } = await supabase
    .from('clipboard_items')
    .delete()
    .in('id', rows.map((r) => r.id));

  if (deleteError) throw deleteError;

  return rows.length;
}

/**
 * Removes files with no row behind them.
 *
 * A crash between the two steps above, or an upload that failed before its row
 * was written, leaves a file nothing references. Nothing will ever list it
 * again, so without this sweep it occupies the bucket forever.
 */
async function sweepOrphans(supabase: ReturnType<typeof createClient>) {
  const { data: users, error: listError } = await supabase.storage
    .from(BUCKET)
    .list('', { limit: 1000 });

  if (listError) throw listError;

  let removed = 0;

  for (const user of users ?? []) {
    const { data: items } = await supabase.storage
      .from(BUCKET)
      .list(user.name, { limit: 1000 });

    if (!items?.length) continue;

    // Folder names are item ids: the path layout is {user_id}/{item_id}/file.
    const itemIds = items.map((i) => i.name);

    const { data: live } = await supabase
      .from('clipboard_items')
      .select('id')
      .in('id', itemIds);

    const liveIds = new Set((live ?? []).map((r) => r.id as string));
    const orphaned = itemIds.filter((id) => !liveIds.has(id));

    for (const id of orphaned) {
      const { data: files } = await supabase.storage
        .from(BUCKET)
        .list(`${user.name}/${id}`, { limit: 10 });

      const paths = (files ?? []).map((f) => `${user.name}/${id}/${f.name}`);
      if (paths.length === 0) continue;

      const { error } = await supabase.storage.from(BUCKET).remove(paths);
      if (!error) removed += paths.length;
    }
  }

  return removed;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
