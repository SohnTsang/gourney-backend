-- 20251011_enable_leaderboard_trigger_only.sql
-- Week 5 · Step 1A: enable leaderboard + create trigger (schema-accurate)

BEGIN;
SET search_path = public, extensions;

-- 1) Feature flag (remote_config has only key, value)
INSERT INTO public.remote_config (key, value)
VALUES ('enable_leaderboard', jsonb_build_object('enabled', true))
ON CONFLICT (key) DO UPDATE
SET value = jsonb_build_object('enabled', true);

-- 2) Trigger function
--    Notes (matches your schema):
--      - visits.visited_at is DATE
--      - city_scores has updated_at (but not created_at)
--      - prefer place.city; fallback to users.home_city (column exists)
--      - v.photo_urls is an array; null-safe check
--      - "already scored today" = same user/place and same visited_at DATE
CREATE OR REPLACE FUNCTION public.update_city_scores()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_points int := 0;
  v_city   text;
  v_week_start date;
  v_enabled boolean;
  v_already_scored_today boolean;
BEGIN
  -- Feature flag
  SELECT COALESCE((value->>'enabled')::boolean, false)
    INTO v_enabled
    FROM public.remote_config
   WHERE key = 'enable_leaderboard';

  IF NOT v_enabled THEN
    RETURN NEW;
  END IF;

  -- City from place first
  SELECT p.city INTO v_city
    FROM public.places p
   WHERE p.id = NEW.place_id;

  -- Fallback to user's home_city
  IF v_city IS NULL THEN
    SELECT u.home_city INTO v_city
      FROM public.users u
     WHERE u.id = NEW.user_id;
  END IF;

  -- If still unknown, skip
  IF v_city IS NULL THEN
    RETURN NEW;
  END IF;

  -- Compute ISO week start (Monday) from DATE
  -- dow: 0=Sunday ... 6=Saturday; shift so Monday=0
  v_week_start := NEW.visited_at
                  - ((EXTRACT(dow FROM NEW.visited_at)::int + 6) % 7);

  -- No points if already scored same place on same day
  SELECT EXISTS (
    SELECT 1
      FROM public.visits v
     WHERE v.user_id  = NEW.user_id
       AND v.place_id = NEW.place_id
       AND v.visited_at = NEW.visited_at
       AND v.id <> NEW.id
  ) INTO v_already_scored_today;

  IF v_already_scored_today THEN
    RETURN NEW;
  END IF;

  -- Points: first-ever visit to this place (+3) vs repeat (+1)
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

  -- +1 for a photo (null-safe)
  IF COALESCE(array_length(NEW.photo_urls, 1), 0) > 0 THEN
    v_points := v_points + 1;
  END IF;

  -- Upsert into city_scores (table already exists with updated_at)
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

-- 3) Trigger (drop if present, then create)
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
