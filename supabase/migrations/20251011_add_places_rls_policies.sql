-- 20251011_add_places_rls_policies.sql
-- Add RLS policies for places table to allow public read access
-- This fixes the issue where authenticated users cannot read places

-- Enable RLS on places table
ALTER TABLE public.places ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.places FORCE ROW LEVEL SECURITY;

-- Policy 1: Allow all authenticated users to read all places
-- Places are public data that all users need to access for searching, viewing details, etc.
CREATE POLICY places_select_authenticated ON public.places
  FOR SELECT 
  TO authenticated
  USING (true);

-- Policy 2: Allow anonymous users to read places (for potential future public APIs)
CREATE POLICY places_select_anon ON public.places
  FOR SELECT 
  TO anon
  USING (true);

-- Policy 3: Only service role can insert places (data comes from seeding/admin operations)
CREATE POLICY places_insert_service ON public.places
  FOR INSERT 
  TO service_role
  WITH CHECK (true);

-- Policy 4: Only service role can update places
CREATE POLICY places_update_service ON public.places
  FOR UPDATE 
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Policy 5: Only service role can delete places
CREATE POLICY places_delete_service ON public.places
  FOR DELETE 
  TO service_role
  USING (true);

-- Also enable RLS on place_hours table for consistency
ALTER TABLE public.place_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.place_hours FORCE ROW LEVEL SECURITY;

-- Allow all authenticated users to read place hours
CREATE POLICY place_hours_select_authenticated ON public.place_hours
  FOR SELECT 
  TO authenticated
  USING (true);

-- Allow anonymous users to read place hours
CREATE POLICY place_hours_select_anon ON public.place_hours
  FOR SELECT 
  TO anon
  USING (true);

-- Only service role can modify place hours
CREATE POLICY place_hours_insert_service ON public.place_hours
  FOR INSERT 
  TO service_role
  WITH CHECK (true);

CREATE POLICY place_hours_update_service ON public.place_hours
  FOR UPDATE 
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY place_hours_delete_service ON public.place_hours
  FOR DELETE 
  TO service_role
  USING (true);

-- Add comments for documentation
COMMENT ON POLICY places_select_authenticated ON public.places IS 
  'Allow all authenticated users to read places - places are public data';

COMMENT ON POLICY places_select_anon ON public.places IS 
  'Allow anonymous users to read places for potential future public APIs';

COMMENT ON POLICY places_insert_service ON public.places IS 
  'Only service role can insert places - data comes from admin seeding';

COMMENT ON POLICY place_hours_select_authenticated ON public.place_hours IS 
  'Allow all authenticated users to read place operating hours';

-- Down migration (rollback script)
-- Save this as: 20251011_add_places_rls_policies_down.sql
/*
-- Disable RLS policies for places
DROP POLICY IF EXISTS places_select_authenticated ON public.places;
DROP POLICY IF EXISTS places_select_anon ON public.places;
DROP POLICY IF EXISTS places_insert_service ON public.places;
DROP POLICY IF EXISTS places_update_service ON public.places;
DROP POLICY IF EXISTS places_delete_service ON public.places;

-- Disable RLS policies for place_hours
DROP POLICY IF EXISTS place_hours_select_authenticated ON public.place_hours;
DROP POLICY IF EXISTS place_hours_select_anon ON public.place_hours;
DROP POLICY IF EXISTS place_hours_insert_service ON public.place_hours;
DROP POLICY IF EXISTS place_hours_update_service ON public.place_hours;
DROP POLICY IF EXISTS place_hours_delete_service ON public.place_hours;

-- Disable RLS on tables (optional - only if you want to fully rollback)
ALTER TABLE public.places DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.place_hours DISABLE ROW LEVEL SECURITY;
*/