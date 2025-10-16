-- 20251015_leaderboard_ugc_integration.sql
-- Award points for approved UGC place submissions

BEGIN;
SET search_path = public, extensions, gis;

-- Function to award points for UGC place approval
CREATE OR REPLACE FUNCTION award_ugc_place_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_city TEXT;
  v_week_start DATE;
  v_enabled BOOLEAN;
BEGIN
  -- Only award points when place becomes approved (not already approved)
  IF NEW.moderation_status != 'approved' OR OLD.moderation_status = 'approved' THEN
    RETURN NEW;
  END IF;

  -- Only for user-generated places
  IF NEW.created_by IS NULL THEN
    RETURN NEW;
  END IF;

  -- Check if leaderboard is enabled
  SELECT COALESCE((value->>'enabled')::boolean, false)
    INTO v_enabled
    FROM public.remote_config
   WHERE key = 'enable_leaderboard';
   
  IF NOT v_enabled THEN
    RETURN NEW;
  END IF;

  -- Get city from place
  v_city := NEW.city;
  
  -- If no city, get from user's home_city
  IF v_city IS NULL THEN
    SELECT home_city INTO v_city
    FROM public.users
    WHERE id = NEW.created_by;
  END IF;

  -- Skip if still no city
  IF v_city IS NULL THEN
    RETURN NEW;
  END IF;

  -- Calculate week start (Monday)
  v_week_start := date_trunc('week', NOW())::date;

  -- Award +3 points for approved UGC place
  INSERT INTO public.city_scores (user_id, city, week_start_date, weekly_points, lifetime_points)
  VALUES (NEW.created_by, v_city, v_week_start, 3, 3)
  ON CONFLICT (user_id, city, week_start_date)
  DO UPDATE SET
    weekly_points = public.city_scores.weekly_points + 3,
    lifetime_points = public.city_scores.lifetime_points + 3,
    updated_at = NOW();

  RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_award_ugc_place_points ON places;
CREATE TRIGGER trigger_award_ugc_place_points
  AFTER UPDATE ON places
  FOR EACH ROW
  EXECUTE FUNCTION award_ugc_place_points();

COMMENT ON FUNCTION award_ugc_place_points IS 
  'Week 6: Award +3 leaderboard points when UGC place is approved';

COMMIT;