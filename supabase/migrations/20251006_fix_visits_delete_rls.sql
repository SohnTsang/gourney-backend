-- 20251006_fix_visits_delete_rls.sql
-- CRITICAL FIX: Separate DELETE policy to enforce strict ownership
-- Issue: Current "for all" policy allowed cross-user deletes

-- Drop the existing combined write policy
DROP POLICY IF EXISTS visits_write_policy ON public.visits;

-- Create separate policies for each operation

-- INSERT: Owner only
CREATE POLICY visits_insert_policy ON public.visits
FOR INSERT 
TO authenticated
WITH CHECK (user_id = auth.uid());

-- UPDATE: Owner only
CREATE POLICY visits_update_policy ON public.visits
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- DELETE: Owner only (CRITICAL - must be strict)
CREATE POLICY visits_delete_policy ON public.visits
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- Keep the SELECT policy unchanged (already correct from earlier migration)
-- SELECT policy allows: owner + visibility-based access + friend checks

COMMENT ON POLICY visits_insert_policy ON public.visits IS 
  'Users can only insert their own visits';

COMMENT ON POLICY visits_update_policy ON public.visits IS 
  'Users can only update their own visits';

COMMENT ON POLICY visits_delete_policy ON public.visits IS 
  'Users can only delete their own visits (strict ownership check)';

-- Down migration:
-- DROP POLICY IF EXISTS visits_insert_policy ON public.visits;
-- DROP POLICY IF EXISTS visits_update_policy ON public.visits;
-- DROP POLICY IF EXISTS visits_delete_policy ON public.visits;
-- 
-- Restore the original combined policy:
-- CREATE POLICY visits_write_policy ON public.visits
-- FOR ALL USING (user_id = auth.uid())
-- WITH CHECK (user_id = auth.uid());