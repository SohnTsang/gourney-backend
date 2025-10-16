-- 20251011_fix_places_get_visits.sql
-- Phase: Week-1 (Stable cursors) + Week-5 (List API semantics)
-- Purpose:
--   * Replace fn_places_get_visits_v1 (no reference to places.name)
--   * Return 200 + [] for empty; 404 only if place not found
--   * Use keyset pagination (created_at DESC, id DESC)
--   * Ensure composite indexes exist

BEGIN;

SET search_path = public, extensions;

-- Drop any previous versions (different integer aliases, etc.)
DROP FUNCTION IF EXISTS public.fn_places_get_visits_v1(uuid, integer, text, boolean);
DROP FUNCTION IF EXISTS public.fn_places_get_visits_v1(uuid, int,     text, boolean);

CREATE OR REPLACE FUNCTION public.fn_places_get_visits_v1(
  p_place_id     uuid,
  p_limit        integer DEFAULT 20,
  p_cursor       text    DEFAULT NULL,
  p_friends_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_viewer       uuid := auth.uid();  -- Supabase-authenticated user
  v_place_exists boolean;
  v_rows         integer := GREATEST(1, LEAST(COALESCE(p_limit, 20), 50));
  v_created_at   timestamptz;
  v_id           uuid;
  v_has_more     boolean := false;
  v_next_cursor  text    := null;
  v_visit_count  bigint  := 0;
  v_visits       jsonb   := '[]'::jsonb;
BEGIN
  -- Ensure place exists
  SELECT EXISTS(SELECT 1 FROM public.places WHERE id = p_place_id)
    INTO v_place_exists;

  IF NOT v_place_exists THEN
    RETURN jsonb_build_object('status', 404, 'error', 'place_not_found');
  END IF;

  -- Decode cursor base64("created_at|id"), tolerate invalid cursor
  IF p_cursor IS NOT NULL THEN
    BEGIN
      SELECT
        (split_part(convert_from(decode(p_cursor, 'base64'), 'utf8'), '|', 1))::timestamptz,
        (split_part(convert_from(decode(p_cursor, 'base64'), 'utf8'), '|', 2))::uuid
      INTO v_created_at, v_id;
    EXCEPTION WHEN OTHERS THEN
      v_created_at := NULL;
      v_id         := NULL;
    END;
  END IF;

  -- Count with same visibility semantics as your RLS
  SELECT COUNT(*)
    INTO v_visit_count
    FROM public.visits v
   WHERE v.place_id = p_place_id
     AND (
       v.user_id = v_viewer
       OR (
         v.visibility = 'public'
         AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = v.user_id AND u.deleted_at IS NOT NULL)
         AND NOT EXISTS (
           SELECT 1 FROM public.user_blocks ub
            WHERE (ub.blocker_id = v_viewer AND ub.blockee_id = v.user_id)
               OR (ub.blocker_id = v.user_id  AND ub.blockee_id = v_viewer)
         )
       )
       OR (
         v.visibility = 'friends'
         AND EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = v_viewer AND f.followee_id = v.user_id)
         AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = v.user_id AND u.deleted_at IS NOT NULL)
         AND NOT EXISTS (
           SELECT 1 FROM public.user_blocks ub
            WHERE (ub.blocker_id = v_viewer AND ub.blockee_id = v.user_id)
               OR (ub.blocker_id = v_user_id  AND ub.blockee_id = v_viewer)
         )
       )
     )
     AND (
       CASE WHEN p_friends_only
            THEN EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = v_viewer AND f.followee_id = v.user_id)
            ELSE TRUE
       END
     );

  -- Page (+1 to detect next page)
  WITH base AS (
    SELECT
      v.id,
      v.user_id,
      v.rating,
      v.created_at AS visited_at,
      u.handle     AS user_handle
    FROM public.visits v
    JOIN public.users  u ON u.id = v.user_id
    WHERE v.place_id = p_place_id
      AND (
        v.user_id = v_viewer
        OR (
          v.visibility = 'public'
          AND NOT EXISTS (SELECT 1 FROM public.users uu WHERE uu.id = v.user_id AND uu.deleted_at IS NOT NULL)
          AND NOT EXISTS (
            SELECT 1 FROM public.user_blocks ub
             WHERE (ub.blocker_id = v_viewer AND ub.blockee_id = v.user_id)
                OR (ub.blocker_id = v_user_id  AND ub.blockee_id = v_viewer)
          )
        )
        OR (
          v.visibility = 'friends'
          AND EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = v_viewer AND f.followee_id = v.user_id)
          AND NOT EXISTS (SELECT 1 FROM public.users uu WHERE uu.id = v.user_id AND uu.deleted_at IS NOT NULL)
          AND NOT EXISTS (
            SELECT 1 FROM public.user_blocks ub
             WHERE (ub.blocker_id = v_viewer AND ub.blockee_id = v.user_id)
                OR (ub.blocker_id = v_user_id  AND ub.blockee_id = v_viewer)
          )
        )
      )
      AND (
        CASE WHEN v_created_at IS NULL
             THEN TRUE
             ELSE (v.created_at, v.id) < (v_created_at, v_id)
        END
      )
      AND (
        CASE WHEN p_friends_only
             THEN EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = v_viewer AND f.followee_id = v.user_id)
             ELSE TRUE
        END
      )
    ORDER BY v.created_at DESC, v.id DESC
    LIMIT v_rows + 1
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(b) ORDER BY b.visited_at DESC, b.id DESC), '[]'::jsonb)
    INTO v_visits
    FROM base b;

  -- Trim to page size and compute next_cursor
  IF jsonb_array_length(v_visits) > v_rows THEN
    v_has_more := TRUE;
    v_visits := (
      SELECT jsonb_agg(elem)
      FROM jsonb_array_elements(v_visits) WITH ORDINALITY e(elem, ord)
      WHERE ord <= v_rows
    );
  END IF;

  IF jsonb_array_length(v_visits) > 0 THEN
    -- Inner block so we can DECLARE locals
    DECLARE
      last_row jsonb;
      last_ts  text;
      last_id  uuid;
    BEGIN
      last_row := v_visits -> (jsonb_array_length(v_visits) - 1);
      last_ts  := (last_row ->> 'visited_at');
      last_id  := (last_row ->> 'id')::uuid;
      v_next_cursor := encode(convert_to((last_ts || '|' || last_id::text), 'utf8'), 'base64');
    END;
  ELSE
    v_next_cursor := NULL;
  END IF;

  RETURN jsonb_build_object(
    'status',       200,
    'place',        jsonb_build_object('id', p_place_id),
    'visits',       v_visits,
    'visit_count',  v_visit_count,
    'next_cursor',  CASE WHEN v_has_more THEN v_next_cursor ELSE NULL END
  );
END;
$fn$;

-- Ensure callers can execute
GRANT EXECUTE ON FUNCTION public.fn_places_get_visits_v1(uuid, integer, text, boolean) TO authenticated;

-- Keyset indexes (idempotent)
CREATE INDEX IF NOT EXISTS visits_place_created_id_desc
  ON public.visits (place_id, created_at DESC, id DESC);
COMMENT ON INDEX visits_place_created_id_desc IS
  'Keyset pagination for place feeds (place_id, created_at desc, id desc).';

CREATE INDEX IF NOT EXISTS visits_user_created_id_desc
  ON public.visits (user_id,  created_at DESC, id DESC);
COMMENT ON INDEX visits_user_created_id_desc IS
  'Keyset pagination for user timelines (user_id, created_at desc, id desc).';

COMMIT;
