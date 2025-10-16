-- migration_ugc_place_rpc.sql
-- RPC function for inserting UGC places with proper geography handling

SET search_path = public, extensions, gis;

CREATE OR REPLACE FUNCTION public.upsert_ugc_place(
  p_provider text,
  p_provider_place_id text,
  p_name_en text,
  p_name_ja text,
  p_name_zh text,
  p_city text,
  p_ward text,
  p_lat double precision,
  p_lng double precision,
  p_categories text[],
  p_price_level int,
  p_created_by uuid,
  p_submitted_photo_url text,
  p_submission_notes text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, gis
AS $$
DECLARE
  v_place_id uuid;
BEGIN
  INSERT INTO public.places (
    provider,
    provider_place_id,
    name_en,
    name_ja,
    name_zh,
    city,
    ward,
    geom,
    lat,
    lng,
    categories,
    price_level,
    created_by,
    moderation_status,
    submitted_photo_url,
    submission_notes
  ) VALUES (
    p_provider,
    p_provider_place_id,
    p_name_en,
    p_name_ja,
    p_name_zh,
    p_city,
    p_ward,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_lat,
    p_lng,
    p_categories,
    p_price_level,
    p_created_by,
    'pending',
    p_submitted_photo_url,
    p_submission_notes
  )
  RETURNING id INTO v_place_id;
  
  RETURN v_place_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_ugc_place TO authenticated;

COMMENT ON FUNCTION public.upsert_ugc_place IS 
  'Week 6 Step 3: Insert user-generated place with pending moderation status';