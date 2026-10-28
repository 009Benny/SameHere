-- ============================================================
-- Same Here — schedule the push digest (pg_cron + pg_net)
-- Run AFTER push_notifications.sql and after deploying the Edge Function:
--
--   supabase functions deploy send-digest --no-verify-jwt --project-ref <project-ref>
--
-- Before running this file:
--   1. Dashboard → Database → Extensions: enable `pg_cron` and `pg_net`.
--   2. Pick a long random secret (e.g. `openssl rand -hex 32`) and store it in
--      BOTH places:
--        * as an Edge Function secret:
--            supabase secrets set DIGEST_CRON_SECRET=<secret> --project-ref <project-ref>
--        * in Vault (below), so the cron job can send it.
--   3. Replace <project-ref> below with your project's ref (the subdomain of
--      your Supabase URL).
--
-- Times are UTC. Mexico City is UTC-6 all year, so 17:00 UTC = 11:00 CDMX.
-- Safe to re-run: each job is unscheduled first.
-- ============================================================

-- The shared secret the function checks in the `x-cron-secret` header.
-- Run once; to rotate it later use vault.update_secret().
-- select vault.create_secret('<secret>', 'digest_cron_secret');

-- Weekly digest: Mondays at 11:00 CDMX.
select cron.unschedule('same-here-weekly-digest')
where exists (select 1 from cron.job where jobname = 'same-here-weekly-digest');

select cron.schedule(
  'same-here-weekly-digest',
  '0 17 * * 1',
  $$
  select net.http_post(
    url     := 'https://eezdoyozyffmfxjmtvfg.supabase.co/functions/v1/send-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'digest_cron_secret')
    ),
    body    := '{"frequency":"weekly"}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);

-- Daily digest: every day at 11:00 CDMX.
select cron.unschedule('same-here-daily-digest')
where exists (select 1 from cron.job where jobname = 'same-here-daily-digest');

select cron.schedule(
  'same-here-daily-digest',
  '0 17 * * *',
  $$
  select net.http_post(
    url     := 'https://eezdoyozyffmfxjmtvfg.supabase.co/functions/v1/send-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'digest_cron_secret')
    ),
    body    := '{"frequency":"daily"}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);

-- Check:   select jobname, schedule, active from cron.job;
-- Runs:    select * from cron.job_run_details order by start_time desc limit 10;
-- Replies: select * from net._http_response order by created desc limit 10;
