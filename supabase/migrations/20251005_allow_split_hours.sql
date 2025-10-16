-- 20251005_allow_split_hours.sql
-- Allow multiple time ranges per day for venues with split hours

-- Step 1: Drop old primary key
ALTER TABLE place_hours DROP CONSTRAINT place_hours_pkey;

-- Step 2: Add ID column and make it primary key
ALTER TABLE place_hours ADD COLUMN id BIGSERIAL PRIMARY KEY;

-- Step 3: Prevent exact duplicates
CREATE UNIQUE INDEX idx_place_hours_unique 
  ON place_hours(place_id, weekday, open_time, close_time);

-- Step 4: Optimize lookups
CREATE INDEX idx_place_hours_lookup 
  ON place_hours(place_id, weekday);

COMMENT ON TABLE place_hours IS 
  'Operating hours - supports multiple time ranges per day (e.g. lunch 11-15, dinner 18-22)';