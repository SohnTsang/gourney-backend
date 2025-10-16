-- 20251006_fix_activity_cascade_delete.sql
-- Add CASCADE delete for activity entries when visits are deleted

-- Drop existing constraint if it exists
ALTER TABLE activity DROP CONSTRAINT IF EXISTS activity_subject_id_fkey;

-- Add new constraint with CASCADE
ALTER TABLE activity 
  ADD CONSTRAINT activity_visits_cascade 
  FOREIGN KEY (subject_id) 
  REFERENCES visits(id) 
  ON DELETE CASCADE;

COMMENT ON CONSTRAINT activity_visits_cascade ON activity IS 
  'CASCADE delete activity entries when parent visit is deleted';

-- Down migration:
-- ALTER TABLE activity DROP CONSTRAINT IF EXISTS activity_visits_cascade;
-- ALTER TABLE activity 
--   ADD CONSTRAINT activity_subject_id_fkey 
--   FOREIGN KEY (subject_id) 
--   REFERENCES visits(id);