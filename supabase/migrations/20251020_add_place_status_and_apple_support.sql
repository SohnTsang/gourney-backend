-- 20251020_add_place_status_and_apple_support.sql
-- Add Apple MapKit support + status tracking for Google API stubs
-- COMPLIANCE: Apple MapKit allows full data storage (more permissive than Google)

BEGIN;

SET search_path = public, extensions, gis;

-- ============================================
-- 1. Add status column for place lifecycle
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='places' AND column_name='status'
  ) THEN
    ALTER TABLE places 
      ADD COLUMN status TEXT DEFAULT 'approved'
        CHECK (status IN ('pending_review', 'approved', 'rejected'));
    
    COMMENT ON COLUMN places.status IS 
      'pending_review = Google API stub (needs admin review - COMPLIANCE)
       approved = Fully populated place (Apple/manual/DB/admin-reviewed)
       rejected = spam/duplicate/inappropriate (hidden)';
  END IF;
END $$;

-- ============================================
-- 2. Add admin review tracking
-- ============================================
ALTER TABLE places
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

COMMENT ON COLUMN places.reviewed_by IS 'Admin who reviewed Google stub';
COMMENT ON COLUMN places.reviewed_at IS 'When admin review completed';
COMMENT ON COLUMN places.rejection_reason IS 'Why rejected (if status=rejected)';

-- ============================================
-- 3. Ensure external API ID columns exist
-- ============================================
ALTER TABLE places
  ADD COLUMN IF NOT EXISTS google_place_id TEXT,
  ADD COLUMN IF NOT EXISTS apple_place_id TEXT;

-- Update comments to reflect compliance
COMMENT ON COLUMN places.google_place_id IS 
  'Google Places API place_id
   COMPLIANCE: Only store as stub reference. Full data requires admin review.
   Terms: https://developers.google.com/maps/terms-20180207#section_3_2_3';

COMMENT ON COLUMN places.apple_place_id IS 
  'Apple MapKit place identifier (MKMapItem.identifier)
   COMPLIANCE: Apple allows full data storage - no restrictions!
   Terms: https://developer.apple.com/maps/mapkit/
   REQUIRED: Display "Powered by Apple" attribution in UI';

-- ============================================
-- 4. Create unique indexes
-- ============================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_places_google_place_id 
  ON places(google_place_id) 
  WHERE google_place_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_places_apple_place_id 
  ON places(apple_place_id) 
  WHERE apple_place_id IS NOT NULL;

-- Composite index for fast lookups
CREATE INDEX IF NOT EXISTS idx_places_external_provider 
  ON places(provider, google_place_id, apple_place_id) 
  WHERE google_place_id IS NOT NULL OR apple_place_id IS NOT NULL;

-- ============================================
-- 5. Admin workflow indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_places_pending_review 
  ON places(status, created_at DESC) 
  WHERE status = 'pending_review';

COMMENT ON INDEX idx_places_pending_review IS 
  'Admin portal: List Google stubs needing review';

CREATE INDEX IF NOT EXISTS idx_visits_place_count
  ON visits(place_id, created_at DESC);

COMMENT ON INDEX idx_visits_place_count IS 
  'Admin portal: Count visits per pending place for prioritization';

-- ============================================
-- 6. Add visit tracking column (if not exists)
-- ============================================
ALTER TABLE visits 
  ADD COLUMN IF NOT EXISTS created_new_place BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN visits.created_new_place IS 
  'Bonus points flag: +3 points if user discovered new place';

COMMIT;