-- 20251002_signup_throttle_down.sql
-- Rollback: Remove signup_throttle table

-- Drop index first
drop index if exists public.idx_signup_throttle_ip_time;

-- Disable RLS
alter table if exists public.signup_throttle no force row level security;
alter table if exists public.signup_throttle disable row level security;

-- Drop table
drop table if exists public.signup_throttle;