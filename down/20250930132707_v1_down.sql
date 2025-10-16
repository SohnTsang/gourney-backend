-- 20250930_v1c_down.sql
-- Beli-like MVP — FULL DOWN migration (clean reverse order)

-- STORAGE policies
drop policy if exists "Users can delete files in their folder" on storage.objects;
drop policy if exists "Users can update files in their folder" on storage.objects;
drop policy if exists "Users can upload to their folder" on storage.objects;
drop policy if exists "Public read user-photos" on storage.objects;
-- (Keep storage.objects table and RLS as Supabase-managed)

-- VIEWS
drop view if exists public.v_activity_visit;

-- RLS policies (table order doesn’t matter once names are explicit)
drop policy if exists devices_write_own         on public.devices;
drop policy if exists devices_select_own        on public.devices;

drop policy if exists activity_select_policy    on public.activity;
drop policy if exists list_items_write_policy   on public.list_items;
drop policy if exists list_items_select_policy  on public.list_items;
drop policy if exists lists_write_policy        on public.lists;
drop policy if exists lists_select_policy       on public.lists;
drop policy if exists visits_write_policy       on public.visits;
drop policy if exists visits_select_policy      on public.visits;

drop policy if exists users_update_own          on public.users;
drop policy if exists users_select_policy       on public.users;

-- Disable FORCE RLS & RLS (optional)
alter table if exists public.push_queue   no force row level security;
alter table if exists public.admin_audit  no force row level security;
alter table if exists public.devices      no force row level security;
alter table if exists public.activity     no force row level security;
alter table if exists public.list_items   no force row level security;
alter table if exists public.lists        no force row level security;
alter table if exists public.visits       no force row level security;
alter table if exists public.users        no force row level security;

alter table if exists public.push_queue   disable row level security;
alter table if exists public.admin_audit  disable row level security;
alter table if exists public.devices      disable row level security;
alter table if exists public.activity     disable row level security;
alter table if exists public.list_items   disable row level security;
alter table if exists public.lists        disable row level security;
alter table if exists public.visits       disable row level security;
alter table if exists public.users        disable row level security;

-- Triggers & helper functions related to places search
drop trigger  if exists trg_places_tsv on public.places;
drop function if exists public.places_tsvector_update();

-- Helper functions & schema
drop function if exists app.can_see_user(uuid, uuid);
drop function if exists app.is_blocked(uuid, uuid);
drop function if exists app.is_friend(uuid, uuid);
drop function if exists app.current_user_id();
drop schema  if exists app cascade;

drop function if exists public.is_reserved_handle(text);

-- Tables (children first to satisfy FKs)
drop table if exists public.admin_audit;
drop table if exists public.remote_config;
drop table if exists public.push_queue;
drop table if exists public.devices;
drop table if exists public.reports;
drop table if exists public.city_scores;
drop table if exists public.activity;
drop table if exists public.list_items;
drop table if exists public.lists;
drop table if exists public.visits;
drop table if exists public.place_hours;
drop table if exists public.places;
drop table if exists public.user_blocks;
drop table if exists public.follows;
drop table if exists public.city_timezones;
drop table if exists public.users;

-- (Extensions usually kept; uncomment if you truly want to remove)
-- drop extension if exists pgcrypto;
-- drop extension if exists pg_stat_statements;
-- drop extension if exists pg_trgm;
-- drop extension if exists postgis;

-- DONE
