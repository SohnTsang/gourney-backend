-- 20251001115226_fix_can_see_user_down.sql
-- Rollback: Revert can_see_user to original version and restore original policies

-- Revert can_see_user to original (weaker) version
create or replace function app.can_see_user(viewer uuid, owner uuid)
returns boolean language sql stable as $$
  select (u.deleted_at is null) and (not app.is_blocked(viewer, owner))
  from public.users u
  where u.id = owner
$$;

-- Revert visits policy to original version
drop policy if exists visits_select_policy on public.visits;
create policy visits_select_policy on public.visits
for select using (
  (
    user_id = app.current_user_id()
    or visibility = 'public'
    or (visibility = 'friends' and app.is_friend(app.current_user_id(), user_id))
  )
  and app.can_see_user(app.current_user_id(), user_id)
);

-- Revert lists policy to original version
drop policy if exists lists_select_policy on public.lists;
create policy lists_select_policy on public.lists
for select using (
  (
    user_id = app.current_user_id()
    or visibility = 'public'
    or (visibility = 'friends' and app.is_friend(app.current_user_id(), user_id))
  )
  and app.can_see_user(app.current_user_id(), user_id)
);

-- Revert list_items policy to original version
drop policy if exists list_items_select_policy on public.list_items;
create policy list_items_select_policy on public.list_items
for select using (
  exists (
    select 1
    from public.lists l
    where l.id = list_id
      and (
        l.user_id = app.current_user_id()
        or l.visibility = 'public'
        or (l.visibility = 'friends' and app.is_friend(app.current_user_id(), l.user_id))
      )
      and app.can_see_user(app.current_user_id(), l.user_id)
  )
);

-- Permissions already granted, no need to revoke