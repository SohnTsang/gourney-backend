CREATE POLICY activity_insert_policy ON public.activity
FOR INSERT 
TO authenticated
WITH CHECK (actor_id = auth.uid());

-- Down migration:
-- DROP POLICY IF EXISTS activity_insert_policy ON public.activity;