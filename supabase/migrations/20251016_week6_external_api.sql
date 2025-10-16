-- 20251016_week6_external_api.sql
-- Week 6 Step 4: External API Integration - Add missing columns

BEGIN;
SET search_path = public, extensions, gis;

-- ============================================
-- 1. Add columns to visits table
-- ============================================

-- Add created_new_place flag for bonus points
ALTER TABLE visits 
  ADD COLUMN IF NOT EXISTS created_new_place BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN visits.created_new_place IS 
  'True if this visit created a new place (+3 bonus points)';

-- ============================================
-- 2. Add columns to places table
-- ============================================

-- Add external API IDs for duplicate prevention
ALTER TABLE places 
  ADD COLUMN IF NOT EXISTS google_place_id TEXT,
  ADD COLUMN IF NOT EXISTS apple_place_id TEXT;

-- Create unique indexes to prevent duplicate API fetches
CREATE UNIQUE INDEX IF NOT EXISTS idx_places_google_place_id 
  ON places(google_place_id) 
  WHERE google_place_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_places_apple_place_id 
  ON places(apple_place_id) 
  WHERE apple_place_id IS NOT NULL;

-- Index for fast lookups during search
CREATE INDEX IF NOT EXISTS idx_places_external_ids 
  ON places(google_place_id, apple_place_id) 
  WHERE google_place_id IS NOT NULL OR apple_place_id IS NOT NULL;

COMMENT ON COLUMN places.google_place_id IS 
  'Google Places API place_id (prevents duplicate API calls)';
COMMENT ON COLUMN places.apple_place_id IS 
  'Apple Maps place ID (prevents duplicate API calls)';

COMMIT;