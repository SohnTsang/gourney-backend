-- 20251018_add_users_insert_policy.sql
-- CRITICAL FIX: Add INSERT policy for users table to allow profile creation
-- This fixes: "new row violates row-level security policy for table users"

BEGIN;

-- Drop existing policies to recreate them properly
DROP POLICY IF EXISTS users_insert_policy ON public.users;

-- INSERT policy: Allow authenticated users to insert their own profile ONLY
CREATE POLICY users_insert_policy ON public.users
  FOR INSERT 
  TO authenticated
  WITH CHECK (id = auth.uid());

-- Verify the user can only insert their own ID matching auth.uid()
COMMENT ON POLICY users_insert_policy ON public.users IS 
  'Users can only create their own profile with matching auth.uid()';

COMMIT;