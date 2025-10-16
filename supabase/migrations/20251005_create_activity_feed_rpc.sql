-- 20251005_create_activity_feed_rpc.sql
-- Activity feed query with full visibility/blocking/deletion filtering

CREATE OR REPLACE FUNCTION get_activity_feed(
  p_limit INTEGER DEFAULT 20,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id BIGINT DEFAULT NULL
)
RETURNS TABLE(
  activity_id BIGINT,
  activity_type TEXT,
  activity_created_at TIMESTAMPTZ,
  actor_id UUID,
  actor_handle TEXT,
  actor_display_name TEXT,
  actor_avatar_url TEXT,
  visit_id UUID,
  visit_rating SMALLINT,
  visit_comment TEXT,
  visit_photo_urls TEXT[],
  visit_visited_at DATE,
  place_id UUID,
  place_name_en TEXT,
  place_name_ja TEXT,
  place_city TEXT,
  place_ward TEXT,
  place_categories TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  current_user_id UUID;
BEGIN
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RETURN QUERY
  SELECT 
    a.id AS activity_id,
    a.type AS activity_type,
    a.created_at AS activity_created_at,
    u.id AS actor_id,
    u.handle AS actor_handle,
    u.display_name AS actor_display_name,
    u.avatar_url AS actor_avatar_url,
    v.id AS visit_id,
    v.rating AS visit_rating,
    v.comment AS visit_comment,
    v.photo_urls AS visit_photo_urls,
    v.visited_at AS visit_visited_at,
    p.id AS place_id,
    p.name_en AS place_name_en,
    p.name_ja AS place_name_ja,
    p.city AS place_city,
    p.ward AS place_ward,
    p.categories AS place_categories
  FROM activity a
  INNER JOIN users u ON a.actor_id = u.id
  LEFT JOIN visits v ON a.type = 'visit' AND a.subject_id = v.id
  LEFT JOIN places p ON v.place_id = p.id
  WHERE
    -- Only show activities from friends or self
    (
      a.actor_id = current_user_id
      OR EXISTS (
        SELECT 1 FROM follows f 
        WHERE f.follower_id = current_user_id 
        AND f.followee_id = a.actor_id
      )
    )
    -- Respect visibility
    AND (
      a.visibility = 'public'
      OR (a.visibility = 'friends' AND EXISTS (
        SELECT 1 FROM follows f
        WHERE f.follower_id = current_user_id
        AND f.followee_id = a.actor_id
      ))
      OR a.actor_id = current_user_id
    )
    -- Exclude blocked users (bidirectional)
    AND NOT EXISTS (
      SELECT 1 FROM user_blocks ub
      WHERE (ub.blocker_id = current_user_id AND ub.blockee_id = a.actor_id)
         OR (ub.blocker_id = a.actor_id AND ub.blockee_id = current_user_id)
    )
    -- Exclude deleted users
    AND u.deleted_at IS NULL
    -- Cursor pagination
    AND (
      p_cursor_created_at IS NULL
      OR a.created_at < p_cursor_created_at
      OR (a.created_at = p_cursor_created_at AND a.id < p_cursor_id)
    )
  ORDER BY a.created_at DESC, a.id DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_activity_feed TO authenticated;

-- Down migration:
-- DROP FUNCTION IF EXISTS get_activity_feed(INTEGER, TIMESTAMPTZ, BIGINT);