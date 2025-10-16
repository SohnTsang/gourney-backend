-- 20240101000011_update_remote_config_cors.sql (key/value layout)
-- Purpose: seed/refresh remote_config entries (CORS, versioning, storage, rate limits, push, monitoring),
--          add monitor_logs + helpers, and expose get_cors_config().
-- Safe to re-run (idempotent).

set search_path = public, extensions;

-- Ensure pgcrypto for gen_random_uuid()
create extension if not exists pgcrypto;

-- Ensure the key/value remote_config table exists (matches v1 schema)
create table if not exists public.remote_config (
  key   text primary key,
  value jsonb not null
);

------------------------------
-- Remote config UPSERTs
------------------------------

-- Feature flags
insert into public.remote_config(key, value) values
  ('push_friend_visit',    jsonb_build_object('enabled', true)),
  ('rate_limits_on',       jsonb_build_object('enabled', true)),
  ('auto_hide_threshold',  jsonb_build_object('count', 3, 'window_hours', 24)),
  ('enable_open_now_beta', jsonb_build_object('enabled', true))
on conflict (key) do update set value = excluded.value;

-- CORS
insert into public.remote_config(key, value) values
('cors', jsonb_build_object(
  'allowed_origins', jsonb_build_array(
    'http://localhost:3000',
    'http://localhost:8100',
    'https://staging.beil-app.com',
    'https://app.beil.com',
    'https://beil.com'
  ),
  'allowed_methods',  jsonb_build_array('GET','POST','PUT','DELETE','OPTIONS'),
  'allowed_headers',  jsonb_build_array('authorization','x-client-info','apikey','content-type','x-api-version'),
  'expose_headers',   jsonb_build_array('x-api-version','x-api-version-deprecated','x-api-version-sunset','retry-after'),
  'max_age', 86400,
  'credentials', true
))
on conflict (key) do update set value = excluded.value;

-- API versioning
insert into public.remote_config(key, value) values
('api_version', jsonb_build_object(
  'current','v1',
  'supported',  jsonb_build_array('v1'),
  'deprecated', jsonb_build_array(),
  'require_version', true
))
on conflict (key) do update set value = excluded.value;

-- Storage
insert into public.remote_config(key, value) values
('storage', jsonb_build_object(
  'user_photos_bucket', 'user-photos',
  'max_file_size_mb', 4,
  'allowed_mime_types', jsonb_build_array('image/jpeg','image/jpg','image/png'),
  'max_photos_per_visit', 3
))
on conflict (key) do update set value = excluded.value;

-- Rate limits
insert into public.remote_config(key, value) values
('rate_limits', jsonb_build_object(
  'signup_per_ip_hour', 10,
  'visits_per_user_day', 30,
  'friend_visit_push_per_recipient_hour', 1,
  'api_calls_per_minute', 60
))
on conflict (key) do update set value = excluded.value;

-- Monitoring
insert into public.remote_config(key, value) values
('monitoring', jsonb_build_object(
  'latency_threshold_ms', 800,
  'latency_duration_minutes', 10,
  'queue_backlog_threshold', 1000,
  'queue_age_threshold_minutes', 10,
  'alert_webhook', null
))
on conflict (key) do update set value = excluded.value;

-- Push delivery knobs
insert into public.remote_config(key, value) values
('push', jsonb_build_object(
  'quiet_hours_default', jsonb_build_object('start','23:00','end','07:00'),
  'max_retries', 3,
  'backoff_base_seconds', 60,
  'batch_size', 100,
  'max_recipients_per_visit', 200
))
on conflict (key) do update set value = excluded.value;

------------------------------
-- Monitor logs + helpers
------------------------------

-- Logs table
create table if not exists public.monitor_logs (
  id uuid primary key default gen_random_uuid(),
  timestamp timestamptz not null default now(),
  alert_count integer not null default 0,
  alerts text[],
  metrics jsonb,
  created_at timestamptz not null default now()
);

-- Index for recency
create index if not exists idx_monitor_logs_timestamp
  on public.monitor_logs(timestamp desc);

-- Cleanup function (7 days)
create or replace function public.cleanup_old_monitor_logs()
returns void
language plpgsql
security definer
as $$
begin
  delete from public.monitor_logs
  where timestamp < now() - interval '7 days';
end;
$$;

-- Push queue stats (expects public.push_queue from v1 schema)
create or replace function public.get_push_queue_stats()
returns table(total_queued bigint, oldest_minutes numeric)
language plpgsql
security definer
as $$
begin
  return query
  select
    count(*)::bigint as total_queued,
    coalesce(extract(epoch from (now() - min(created_at)))/60.0, 0) as oldest_minutes
  from public.push_queue
  where status = 'queued';
end;
$$;

------------------------------
-- CORS helper for Edge Functions
------------------------------

create or replace function public.get_cors_config()
returns jsonb
language plpgsql
stable
as $$
declare cors_config jsonb;
begin
  select rc.value into cors_config
  from public.remote_config rc
  where rc.key = 'cors';

  return coalesce(cors_config, '{}'::jsonb);
end;
$$;

------------------------------
-- Grants (keep minimal; Edge uses service_role)
------------------------------

-- service_role can read config and call helpers
grant select on table public.remote_config to service_role;
grant execute on function public.get_push_queue_stats() to service_role;
grant execute on function public.get_cors_config() to service_role;
grant insert, select on table public.monitor_logs to service_role;

-- anon/authenticated may read CORS config if you want Edge-to-browser debug endpoints
-- grant execute on function public.get_cors_config() to anon, authenticated;

-- (Optional) If you expose metrics to clients, add grants carefully.

-- Down migration (commented for reference)
-- drop function if exists public.get_cors_config();
-- drop function if exists public.get_push_queue_stats();
-- drop function if exists public.cleanup_old_monitor_logs();
-- drop table if exists public.monitor_logs;
-- delete from public.remote_config where key in
--   ('cors','api_version','storage','rate_limits','monitoring','push',
--    'push_friend_visit','rate_limits_on','auto_hide_threshold','enable_open_now_beta');
