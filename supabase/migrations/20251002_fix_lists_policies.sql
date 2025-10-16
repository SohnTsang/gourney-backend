-- 20251002_fix_lists_policies.sql
-- Patch to enforce block-aware visibility on lists and list_items

-- Ensure can_see_user is the strict version
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

-- 🔒 Fix lists SELECT policy
drop policy if exists lists_select_policy on public.lists;
create policy lists_select_policy on public.lists
for select using (
  user_id = app.current_user_id()
  or (visibility = 'public' and app.can_see_user(app.current_user_id(), user_id))
  or (visibility = 'friends' and app.can_see_user(app.current_user_id(), user_id))
);

-- 🔒 Keep lists WRITE policy (owner-only)
drop policy if exists lists_write_policy on public.lists;
create policy lists_write_policy on public.lists
for all using (
  user_id = app.current_user_id()
);

-- 🔒 Fix list_items SELECT policy
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

-- 🔒 Keep list_items WRITE policy (owner-only, via parent list)
drop policy if exists list_items_write_policy on public.list_items;
create policy list_items_write_policy on public.list_items
for all using (
  exists (
    select 1 from public.lists l
    where l.id = list_id
      and l.user_id = app.current_user_id()
  )
);

-- Make sure normal roles can call helper
grant usage on schema app to authenticated, anon;
grant execute on function app.can_see_user(uuid, uuid) to authenticated, anon;
