-- 20251006_create_visit_rate_limit.sql
-- Add table for tracking visit CRUD rate limits

CREATE TABLE IF NOT EXISTS public.visit_rate_limit (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL,
  action_type text NOT NULL,  -- 'create' | 'update' | 'delete'
  ip_address text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for fast rate limit checks (last 1 hour for updates/deletes, 24 hours for creates)
CREATE INDEX idx_visit_rate_limit_user_action_time 
  ON public.visit_rate_limit(user_id, action_type, created_at DESC);

-- Cleanup old entries (keep only last 24 hours)
CREATE INDEX idx_visit_rate_limit_cleanup 
  ON public.visit_rate_limit(created_at);

-- RLS: service role only (rate limiting is server-side)
ALTER TABLE public.visit_rate_limit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_rate_limit FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE public.visit_rate_limit IS 
  'Tracks visit CRUD actions for rate limiting. Auto-cleaned after 24 hours.';

-- Down migration
-- DROP TABLE IF EXISTS public.visit_rate_limit CASCADE;