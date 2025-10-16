-- 20251005_fix_search_price_bug.sql
-- Fix price_level filter bug in search_places

set search_path = public, extensions, gis;

CREATE OR REPLACE FUNCTION public.search_places(
  p_search_text text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_price_level int DEFAULT NULL,
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
  geom geography,
  search_tokens tsvector,
  created_at timestamptz,
  updated_at timestamptz,
  search_rank real
)
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions, gis
AS $$
DECLARE
  search_query tsquery;
BEGIN
  -- Prepare search query if text provided
  IF p_search_text IS NOT NULL AND p_search_text != '' THEN
    search_query := plainto_tsquery('simple', p_search_text);
  END IF;

  RETURN QUERY
  SELECT 
    p.id,
    p.provider,
    p.provider_place_id,
    p.name_ja,
    p.name_en,
    p.name_zh,
    p.postal_code,
    p.prefecture_code,
    p.prefecture_name,
    p.ward,
    p.city,
    p.lat,
    p.lng,
    p.price_level,
    p.categories,
    p.attributes,
    p.geom,
    p.search_tokens,
    p.created_at,
    p.updated_at,
    CASE 
      WHEN p_search_text IS NOT NULL THEN
        ts_rank(p.search_tokens, search_query)
      ELSE 0.0
    END as search_rank
  FROM public.places p
  WHERE 
    -- Text search with tsvector OR trigram fallback for CJK
    (p_search_text IS NULL OR (
      p.search_tokens @@ search_query
      OR p.name_ja ILIKE '%' || p_search_text || '%'
      OR p.name_en ILIKE '%' || p_search_text || '%'
      OR p.name_zh ILIKE '%' || p_search_text || '%'
      OR p.ward ILIKE '%' || p_search_text || '%'
      OR p.city ILIKE '%' || p_search_text || '%'
    ))
    -- Category filter
    AND (p_category IS NULL OR p.categories @> ARRAY[p_category])
    -- Price level filter (FIXED: was comparing p_price_level = p_price_level)
    AND (p_price_level IS NULL OR p.price_level = p_price_level)
    -- Cursor pagination
    AND (
      p_cursor_created_at IS NULL 
      OR p.created_at < p_cursor_created_at
      OR (p.created_at = p_cursor_created_at AND p.id < p_cursor_id)
    )
  ORDER BY 
    CASE WHEN p_search_text IS NOT NULL THEN ts_rank(p.search_tokens, search_query) ELSE 0 END DESC,
    p.created_at DESC,
    p.id DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_places TO authenticated, anon;