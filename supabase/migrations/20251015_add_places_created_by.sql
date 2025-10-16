-- 20251015_add_places_created_by.sql
-- Track user-generated places for moderation and credit

BEGIN;
SET search_path = public, extensions, gis;

-- Add created_by column to places
ALTER TABLE places 
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS moderation_status TEXT NOT NULL DEFAULT 'approved',
  ADD COLUMN IF NOT EXISTS submitted_photo_url TEXT,
  ADD COLUMN IF NOT EXISTS submission_notes TEXT,
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

-- Add constraint for moderation status
ALTER TABLE places
  DROP CONSTRAINT IF EXISTS check_moderation_status;

ALTER TABLE places
  ADD CONSTRAINT check_moderation_status 
  CHECK (moderation_status IN ('pending', 'approved', 'rejected', 'flagged'));

-- Index for moderation queries
CREATE INDEX IF NOT EXISTS idx_places_moderation_status 
  ON places(moderation_status, created_at DESC) 
  WHERE created_by IS NOT NULL;

-- Index for user submissions
CREATE INDEX IF NOT EXISTS idx_places_created_by 
  ON places(created_by, created_at DESC) 
  WHERE created_by IS NOT NULL;

COMMENT ON COLUMN places.created_by IS 'User who submitted this place (NULL for admin-seeded)';
COMMENT ON COLUMN places.moderation_status IS 'pending | approved | rejected | flagged';
COMMENT ON COLUMN places.submitted_photo_url IS 'Photo of storefront submitted by user';

COMMIT;