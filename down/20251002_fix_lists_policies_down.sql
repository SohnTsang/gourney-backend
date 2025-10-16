-- 20251002_fix_lists_policies_down.sql
-- Rollback: Revert to the version from 20251001115226_fix_can_see_user

-- Note: This migration only updated can_see_user (removing friendship requirement)
-- To rollback, we restore the stricter version from the previous migration

-- Revert can_see_user to stricter version (requires friendship)
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

-- Policies remain the same as 20251002 migration
-- (they were already fixed in that migration, no rollback needed for policies)
-- The main change in 20251002 was the can_see_user function logic

-- Revoke permissions if needed (though they should already be granted)
-- No action needed - permissions remain