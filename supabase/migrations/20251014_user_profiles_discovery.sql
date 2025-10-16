-- 20251014_user_profiles_discovery.sql
-- Week 5 Step 5: User Profiles & Discovery Infrastructure

BEGIN;
SET search_path = public, extensions;

-- ============================================
-- 1. Create user profile view function
-- ============================================

CREATE OR REPLACE FUNCTION public.get_user_profile(
  p_handle TEXT,
  p_viewer_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_viewer UUID := COALESCE(p_viewer_id, auth.uid());
  v_user RECORD;
  v_follower_count INT;
  v_following_count INT;
  v_visit_count INT;
  v_list_count INT;
  v_is_following BOOLEAN := FALSE;
  v_follows_viewer BOOLEAN := FALSE;
  v_is_blocked BOOLEAN := FALSE;
  v_relationship TEXT := 'stranger';
BEGIN
  -- Get user by handle
  SELECT 
    u.id,
    u.handle,
    u.display_name,
    u.avatar_url,
    u.home_city,
    u.created_at
  INTO v_user
  FROM public.users u
  WHERE u.handle = p_handle
    AND u.deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 404,
      'error', 'user_not_found'
    );
  END IF;

  -- Check if blocked
  IF v_viewer IS NOT NULL THEN
    SELECT app.is_blocked(v_viewer, v_user.id) INTO v_is_blocked;
    
    IF v_is_blocked THEN
      RETURN jsonb_build_object(
        'status', 403,
        'error', 'user_blocked'
      );
    END IF;
  END IF;

  -- Get follower/following counts
  SELECT COUNT(*) INTO v_follower_count
  FROM public.follows
  WHERE followee_id = v_user.id;

  SELECT COUNT(*) INTO v_following_count
  FROM public.follows
  WHERE follower_id = v_user.id;

  -- Check relationship with viewer
  IF v_viewer IS NOT NULL AND v_viewer != v_user.id THEN
    SELECT EXISTS(
      SELECT 1 FROM public.follows
      WHERE follower_id = v_viewer AND followee_id = v_user.id
    ) INTO v_is_following;

    SELECT EXISTS(
      SELECT 1 FROM public.follows
      WHERE follower_id = v_user.id AND followee_id = v_viewer
    ) INTO v_follows_viewer;

    IF v_is_following AND v_follows_viewer THEN
      v_relationship := 'mutual';
    ELSIF v_is_following THEN
      v_relationship := 'following';
    ELSIF v_follows_viewer THEN
      v_relationship := 'follower';
    END IF;
  ELSIF v_viewer = v_user.id THEN
    v_relationship := 'self';
  END IF;

  -- Count visible visits based on viewer relationship
  IF v_relationship = 'self' THEN
    -- Owner sees all their visits
    SELECT COUNT(*) INTO v_visit_count
    FROM public.visits
    WHERE user_id = v_user.id;
  ELSIF v_relationship IN ('following', 'mutual') THEN
    -- Friends see public + friends visits
    SELECT COUNT(*) INTO v_visit_count
    FROM public.visits
    WHERE user_id = v_user.id
      AND visibility IN ('public', 'friends');
  ELSE
    -- Strangers see only public visits
    SELECT COUNT(*) INTO v_visit_count
    FROM public.visits
    WHERE user_id = v_user.id
      AND visibility = 'public';
  END IF;

  -- Count visible lists
  IF v_relationship = 'self' THEN
    SELECT COUNT(*) INTO v_list_count
    FROM public.lists
    WHERE user_id = v_user.id;
  ELSIF v_relationship IN ('following', 'mutual') THEN
    SELECT COUNT(*) INTO v_list_count
    FROM public.lists
    WHERE user_id = v_user.id
      AND visibility IN ('public', 'friends');
  ELSE
    SELECT COUNT(*) INTO v_list_count
    FROM public.lists
    WHERE user_id = v_user.id
      AND visibility = 'public';
  END IF;

  -- Return profile
  RETURN jsonb_build_object(
    'status', 200,
    'user', jsonb_build_object(
      'id', v_user.id,
      'handle', v_user.handle,
      'display_name', v_user.display_name,
      'avatar_url', v_user.avatar_url,
      'home_city', v_user.home_city,
      'created_at', v_user.created_at,
      'follower_count', v_follower_count,
      'following_count', v_following_count,
      'visit_count', v_visit_count,
      'list_count', v_list_count,
      'relationship', v_relationship,
      'is_following', v_is_following,
      'follows_you', v_follows_viewer
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_profile(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_profile(TEXT, UUID) TO anon;

-- ============================================
-- 2. Create user search function
-- ============================================

CREATE OR REPLACE FUNCTION public.search_users(
  p_query TEXT,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_viewer UUID := auth.uid();
  v_limit INT := GREATEST(1, LEAST(COALESCE(p_limit, 20), 50));
  v_offset INT := GREATEST(0, COALESCE(p_offset, 0));
  v_results JSONB;
  v_total_count INT;
BEGIN
  -- Sanitize query
  IF p_query IS NULL OR LENGTH(TRIM(p_query)) < 2 THEN
    RETURN jsonb_build_object(
      'status', 400,
      'error', 'query_too_short',
      'detail', 'Search query must be at least 2 characters'
    );
  END IF;

  -- Count total matches
  SELECT COUNT(*) INTO v_total_count
  FROM public.users u
  WHERE u.deleted_at IS NULL
    AND (
      u.handle ILIKE '%' || p_query || '%'
      OR u.display_name ILIKE '%' || p_query || '%'
    )
    AND (v_viewer IS NULL OR NOT app.is_blocked(v_viewer, u.id));

  -- Get paginated results
  WITH search_results AS (
    SELECT 
      u.id,
      u.handle,
      u.display_name,
      u.avatar_url,
      u.home_city,
      (SELECT COUNT(*) FROM public.follows f WHERE f.followee_id = u.id) AS follower_count,
      CASE 
        WHEN v_viewer IS NOT NULL THEN EXISTS(
          SELECT 1 FROM public.follows f 
          WHERE f.follower_id = v_viewer AND f.followee_id = u.id
        )
        ELSE FALSE
      END AS is_following,
      CASE
        WHEN u.handle ILIKE p_query || '%' THEN 1
        WHEN u.display_name ILIKE p_query || '%' THEN 2
        WHEN u.handle ILIKE '%' || p_query || '%' THEN 3
        ELSE 4
      END AS match_rank
    FROM public.users u
    WHERE u.deleted_at IS NULL
      AND (
        u.handle ILIKE '%' || p_query || '%'
        OR u.display_name ILIKE '%' || p_query || '%'
      )
      AND (v_viewer IS NULL OR NOT app.is_blocked(v_viewer, u.id))
    ORDER BY match_rank ASC, follower_count DESC, u.handle ASC
    LIMIT v_limit
    OFFSET v_offset
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]'::jsonb)
  INTO v_results
  FROM search_results sr;

  RETURN jsonb_build_object(
    'status', 200,
    'users', v_results,
    'total_count', v_total_count,
    'limit', v_limit,
    'offset', v_offset
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_users(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_users(TEXT, INTEGER, INTEGER) TO anon;

-- ============================================
-- 3. Create suggested follows function
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
BEGIN
  IF v_viewer IS NULL THEN
    RETURN jsonb_build_object(
      'status', 401,
      'error', 'authentication_required'
    );
  END IF;

  -- Get viewer's home city
  DECLARE
    v_home_city TEXT;
  BEGIN
    SELECT home_city INTO v_home_city
    FROM public.users
    WHERE id = v_viewer;
  END;

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
    SELECT * FROM friends_of_friends
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

-- ============================================
-- 4. Add comments for documentation
-- ============================================

COMMENT ON FUNCTION public.get_user_profile IS 'Week 5 Step 5: Get user profile with relationship context';
COMMENT ON FUNCTION public.search_users IS 'Week 5 Step 5: Search users by handle or display name';
COMMENT ON FUNCTION public.get_suggested_follows IS 'Week 5 Step 5: Get personalized follow suggestions';

COMMIT;