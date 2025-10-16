-- Fix places RLS to allow everyone to read
-- Run this in Supabase SQL Editor

-- Enable RLS on places table
ALTER TABLE places ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if any
DROP POLICY IF EXISTS "places_select_all" ON places;

-- Create policy allowing everyone (including anonymous users) to read places
CREATE POLICY "places_select_all" 
ON places
FOR SELECT
USING (true);

-- Verify policy was created
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'places';