-- CopyOnce — scheduled media reaper.
--
-- Apply this LAST, and only after the reap-media Edge Function is deployed and
-- the two vault secrets below exist. Running it early schedules a job that
-- posts to a URL that is not there yet — harmless, but it fills the cron log
-- with failures.
--
-- Prerequisites, run once in the SQL editor with real values:
--
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co/functions/v1/reap-media',
--     'reap_media_url'
--   );
--   select vault.create_secret('<service-role-key>', 'reap_media_key');
--
-- The service role key is a secret that must never reach a client, which is
-- why it lives in the vault and is read at call time rather than written into
-- this file. Nothing here should ever be pasted into the Flutter app.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

-- Every five minutes. The relay's promise is "gone once delivered", and a
-- delivered image already had its expiry collapsed by the trigger, so this
-- interval is the lag between that and the file actually going. Five minutes
-- keeps the window small without spending a meaningful share of the free
-- tier's function invocations (~8.6k/month against a 500k allowance).
select cron.unschedule('reap-media')
where exists (select 1 from cron.job where jobname = 'reap-media');

select cron.schedule(
  'reap-media',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
             where name = 'reap_media_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                     from vault.decrypted_secrets
                                     where name = 'reap_media_key')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);

-- Free-tier projects pause after about a week of inactivity, and cron does not
-- run while paused. The client-side reaper in expired_media_paths() /
-- reap_media_rows() stays in place for exactly that reason: whoever opens the
-- app first after a pause clears their own backlog.
