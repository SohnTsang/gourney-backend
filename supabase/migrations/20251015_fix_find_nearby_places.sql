-- Fix find_nearby_places function type mismatch

BEGIN;
SET search_path = public, extensions, gis;

DROP FUNCTION IF EXISTS public.find_nearby_places(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TEXT);

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
  similarity_score REAL  -- Changed from DOUBLE PRECISION to REAL
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