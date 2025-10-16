-- 20251002_create_signup_throttle.sql
-- Create signup_throttle table for per-IP signup rate limiting

CREATE TABLE IF NOT EXISTS public.signup_throttle (
  id bigserial PRIMARY KEY,
  ip_address text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_signup_throttle_ip_time ON public.signup_throttle(ip_address, created_at DESC);

-- Enable RLS but no policies (service_role only)
ALTER TABLE public.signup_throttle ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.signup_throttle FORCE ROW LEVEL SECURITY;