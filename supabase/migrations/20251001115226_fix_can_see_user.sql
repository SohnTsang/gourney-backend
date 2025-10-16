-- PATCH: tighten app.can_see_user AND fix visits/lists policies

-- Safer boolean: returns FALSE unless owner exists, isn't deleted, isn't blocking/blocked,
-- and viewer is either the owner or a friend of the owner.
create or replace function app.can_see_user(viewer uuid, owner uuid)
returns boolean
language sql
stable
as $$
  select coalesce(
    exists (
      select 1
      from public.users u
      where u.id = owner
        and u.deleted_at is null
        and not app.is_blocked(viewer, owner)
        and (
          viewer = owner
          or app.is_friend(viewer, owner)
        )
    ),
    false
  )
$$;

-- Fix visits policy to delegate to app.can_see_user
drop policy if exists visits_select_policy on public.visits;
create policy visits_select_policy on public.visits
for select using (
  user_id = app.current_user_id()
  or (visibility = 'public' and app.can_see_user(app.current_user_id(), user_id))
  or (visibility = 'friends' and app.can_see_user(app.current_user_id(), user_id))
);

-- Fix lists policy
drop policy if exists lists_select_policy on public.lists;
create policy lists_select_policy on public.lists
for select using (
  user_id = app.current_user_id()
  or (visibility = 'public' and app.can_see_user(app.current_user_id(), user_id))
  or (visibility = 'friends' and app.can_see_user(app.current_user_id(), user_id))
);

-- Fix list_items policy
drop policy if exists list_items_select_policy on public.list_items;
create policy list_items_select_policy on public.list_items
for select using (
  exists (
    select 1 from public.lists l
    where l.id = list_id
      and (
        l.user_id = app.current_user_id()
        or (l.visibility = 'public' and app.can_see_user(app.current_user_id(), l.user_id))
        or (l.visibility = 'friends' and app.can_see_user(app.current_user_id(), l.user_id))
      )
  )
);

-- Make sure normal app roles can call the function
grant usage on schema app to authenticated, anon;
grant execute on function app.can_see_user(uuid, uuid) to authenticated, anon;
