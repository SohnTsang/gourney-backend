-- 20251014_user_profiles_discovery_down.sql
-- Rollback Week 5 Step 5: User Profiles & Discovery

BEGIN;
SET search_path = public, extensions;

-- Drop functions
DROP FUNCTION IF EXISTS public.get_suggested_follows(INTEGER);
DROP FUNCTION IF EXISTS public.search_users(TEXT, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.get_user_profile(TEXT, UUID);

COMMIT;