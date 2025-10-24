-- Drop redundant status column (keep moderation_status)
ALTER TABLE places DROP COLUMN IF EXISTS status;

-- Verify moderation_status has correct check constraint
ALTER TABLE places DROP CONSTRAINT IF EXISTS places_moderation_status_check;
ALTER TABLE places 
  ADD CONSTRAINT places_moderation_status_check 
  CHECK (moderation_status IN ('pending', 'approved', 'rejected'));

-- Add admin review tracking (if not exists)
ALTER TABLE places 
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

-- Create unique indexes for external IDs (if not exists)
CREATE UNIQUE INDEX IF NOT EXISTS idx_places_google_place_id 
  ON places(google_place_id) 
  WHERE google_place_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_places_apple_place_id 
  ON places(apple_place_id) 
  WHERE apple_place_id IS NOT NULL;

-- Index for admin queries
CREATE INDEX IF NOT EXISTS idx_places_pending_moderation 
  ON places(moderation_status, created_at DESC) 
  WHERE moderation_status = 'pending';
