-- 20251004_search_rate_limit.sql
-- Add table for tracking search rate limits (100 req/min per user)

CREATE TABLE IF NOT EXISTS public.search_rate_limit (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL,
  searched_at timestamptz NOT NULL DEFAULT now(),
  ip_address text,
  endpoint text NOT NULL
);

-- Index for fast rate limit checks (last 1 minute)
CREATE INDEX idx_search_rate_limit_user_time 
  ON public.search_rate_limit(user_id, searched_at DESC);

-- Cleanup old entries (keep only last hour for debugging)
CREATE INDEX idx_search_rate_limit_cleanup 
  ON public.search_rate_limit(searched_at);

-- RLS: service role only (rate limiting is server-side)
ALTER TABLE public.search_rate_limit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_rate_limit FORCE ROW LEVEL SECURITY;

-- Auto-cleanup function (runs daily)
CREATE OR REPLACE FUNCTION cleanup_old_rate_limits()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.search_rate_limit
  WHERE searched_at < now() - interval '1 hour';
END;
$$;

COMMENT ON TABLE public.search_rate_limit IS 
  'Tracks search requests for rate limiting (100/min per user). Auto-cleaned after 1 hour.';

-- Down migration
-- DROP TABLE IF EXISTS public.search_rate_limit CASCADE;
-- DROP FUNCTION IF EXISTS cleanup_old_rate_limits();