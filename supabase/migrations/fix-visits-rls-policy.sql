-- Fix visits RLS policy to work properly with Supabase client
-- Run this in Supabase SQL Editor

-- Drop old policy
DROP POLICY IF EXISTS visits_select_policy ON public.visits;

-- Create new simplified policy
CREATE POLICY visits_select_policy ON public.visits
FOR SELECT
TO authenticated
USING (
  -- User can see their own visits
  user_id = auth.uid()
  OR
  -- User can see public visits from non-deleted, non-blocked users
  (
    visibility = 'public'
    AND NOT EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = visits.user_id
      AND u.deleted_at IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.user_blocks ub
      WHERE (ub.blocker_id = auth.uid() AND ub.blockee_id = visits.user_id)
         OR (ub.blocker_id = visits.user_id AND ub.blockee_id = auth.uid())
    )
  )
  OR
  -- User can see friends-only visits from users they follow
  (
    visibility = 'friends'
    AND EXISTS (
      SELECT 1 FROM public.follows f
      WHERE f.follower_id = auth.uid()
      AND f.followee_id = visits.user_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = visits.user_id
      AND u.deleted_at IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.user_blocks ub
      WHERE (ub.blocker_id = auth.uid() AND ub.blockee_id = visits.user_id)
         OR (ub.blocker_id = visits.user_id AND ub.blockee_id = auth.uid())
    )
  )
);

-- Verify the policy was created
SELECT 
  '✓ Policy updated' AS status,
  policyname,
  cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'visits'
  AND policyname = 'visits_select_policy';

-- Test the policy - should return your 3 visits
SELECT 
  '✓ Test query' AS status,
  COUNT(*) AS visible_visits
FROM public.visits
WHERE place_id = '178563c5-42db-4eaa-a4b6-e60c241fe94b';