-- 20251014_fix_user_profile_public_access.sql
-- Fix get_user_profile to allow unauthenticated access for public profiles
-- This ensures profiles can be viewed without authentication

BEGIN;
SET search_path = public, extensions;

-- ============================================
-- Fix get_user_profile function to allow anonymous access
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
  v_viewer UUID;
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
  -- Allow both authenticated and anonymous viewers
  -- If p_viewer_id is provided, use it; otherwise try auth.uid() (which may be NULL)
  v_viewer := COALESCE(p_viewer_id, auth.uid());
  
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

  -- Check if blocked (only if viewer is authenticated)
  IF v_viewer IS NOT NULL THEN
    SELECT app.is_blocked(v_viewer, v_user.id) INTO v_is_blocked;
    
    IF v_is_blocked THEN
      RETURN jsonb_build_object(
        'status', 403,
        'error', 'user_blocked'
      );
    END IF;
  END IF;

  -- Get follower/following counts (always visible)
  SELECT COUNT(*) INTO v_follower_count
  FROM public.follows
  WHERE followee_id = v_user.id;

  SELECT COUNT(*) INTO v_following_count
  FROM public.follows
  WHERE follower_id = v_user.id;

  -- Check relationship with viewer (only if viewer is authenticated)
  IF v_viewer IS NOT NULL AND v_viewer != v_user.id THEN
    -- Viewer is authenticated and viewing someone else
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
    -- Viewer is viewing their own profile
    v_relationship := 'self';
  ELSE
    -- Viewer is not authenticated (anonymous)
    v_relationship := 'stranger';
  END IF;

  -- Count visible visits based on viewer relationship
  IF v_relationship = 'self' THEN
    -- Owner sees all their visits
    SELECT COUNT(*) INTO v_visit_count
    FROM public.visits
    WHERE user_id = v_user.id
      AND deleted_at IS NULL;
  ELSIF v_relationship IN ('following', 'mutual') THEN
    -- Friends see public + friends visits
    SELECT COUNT(*) INTO v_visit_count
    FROM public.visits
    WHERE user_id = v_user.id
      AND visibility IN ('public', 'friends')
      AND deleted_at IS NULL;
  ELSE
    -- Strangers and anonymous viewers see only public visits
    SELECT COUNT(*) INTO v_visit_count
    FROM public.visits
    WHERE user_id = v_user.id
      AND visibility = 'public'
      AND deleted_at IS NULL;
  END IF;

  -- Count visible lists based on viewer relationship
  IF v_relationship = 'self' THEN
    -- Owner sees all their lists
    SELECT COUNT(*) INTO v_list_count
    FROM public.lists
    WHERE user_id = v_user.id;
  ELSIF v_relationship IN ('following', 'mutual') THEN
    -- Friends see public + friends lists
    SELECT COUNT(*) INTO v_list_count
    FROM public.lists
    WHERE user_id = v_user.id
      AND visibility IN ('public', 'friends');
  ELSE
    -- Strangers and anonymous viewers see only public lists
    SELECT COUNT(*) INTO v_list_count
    FROM public.lists
    WHERE user_id = v_user.id
      AND visibility = 'public';
  END IF;

  -- Return profile with all data
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

-- Ensure function can be called by both authenticated and anonymous users
GRANT EXECUTE ON FUNCTION public.get_user_profile(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_profile(TEXT, UUID) TO anon;

-- Add comment
COMMENT ON FUNCTION public.get_user_profile IS 
'Week 5 Step 5: Get user profile with relationship context. Supports both authenticated and anonymous access for public profiles.';

COMMIT;