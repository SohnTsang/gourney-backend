-- 20251004_schedule_slow_query_sampler.sql
-- Schedule slow query sampler to run daily at 2 AM UTC
-- PREREQUISITE: Enable pg_cron extension in Supabase Dashboard → Database → Extensions

-- Remove existing job if it exists
SELECT cron.unschedule('slow-query-sampler');

-- Schedule daily slow query sampler at 2 AM UTC
SELECT cron.schedule(
  'slow-query-sampler',
  '0 2 * * *', -- Daily at 2 AM UTC
  $$
  SELECT
    net.http_post(
      url := 'https://jelbrfbhwwcosmuckjqm.supabase.co/functions/v1/slow-query-sampler',
      headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1OTIxODg0MCwiZXhwIjoyMDc0Nzk0ODQwfQ.gg7qxC5QxJHt91YJwPqtiuFgIuv4KSfUgeFjXe7s9po"}'::jsonb,
      body := '{}'::jsonb
    ) AS request_id;
  $$
);

-- Verify cron job is scheduled
SELECT * FROM cron.job WHERE jobname = 'slow-query-sampler';

-- Down migration
-- SELECT cron.unschedule('slow-query-sampler');