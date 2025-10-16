-- 20251006_fix_trigger_security_definer.sql
-- Fix trigger to run with SECURITY DEFINER so it can delete activity rows

-- Recreate the function with SECURITY DEFINER
CREATE OR REPLACE FUNCTION app.cascade_delete_activity_on_visit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER  -- This is the critical addition
SET search_path = public, app
AS $$
BEGIN
  -- Delete activity rows for this visit
  DELETE FROM public.activity
  WHERE type = 'visit'
    AND subject_id = OLD.id;
  
  RETURN OLD;
END;
$$;

-- Recreate trigger (just to be safe)
DROP TRIGGER IF EXISTS trg_activity_cascade_on_visit_delete ON public.visits;

CREATE TRIGGER trg_activity_cascade_on_visit_delete
AFTER DELETE ON public.visits
FOR EACH ROW
EXECUTE FUNCTION app.cascade_delete_activity_on_visit();

COMMENT ON FUNCTION app.cascade_delete_activity_on_visit() IS 
  'CASCADE delete activity entries when visit deleted. SECURITY DEFINER to bypass RLS.';