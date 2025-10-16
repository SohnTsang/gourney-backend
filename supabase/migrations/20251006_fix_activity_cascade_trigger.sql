-- 20251006_fix_activity_cascade_trigger.sql
-- Cascade delete activity entries when visits deleted (trigger-based for polymorphic FK)

BEGIN;

-- Drop any attempted FK constraints
ALTER TABLE public.activity
  DROP CONSTRAINT IF EXISTS activity_visits_cascade,
  DROP CONSTRAINT IF EXISTS activity_subject_id_fkey;

-- Clean up orphaned visit activities (if any exist)
DELETE FROM public.activity a
WHERE a.type = 'visit'
  AND NOT EXISTS (
    SELECT 1 FROM public.visits v WHERE v.id = a.subject_id
  );

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_activity_visit_subject
  ON public.activity(subject_id)
  WHERE type = 'visit';

-- Trigger function to cascade delete
CREATE OR REPLACE FUNCTION app.cascade_delete_activity_on_visit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM public.activity
  WHERE type = 'visit'
    AND subject_id = OLD.id;
  RETURN OLD;
END;
$$;

-- Attach trigger
DROP TRIGGER IF EXISTS trg_activity_cascade_on_visit_delete ON public.visits;

CREATE TRIGGER trg_activity_cascade_on_visit_delete
AFTER DELETE ON public.visits
FOR EACH ROW
EXECUTE FUNCTION app.cascade_delete_activity_on_visit();

COMMIT;

COMMENT ON FUNCTION app.cascade_delete_activity_on_visit() IS 
  'Cascade delete activity entries when parent visit deleted (polymorphic FK alternative)';

-- Down migration:
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_activity_cascade_on_visit_delete ON public.visits;
-- DROP FUNCTION IF EXISTS app.cascade_delete_activity_on_visit();
-- DROP INDEX IF EXISTS idx_activity_visit_subject;
-- COMMIT;