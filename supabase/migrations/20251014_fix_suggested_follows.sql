-- 20251014_fix_suggested_follows.sql
-- Fix get_suggested_follows function - variable declaration issue

BEGIN;
SET search_path = public, extensions;

-- ============================================
-- Fix get_suggested_follows function
-- ============================================

CREATE OR REPLACE FUNCTION public.get_suggested_follows(
  p_limit INTEGER DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_viewer UUID := auth.uid();
  v_limit INT := GREATEST(1, LEAST(COALESCE(p_limit, 20), 50));
  v_suggestions JSONB;
  v_home_city TEXT;  -- Add this declaration at the top level
BEGIN
  IF v_viewer IS NULL THEN
    RETURN jsonb_build_object(
      'status', 401,
      'error', 'authentication_required'
    );
  END IF;

  -- Get viewer's home city
  SELECT home_city INTO v_home_city
  FROM public.users
  WHERE id = v_viewer;

  -- If user has no home city, use a default or skip city-based suggestions
  IF v_home_city IS NULL THEN
    v_home_city := 'Tokyo';  -- Default fallback
  END IF;

  WITH friends_of_friends AS (
    -- Friends of friends
    SELECT DISTINCT
      u.id,
      u.handle,
      u.display_name,
      u.avatar_url,
      u.home_city,
      COUNT(DISTINCT f1.follower_id) AS mutual_friends_count,
      'friends_of_friends' AS reason
    FROM public.users u
    JOIN public.follows f2 ON f2.followee_id = u.id
    JOIN public.follows f1 ON f1.followee_id = f2.follower_id
    WHERE f1.follower_id = v_viewer
      AND u.id != v_viewer
      AND u.deleted_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.follows f3
        WHERE f3.follower_id = v_viewer AND f3.followee_id = u.id
      )
      AND NOT app.is_blocked(v_viewer, u.id)
    GROUP BY u.id, u.handle, u.display_name, u.avatar_url, u.home_city
    ORDER BY mutual_friends_count DESC
    LIMIT 10
  ),
  top_active_users AS (
    -- Top users by weekly points in same city
    SELECT DISTINCT
      u.id,
      u.handle,
      u.display_name,
      u.avatar_url,
      u.home_city,
      0 AS mutual_friends_count,
      'top_active' AS reason,
      cs.weekly_points
    FROM public.users u
    JOIN public.city_scores cs ON cs.user_id = u.id
    WHERE u.id != v_viewer
      AND u.deleted_at IS NULL
      AND cs.city = v_home_city
      AND cs.week_start_date = date_trunc('week', CURRENT_DATE)::date
      AND NOT EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = v_viewer AND f.followee_id = u.id
      )
      AND NOT app.is_blocked(v_viewer, u.id)
    ORDER BY cs.weekly_points DESC
    LIMIT 10
  ),
  combined AS (
    SELECT id, handle, display_name, avatar_url, home_city, mutual_friends_count, reason
    FROM friends_of_friends
    UNION ALL
    SELECT id, handle, display_name, avatar_url, home_city, mutual_friends_count, reason
    FROM top_active_users
  ),
  deduplicated AS (
    SELECT DISTINCT ON (id)
      id,
      handle,
      display_name,
      avatar_url,
      home_city,
      mutual_friends_count,
      reason
    FROM combined
    ORDER BY id, mutual_friends_count DESC, random()
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY random()), '[]'::jsonb)
  INTO v_suggestions
  FROM deduplicated d
  LIMIT v_limit;

  RETURN jsonb_build_object(
    'status', 200,
    'suggestions', v_suggestions
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_suggested_follows(INTEGER) TO authenticated;

COMMENT ON FUNCTION public.get_suggested_follows IS 
'Week 5 Step 5: Get personalized follow suggestions (friends-of-friends + top active users)';

COMMIT;
