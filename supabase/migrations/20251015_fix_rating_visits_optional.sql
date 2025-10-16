-- Fix: Make rating optional in visits table
BEGIN;

-- Drop the NOT NULL constraint on rating
ALTER TABLE visits ALTER COLUMN rating DROP NOT NULL;

-- Add a check constraint to ensure if rating is provided, it's between 1-5
ALTER TABLE visits DROP CONSTRAINT IF EXISTS check_rating_range;
ALTER TABLE visits ADD CONSTRAINT check_rating_range 
  CHECK (rating IS NULL OR (rating >= 1 AND rating <= 5));

COMMIT;