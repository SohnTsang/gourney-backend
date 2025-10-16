-- 20251003_enhance_places_search.sql
-- Enhanced search infrastructure for Week 2
-- Adds proper tsvector weights and improved search function

set search_path = public;

-- Drop the old trigger first
DROP TRIGGER IF EXISTS trg_places_tsv ON public.places;
DROP FUNCTION IF EXISTS public.places_tsvector_update();

-- Enhanced tsvector generator with A/B/C weights
-- A weight (1.0): Primary language names
-- B weight (0.4): Secondary language names  
-- C weight (0.2): Location info (city/ward)
CREATE OR REPLACE FUNCTION public.places_tsvector_update()
RETURNS trigger 
LANGUAGE plpgsql 
AS $$
BEGIN
  -- Determine primary language based on data availability
  -- Priority: Japanese > English > Chinese
  IF new.name_ja IS NOT NULL AND new.name_ja != '' THEN
    new.search_tokens := 
      setweight(to_tsvector('simple', coalesce(new.name_ja, '')), 'A') ||
      setweight(to_tsvector('simple', coalesce(new.name_en, '')), 'B') ||
      setweight(to_tsvector('simple', coalesce(new.name_zh, '')), 'B') ||
      setweight(to_tsvector('simple', coalesce(new.city, '')), 'C') ||
      setweight(to_tsvector('simple', coalesce(new.ward, '')), 'C');
  ELSIF new.name_en IS NOT NULL AND new.name_en != '' THEN
    new.search_tokens := 
      setweight(to_tsvector('simple', coalesce(new.name_en, '')), 'A') ||
      setweight(to_tsvector('simple', coalesce(new.name_zh, '')), 'B') ||
      setweight(to_tsvector('simple', coalesce(new.city, '')), 'C') ||
      setweight(to_tsvector('simple', coalesce(new.ward, '')), 'C');
  ELSE
    new.search_tokens := 
      setweight(to_tsvector('simple', coalesce(new.name_zh, '')), 'A') ||
      setweight(to_tsvector('simple', coalesce(new.city, '')), 'C') ||
      setweight(to_tsvector('simple', coalesce(new.ward, '')), 'C');
  END IF;
  
  RETURN new;
END;
$$;

-- Recreate trigger
CREATE TRIGGER trg_places_tsv
  BEFORE INSERT OR UPDATE ON public.places
  FOR EACH ROW 
  EXECUTE FUNCTION public.places_tsvector_update();

-- Update existing rows to use new weights
UPDATE public.places SET updated_at = updated_at;

-- Verify indexes exist (from Week 1)
-- These should already exist, but let's confirm
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE tablename = 'places' AND indexname = 'idx_places_search_tokens'
  ) THEN
    CREATE INDEX idx_places_search_tokens ON public.places USING gin(search_tokens);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE tablename = 'places' AND indexname = 'idx_places_trgm_ja'
  ) THEN
    CREATE INDEX idx_places_trgm_ja ON public.places USING gin(name_ja gin_trgm_ops);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE tablename = 'places' AND indexname = 'idx_places_trgm_en'
  ) THEN
    CREATE INDEX idx_places_trgm_en ON public.places USING gin(name_en gin_trgm_ops);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE tablename = 'places' AND indexname = 'idx_places_trgm_zh'
  ) THEN
    CREATE INDEX idx_places_trgm_zh ON public.places USING gin(name_zh gin_trgm_ops);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE tablename = 'places' AND indexname = 'idx_places_geom'
  ) THEN
    CREATE INDEX idx_places_geom ON public.places USING gist(geom);
  END IF;
END $$;

-- Add composite index for cursor pagination
CREATE INDEX IF NOT EXISTS idx_places_created_id 
  ON public.places(created_at DESC, id DESC);

-- Comments for documentation
COMMENT ON FUNCTION public.places_tsvector_update() IS 
  'Generates weighted full-text search tokens: A=primary name, B=secondary names, C=location';

COMMENT ON INDEX idx_places_search_tokens IS 
  'GIN index for full-text search with tsvector weights';

COMMENT ON INDEX idx_places_created_id IS 
  'Composite index for stable cursor pagination';