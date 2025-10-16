-- 20251012_fix_leaderboard_trigger.sql
BEGIN;
SET search_path = public, extensions;

-- Replace trigger function with hardened version
CREATE OR REPLACE FUNCTION public.update_city_scores()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_points int := 0;
  v_city   text;
  v_day    date;
  v_week_start date;
  v_enabled boolean;
  v_already_scored boolean;
BEGIN
  -- Defensive search_path
  PERFORM set_config('search_path', 'public,extensions', true);

  -- Feature flag (remote_config has only key,value)
  SELECT COALESCE((value->>'enabled')::boolean, false)
    INTO v_enabled
    FROM public.remote_config
   WHERE key = 'enable_leaderboard';
  IF NOT v_enabled THEN
    RETURN NEW;
  END IF;

  -- Effective visit day (DATE)
  v_day := COALESCE(NEW.visited_at, CURRENT_DATE);

  -- City: place.city first
  SELECT p.city INTO v_city
    FROM public.places p
   WHERE p.id = NEW.place_id;

  -- Fallback to users.home_city
  IF v_city IS NULL THEN
    SELECT u.home_city INTO v_city
      FROM public.users u
     WHERE u.id = NEW.user_id;
  END IF;

  -- Skip if still unknown
  IF v_city IS NULL THEN
    RETURN NEW;
  END IF;

  -- ISO Monday week start for v_day
  v_week_start := v_day - ((EXTRACT(dow FROM v_day)::int + 6) % 7);

  -- Already scored same place, same day?
  SELECT EXISTS (
    SELECT 1
      FROM public.visits v
     WHERE v.user_id   = NEW.user_id
       AND v.place_id  = NEW.place_id
       AND v.visited_at = v_day
       AND v.id       <> NEW.id
  ) INTO v_already_scored;

  IF v_already_scored THEN
    RETURN NEW;
  END IF;

  -- First-ever visit to this place?
  IF NOT EXISTS (
    SELECT 1
      FROM public.visits v
     WHERE v.user_id  = NEW.user_id
       AND v.place_id = NEW.place_id
       AND v.id <> NEW.id
  ) THEN
    v_points := 3;
  ELSE
    v_points := 1;
  END IF;

  -- +1 for photo (null-safe)
  IF COALESCE(array_length(NEW.photo_urls, 1), 0) > 0 THEN
    v_points := v_points + 1;
  END IF;

  -- Upsert into city_scores (your table has updated_at but not created_at)
  INSERT INTO public.city_scores (user_id, city, week_start_date, weekly_points, lifetime_points)
  VALUES (NEW.user_id, v_city, v_week_start, v_points, v_points)
  ON CONFLICT (user_id, city, week_start_date)
  DO UPDATE SET
    weekly_points   = public.city_scores.weekly_points + v_points,
    lifetime_points = public.city_scores.lifetime_points + v_points,
    updated_at      = now();

  RETURN NEW;
END;
$fn$;

-- Drop & recreate trigger to be absolutely sure it's attached to public.visits
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_update_city_scores') THEN
    DROP TRIGGER trigger_update_city_scores ON public.visits;
  END IF;

  CREATE TRIGGER trigger_update_city_scores
    AFTER INSERT ON public.visits
    FOR EACH ROW
    EXECUTE FUNCTION public.update_city_scores();
END$$;

COMMIT;
