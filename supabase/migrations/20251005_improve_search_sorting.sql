-- Grant usage on gis schema to public roles
GRANT USAGE ON SCHEMA gis TO anon, authenticated, service_role;

-- Now recreate the function WITHOUT schema qualification
set search_path = public, extensions, gis;

DROP FUNCTION IF EXISTS public.search_places(text, text, int, timestamptz, uuid, int);

CREATE OR REPLACE FUNCTION public.search_places(
  p_search_text text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_price_level int DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_radius_meters int DEFAULT 5000,
  p_cursor_created_at timestamptz DEFAULT NULL,
  p_cursor_id uuid DEFAULT NULL,
  p_limit int DEFAULT 50
)
RETURNS TABLE(
  id uuid,
  provider text,
  provider_place_id text,
  name_ja text,
  name_en text,
  name_zh text,
  postal_code text,
  prefecture_code text,
  prefecture_name text,
  ward text,
  city text,
  lat double precision,
  lng double precision,
  price_level int,
  categories text[],
  attributes jsonb,
  geom geography,  -- Keep as 'geography' not 'gis.geography'
  search_tokens tsvector,
  created_at timestamptz,
  updated_at timestamptz,
  search_rank real,
  distance_meters int
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER  -- Add this line - critical!
SET search_path = public, extensions, gis
AS $$
DECLARE
  search_query tsquery;
  user_location geography;  -- Keep as 'geography' not 'gis.geography'
BEGIN
  -- rest of function unchanged
  IF p_search_text IS NOT NULL AND p_search_text != '' THEN
    search_query := plainto_tsquery('simple', p_search_text);
  END IF;

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    user_location := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
  END IF;

  RETURN QUERY
  SELECT 
    p.id, p.provider, p.provider_place_id,
    p.name_ja, p.name_en, p.name_zh,
    p.postal_code, p.prefecture_code, p.prefecture_name,
    p.ward, p.city, p.lat, p.lng, p.price_level,
    p.categories, p.attributes, p.geom,
    p.search_tokens, p.created_at, p.updated_at,
    CASE 
      WHEN p_search_text IS NOT NULL THEN ts_rank(p.search_tokens, search_query)
      ELSE 0.0
    END as search_rank,
    CASE
      WHEN user_location IS NOT NULL THEN ST_Distance(p.geom, user_location)::int
      ELSE NULL
    END as distance_meters
  FROM public.places p
  WHERE 
    (p_search_text IS NULL OR (
      p.search_tokens @@ search_query
      OR p.name_ja ILIKE '%' || p_search_text || '%'
      OR p.name_en ILIKE '%' || p_search_text || '%'
      OR p.name_zh ILIKE '%' || p_search_text || '%'
      OR p.ward ILIKE '%' || p_search_text || '%'
      OR p.city ILIKE '%' || p_search_text || '%'
    ))
    AND (p_category IS NULL OR p.categories @> ARRAY[p_category])
    AND (search_places.p_price_level IS NULL OR p.price_level = search_places.p_price_level)
    AND (user_location IS NULL OR ST_DWithin(p.geom, user_location, p_radius_meters))
    AND (
      p_cursor_created_at IS NULL 
      OR p.created_at < p_cursor_created_at
      OR (p.created_at = p_cursor_created_at AND p.id < p_cursor_id)
    )
  ORDER BY 
    CASE WHEN p_search_text IS NOT NULL THEN ts_rank(p.search_tokens, search_query) ELSE 0 END DESC,
    CASE WHEN user_location IS NOT NULL THEN ST_Distance(p.geom, user_location) ELSE 999999999 END ASC,
    p.created_at DESC,
    p.id DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_places TO authenticated, anon;