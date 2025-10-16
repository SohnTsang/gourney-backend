-- 20251006_add_activity_update_policy.sql
-- Add UPDATE policy for activity table to allow visibility propagation

CREATE POLICY activity_update_policy ON public.activity
FOR UPDATE
TO authenticated
USING (actor_id = auth.uid())
WITH CHECK (actor_id = auth.uid());

-- Down migration:
-- DROP POLICY IF EXISTS activity_update_policy ON public.activity;