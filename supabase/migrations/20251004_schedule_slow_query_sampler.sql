-- 20251004_schedule_slow_query_sampler.sql
-- Schedule slow query sampler to run daily at 2 AM UTC
-- PREREQUISITE: Enable pg_cron extension in Supabase Dashboard → Database → Extensions
-- PREREQUISITE: Set SUPABASE_URL and SERVICE_ROLE_KEY as Supabase secrets

-- Remove existing job if it exists
SELECT cron.unschedule('slow-query-sampler');

-- Schedule daily slow query sampler at 2 AM UTC
SELECT cron.schedule(
  'slow-query-sampler',
  '0 2 * * *', -- Daily at 2 AM UTC
  $$
  SELECT
    net.http_post(
      url := current_setting('request.env.SUPABASE_URL', true) || '/functions/v1/slow-query-sampler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('request.env.SUPABASE_SERVICE_ROLE_KEY', true)
      ),
      body := '{}'::jsonb
    ) AS request_id;
  $$
);

-- Verify cron job is scheduled
SELECT * FROM cron.job WHERE jobname = 'slow-query-sampler';

-- Down migration
-- SELECT cron.unschedule('slow-query-sampler');
