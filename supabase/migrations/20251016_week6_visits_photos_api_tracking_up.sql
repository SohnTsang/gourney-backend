-- 20251016_week6_visits_photos_api_tracking_up.sql
-- Week 6: Add photo support, API tracking, and place moderation

BEGIN;
SET search_path = public, extensions, gis;

-- ============================================
-- 1. Update visits table
-- ============================================

-- Add photo_urls column (max 3 photos per visit)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='visits' AND column_name='photo_urls'
  ) THEN
    ALTER TABLE visits ADD COLUMN photo_urls TEXT[] DEFAULT '{}';
  END IF;
END $$;

-- Add created_new_place flag
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='visits' AND column_name='created_new_place'
  ) THEN
    ALTER TABLE visits ADD COLUMN created_new_place BOOLEAN DEFAULT FALSE;
  END IF;
END $$;

-- Update existing constraint or add new one for photo limit
ALTER TABLE visits DROP CONSTRAINT IF EXISTS check_photo_limit;
ALTER TABLE visits ADD CONSTRAINT check_photo_limit 
  CHECK (cardinality(photo_urls) <= 3);

-- Ensure comment length constraint exists
ALTER TABLE visits DROP CONSTRAINT IF EXISTS check_comment_length;
ALTER TABLE visits ADD CONSTRAINT check_comment_length 
  CHECK (comment IS NULL OR char_length(comment) <= 1000);

-- Add constraint: photo OR comment required
ALTER TABLE visits DROP CONSTRAINT IF EXISTS check_photo_or_comment;
ALTER TABLE visits ADD CONSTRAINT check_photo_or_comment 
  CHECK (
    cardinality(photo_urls) > 0 OR 
    (comment IS NOT NULL AND char_length(trim(comment)) > 0)
  );

COMMENT ON COLUMN visits.photo_urls IS 'Array of photo URLs from user-photos storage bucket (max 3)';
COMMENT ON COLUMN visits.created_new_place IS 'Flag if this visit created a new place (for bonus points)';

-- ============================================
-- 2. Update places table
-- ============================================

-- Add google_place_id for API tracking
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='places' AND column_name='google_place_id'
  ) THEN
    ALTER TABLE places ADD COLUMN google_place_id TEXT;
  END IF;
END $$;

-- Add apple_place_id for API tracking
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='places' AND column_name='apple_place_id'
  ) THEN
    ALTER TABLE places ADD COLUMN apple_place_id TEXT;
  END IF;
END $$;

-- Create unique indexes to prevent duplicate API fetches
CREATE UNIQUE INDEX IF NOT EXISTS idx_places_google_place_id 
  ON places(google_place_id) 
  WHERE google_place_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_places_apple_place_id 
  ON places(apple_place_id) 
  WHERE apple_place_id IS NOT NULL;

COMMENT ON COLUMN places.google_place_id IS 'Google Places API place_id (prevents duplicate API calls)';
COMMENT ON COLUMN places.apple_place_id IS 'Apple Maps place ID (prevents duplicate API calls)';

-- ============================================
-- 3. Create find_nearby_places function
-- ============================================

CREATE OR REPLACE FUNCTION public.find_nearby_places(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_radius_meters INT,
  p_name_query TEXT
)
RETURNS TABLE (
  id UUID,
  name TEXT,
  distance_meters DOUBLE PRECISION,
  similarity_score DOUBLE PRECISION
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, gis
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    COALESCE(p.name_en, p.name_ja, p.name_zh) AS name,
    ST_Distance(
      p.geom::geography,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) AS distance_meters,
    GREATEST(
      similarity(LOWER(COALESCE(p.name_en, '')), LOWER(p_name_query)),
      similarity(LOWER(COALESCE(p.name_ja, '')), LOWER(p_name_query)),
      similarity(LOWER(COALESCE(p.name_zh, '')), LOWER(p_name_query))
    ) AS similarity_score
  FROM public.places p
  WHERE 
    ST_DWithin(
      p.geom::geography,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_radius_meters
    )
    AND (
      LOWER(COALESCE(p.name_en, '')) ILIKE '%' || LOWER(p_name_query) || '%' OR
      LOWER(COALESCE(p.name_ja, '')) ILIKE '%' || LOWER(p_name_query) || '%' OR
      LOWER(COALESCE(p.name_zh, '')) ILIKE '%' || LOWER(p_name_query) || '%'
    )
  ORDER BY distance_meters ASC
  LIMIT 5;
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_nearby_places TO authenticated;

COMMENT ON FUNCTION public.find_nearby_places IS 
  'Finds nearby places within radius for duplicate detection. Uses PostGIS + fuzzy name matching.';

COMMIT;