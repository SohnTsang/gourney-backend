-- 20251003_add_upsert_place_rpc.sql
-- Add RPC function for upserting places with proper geography handling
-- CRITICAL: Includes gis schema in search_path for geography type

set search_path = public, extensions, gis;

CREATE OR REPLACE FUNCTION public.upsert_place(
  p_provider text,
  p_provider_place_id text,
  p_name_ja text,
  p_name_en text,
  p_name_zh text,
  p_postal_code text,
  p_prefecture_code text,
  p_prefecture_name text,
  p_ward text,
  p_city text,
  p_lat double precision,
  p_lng double precision,
  p_price_level int,
  p_categories text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, gis
SET client_encoding = 'UTF8'
AS $$
DECLARE
  place_id uuid;
BEGIN
  INSERT INTO public.places (
    provider, provider_place_id, name_ja, name_en, name_zh,
    postal_code, prefecture_code, prefecture_name, ward, city,
    geom, lat, lng, price_level, categories, attributes
  ) VALUES (
    p_provider, p_provider_place_id, p_name_ja, p_name_en, p_name_zh,
    p_postal_code, p_prefecture_code, p_prefecture_name, p_ward, p_city,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_lat, p_lng, p_price_level, p_categories, '{}'::jsonb
  )
  ON CONFLICT (provider_place_id) DO UPDATE SET
    name_ja = EXCLUDED.name_ja,
    name_en = EXCLUDED.name_en,
    name_zh = EXCLUDED.name_zh,
    postal_code = EXCLUDED.postal_code,
    prefecture_code = EXCLUDED.prefecture_code,
    prefecture_name = EXCLUDED.prefecture_name,
    ward = EXCLUDED.ward,
    city = EXCLUDED.city,
    geom = EXCLUDED.geom,
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    price_level = EXCLUDED.price_level,
    categories = EXCLUDED.categories,
    updated_at = now()
  RETURNING id INTO place_id;
  
  RETURN place_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_place TO service_role;

COMMENT ON FUNCTION public.upsert_place IS 
  'Upserts place data with PostGIS geography. Requires gis schema in search_path.';

-- Down migration
-- DROP FUNCTION IF EXISTS public.upsert_place(text, text, text, text, text, text, text, text, text, text, double precision, double precision, int, text[]);