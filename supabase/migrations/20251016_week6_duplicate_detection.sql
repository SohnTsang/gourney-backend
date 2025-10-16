-- 20251016_week6_duplicate_detection.sql
-- Week 6 Step 4: Find nearby places for duplicate detection

SET search_path = public, extensions, gis;

CREATE OR REPLACE FUNCTION find_nearby_places(
  p_lat double precision,
  p_lng double precision,
  p_radius_meters integer DEFAULT 50,
  p_name_query text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  name_en text,
  name_ja text,
  name_zh text,
  distance_meters double precision,
  similarity_score real
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, gis
AS $$
DECLARE
  user_location gis.geography;
BEGIN
  -- Create point from coordinates
  user_location := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::gis.geography;
  
  RETURN QUERY
  SELECT 
    p.id,
    p.name_en,
    p.name_ja,
    p.name_zh,
    ST_Distance(p.geom, user_location) as distance_meters,
    CASE 
      WHEN p_name_query IS NOT NULL THEN
        GREATEST(
          similarity(COALESCE(p.name_en, ''), p_name_query),
          similarity(COALESCE(p.name_ja, ''), p_name_query),
          similarity(COALESCE(p.name_zh, ''), p_name_query)
        )
      ELSE 0.0
    END as similarity_score
  FROM places p
  WHERE ST_DWithin(p.geom, user_location, p_radius_meters)
    AND p.moderation_status IN ('approved', 'pending')
  ORDER BY 
    CASE 
      WHEN p_name_query IS NOT NULL THEN similarity_score 
      ELSE 0 
    END DESC,
    distance_meters ASC
  LIMIT 5;
END;
$$;

GRANT EXECUTE ON FUNCTION find_nearby_places TO authenticated, anon;

COMMENT ON FUNCTION find_nearby_places IS 
  'Week 6 Step 4: Find nearby places within radius with optional name similarity matching';