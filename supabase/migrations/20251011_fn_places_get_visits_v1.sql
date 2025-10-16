-- Function: public.fn_places_get_visits_v1
-- Returns a single JSON payload so the Edge Function stays thin.
-- Assumes helper funcs exist: app.current_user_id(), app.is_friend(a,b), app.is_blocked(a,b), app.can_see_user(a,b)

create or replace function public.fn_places_get_visits_v1(
  p_place_id uuid,
  p_limit int default 20,
  p_cursor text default null,
  p_friends_only boolean default false
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user uuid := app.current_user_id();
  v_place record;
  v_created_at timestamptz;
  v_id uuid;
  v_rows int := greatest(1, least(coalesce(p_limit, 20), 50)); -- clamp 1..50
  v_has_more boolean := false;
  v_next_cursor text := null;
  v_visit_count bigint := 0;
  v_visits jsonb := '[]'::jsonb;
begin
  -- place existence check (readable under RLS)
  select id, name
    into v_place
    from public.places
   where id = p_place_id
   limit 1;

  if not found then
    return jsonb_build_object(
      'status', 404,
      'error', 'place_not_found'
    );
  end if;

  -- decode cursor if present: base64("created_at|id")
  if p_cursor is not null then
    begin
      select
        (split_part(convert_from(decode(p_cursor, 'base64'), 'utf8'), '|', 1))::timestamptz,
        (split_part(convert_from(decode(p_cursor, 'base64'), 'utf8'), '|', 2))::uuid
      into v_created_at, v_id;
    exception when others then
      v_created_at := null;
      v_id := null;
    end;
  end if;

  -- Count with same filters
  select count(*)
    into v_visit_count
    from public.visits v
    where v.place_id = p_place_id
      and (not app.is_blocked(v_user, v.user_id))
      and app.can_see_user(v_user, v.user_id)
      and (case when p_friends_only then app.is_friend(v_user, v.user_id) else true end);

  -- Page fetch (+1 to detect next page)
  with base as (
    select
      v.id,
      v.user_id,
      v.rating,
      v.created_at as visited_at,
      u.handle as user_handle
    from public.visits v
    join public.users u on u.id = v.user_id
    where v.place_id = p_place_id
      and (not app.is_blocked(v_user, v.user_id))
      and app.can_see_user(v_user, v.user_id)
      and (case when p_friends_only then app.is_friend(v_user, v.user_id) else true end)
      and (
        -- keyset: only apply when cursor present
        case
          when v_created_at is null then true
          else (v.created_at, v.id) < (v_created_at, v_id)
        end
      )
    order by v.created_at desc, v.id desc
    limit v_rows + 1
  )
  select coalesce(jsonb_agg(to_jsonb(b) order by b.visited_at desc, b.id desc), '[]'::jsonb)
    into v_visits
    from base b;

  -- has_more and next_cursor
  if jsonb_array_length(v_visits) > v_rows then
    v_has_more := true;
    -- pop last element
    v_visits := (select jsonb_agg(elem) from jsonb_array_elements(v_visits) with ordinality e(elem, ord)
                 where ord <= v_rows);

    -- last row for next cursor
    select to_char((v_visits -> (jsonb_array_length(v_visits)-1)) ->> 'visited_at', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    into strict v_next_cursor; -- temp dummy to force not null; we'll recompute properly below
  end if;

  if jsonb_array_length(v_visits) > 0 then
    -- compute next_cursor from last element
    declare
      last jsonb;
      last_ts text;
      last_id uuid;
    begin
      last := v_visits -> (jsonb_array_length(v_visits)-1);
      last_ts := (last ->> 'visited_at');
      last_id := (last ->> 'id')::uuid;
      v_next_cursor := encode(convert_to((last_ts || '|' || last_id::text), 'utf8'), 'base64');
    end;
  else
    v_next_cursor := null;
  end if;

  return jsonb_build_object(
    'status', 200,
    'place', jsonb_build_object('id', v_place.id, 'name', v_place.name),
    'visits', v_visits,
    'visit_count', v_visit_count,
    'next_cursor', case when v_has_more then v_next_cursor else null end
  );
end
$$;

-- Optional: permissions; rpc runs under RLS with caller's JWT via PostgREST.
-- Make sure authenticated can execute:
grant execute on function public.fn_places_get_visits_v1(uuid, int, text, boolean) to authenticated;
