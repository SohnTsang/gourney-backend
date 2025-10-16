-- 20251011_enable_leaderboard_city_scores_trigger.sql
-- Week 5 · Step 1A: Enable leaderboard + trigger to update city_scores on visits insert

BEGIN;

SET search_path = public, extensions;

-- 0) Ensure remote_config table exists (key/value store)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'remote_config'
  ) THEN
    CREATE TABLE public.remote_config (
      key   text PRIMARY KEY,
      value jsonb NOT NULL DEFAULT '{}'::jsonb,
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  END IF;
END$$;

-- 1) Enable leaderboard via feature flag
INSERT INTO public.remote_config (key, value)
VALUES ('enable_leaderboard', jsonb_build_object('enabled', true))
ON CONFLICT (key) DO UPDATE
SET value = jsonb_build_object('enabled', true),
    updated_at = now();

-- 2) Ensure city_scores table exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='city_scores'
  ) THEN
    CREATE TABLE public.city_scores (
      user_id         uuid    NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      city            text    NOT NULL,
      week_start_date date    NOT NULL,  -- Monday ISO week start
      weekly_points   int     NOT NULL DEFAULT 0,
      lifetime_points int     NOT NULL DEFAULT 0,
      created_at      timestamptz NOT NULL DEFAULT now(),
      updated_at      timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (user_id, city, week_start_date)
    );
  END IF;
END$$;

-- 3) Helpful indexes for leaderboard queries
CREATE INDEX IF NOT EXISTS idx_city_scores_city_weekly
  ON public.city_scores (city, weekly_points DESC, user_id ASC);

CREATE INDEX IF NOT EXISTS idx_city_scores_city_lifetime
  ON public.city_scores (city, lifetime_points DESC, user_id ASC);

CREATE INDEX IF NOT EXISTS idx_city_scores_user
  ON public.city_scores (user_id, city);

-- 4) Trigger function: update city_scores after a new visit
--    - Points: first visit to a place = +3, repeat (different day) = +1
--    - +1 if photo present
--    - Uses place.city; if absent, tries users.home_city (and safely ignores if column doesn't exist)
CREATE OR REPLACE FUNCTION public.update_city_scores()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_points               int := 0;
  v_city                 text;
  v_week_start           date;
  v_already_scored_today boolean;
  v_enabled              boolean;
BEGIN
  -- Feature flag
  SELECT COALESCE( (value->>'enabled')::boolean, false )
    INTO v_enabled
    FROM public.remote_config
   WHERE key = 'enable_leaderboard';
  IF NOT COALESCE(v_enabled, false) THEN
    RETURN NEW;
  END IF;

  -- City from place first
  SELECT p.city INTO v_city
    FROM public.places p
   WHERE p.id = NEW.place_id;

  -- If no city on place, try users.home_city but guard against missing column
  IF v_city IS NULL THEN
    BEGIN
      EXECUTE $sql$
        SELECT home_city::text FROM public.users WHERE id = $1
      $sql$ USING NEW.user_id
      INTO v_city;
    EXCEPTION
      WHEN undefined_column THEN
        -- users.home_city does not exist; ignore
        v_city := NULL;
    END;
  END IF;

  -- If still no city, skip scoring
  IF v_city IS NULL THEN
    RETURN NEW;
  END IF;

  -- ISO week start (Monday) from visited_at or now()
  v_week_start := date_trunc('week', COALESCE(NEW.visited_at, now()))::date;

  -- No points if user already scored for this place "today"
  SELECT EXISTS (
    SELECT 1
      FROM public.visits v
     WHERE v.user_id = NEW.user_id
       AND v.place_id = NEW.place_id
       AND date(v.created_at) = date(COALESCE(NEW.visited_at, now()))
       AND v.id <> NEW.id
  ) INTO v_already_scored_today;

  IF v_already_scored_today THEN
    RETURN NEW;
  END IF;

  -- Points: first-ever visit (+3) vs repeat (+1)
  IF NOT EXISTS (
    SELECT 1
      FROM public.visits v
     WHERE v.user_id = NEW.user_id
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

  -- Upsert into city_scores
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

-- 5) Create/replace trigger
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trigger_update_city_scores'
  ) THEN
    DROP TRIGGER trigger_update_city_scores ON public.visits;
  END IF;

  CREATE TRIGGER trigger_update_city_scores
    AFTER INSERT ON public.visits
    FOR EACH ROW
    EXECUTE FUNCTION public.update_city_scores();
END$$;

COMMIT;
