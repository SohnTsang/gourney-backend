-- 20250930_v1c_up.sql
-- Beli-like MVP (JP/SG/HK) — FULL UP migration with Week-1 hardening deltas
set search_path = public, extensions, gis;

set check_function_bodies = off;
set statement_timeout = 0;
set lock_timeout = 0;

-- ===================== EXTENSIONS =====================
create extension if not exists postgis;
create extension if not exists pg_trgm;
create extension if not exists pg_stat_statements;
create extension if not exists pgcrypto;  -- gen_random_uuid()

-- ===================== SCHEMAS & HELPERS =====================
create schema if not exists app;

-- Supabase auth uid() wrapper
create or replace function app.current_user_id()
returns uuid
language sql stable
as $$ select auth.uid() $$;

-- Is follower (viewer follows owner)?
create or replace function app.is_friend(viewer uuid, owner uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from public.follows f
    where f.follower_id = viewer and f.followee_id = owner
  )
$$;

-- Is either side blocking the other?
create or replace function app.is_blocked(a uuid, b uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from public.user_blocks ub
    where (ub.blocker_id = a and ub.blockee_id = b)
       or (ub.blocker_id = b and ub.blockee_id = a)
  )
$$;

-- Owner is visible to viewer (not deleted & not blocked)
create or replace function app.can_see_user(viewer uuid, owner uuid)
returns boolean language sql stable as $$
  select (u.deleted_at is null) and (not app.is_blocked(viewer, owner))
  from public.users u
  where u.id = owner
$$;

-- Reserved handles guard
create or replace function public.is_reserved_handle(h text)
returns boolean language sql immutable as $$
  select lower(h) in ('admin','root','system','support','help','moderator','beli','team','staff')
$$;

-- ===================== CORE TABLES =====================

-- USERS
create table if not exists public.users (
  id uuid primary key,                              -- == auth.uid()
  handle text not null unique,
  display_name text,
  avatar_url text,
  home_city text,
  locale text not null default 'ja-JP',
  script_preference text not null default 'auto',
  timezone text not null default 'Asia/Tokyo',
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.users
  add constraint users_handle_regex
    check (handle ~ '^[a-z0-9_]{3,20}$'),
  add constraint users_handle_not_reserved
    check (not public.is_reserved_handle(handle));

-- FOLLOWS
create table if not exists public.follows (
  follower_id uuid not null references public.users(id) on delete cascade,
  followee_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint follows_no_self check (follower_id <> followee_id)
);
create index if not exists idx_follows_follower on public.follows(follower_id);
create index if not exists idx_follows_followee on public.follows(followee_id);

-- USER BLOCKS
create table if not exists public.user_blocks (
  blocker_id uuid not null references public.users(id) on delete cascade,
  blockee_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blockee_id)
);

-- PLACES (JP-aware, slim but future-proof)
create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  provider text not null,                           -- 'apple'|'google'|'ugc'
  provider_place_id text unique,
  name_ja text,
  name_en text,
  name_zh text,
  postal_code text,
  prefecture_code text,
  prefecture_name text,
  ward text,
  city text,
  geom geography(Point,4326),
  lat double precision,
  lng double precision,
  price_level int,
  categories text[],                                -- multi-category
  attributes jsonb not null default '{}'::jsonb,    -- { takeout:true, raw_address:"", ... }
  search_tokens tsvector,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.places
  add constraint places_provider_valid
    check (provider in ('apple','google','ugc')),
  add constraint places_price_level_bounds
    check (price_level is null or price_level between 0 and 4);

-- search_tokens generator (names + city/ward; weights A/B/C)
create or replace function public.places_tsvector_update()
returns trigger language plpgsql as $$
begin
  new.search_tokens :=
      setweight(to_tsvector('simple', coalesce(new.name_ja,'')), 'A')
   || setweight(to_tsvector('simple', coalesce(new.name_en,'')), 'B')
   || setweight(to_tsvector('simple', coalesce(new.name_zh,'')), 'B')
   || setweight(to_tsvector('simple', coalesce(new.city,'')),   'C')
   || setweight(to_tsvector('simple', coalesce(new.ward,'')),   'C');
  return new;
end
$$;

create trigger trg_places_tsv
before insert or update on public.places
for each row execute procedure public.places_tsvector_update();

-- Indexes for places (search + geo)
create index if not exists idx_places_search_tokens on public.places using gin(search_tokens);
create index if not exists idx_places_trgm_ja on public.places using gin (name_ja gin_trgm_ops);
create index if not exists idx_places_trgm_en on public.places using gin (name_en gin_trgm_ops);
create index if not exists idx_places_trgm_zh on public.places using gin (name_zh gin_trgm_ops);
create index if not exists idx_places_geom on public.places using gist (geom);

-- PLACE HOURS (0 = Sunday .. 6 = Saturday)
create table if not exists public.place_hours (
  place_id uuid not null references public.places(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6), -- 0=Sun..6=Sat
  open_time time not null,
  close_time time not null,
  notes text,
  primary key (place_id, weekday)
);
comment on table public.place_hours is 'weekday: 0=Sunday .. 6=Saturday; handle overnight by open_time > close_time';

-- VISITS (inline rating & photos)
create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text check (char_length(comment) <= 1000),
  photo_urls text[] check (cardinality(photo_urls) <= 3),
  visibility text not null default 'friends',       -- 'public'|'friends'|'private'
  visited_at date,                                  -- client sets; fallback to created_at::date in app
  created_at timestamptz not null default now()
);
create index if not exists idx_visits_user_created on public.visits(user_id, created_at desc);
create index if not exists idx_visits_place_created on public.visits(place_id, created_at desc);
-- Stable pagination composite (created_at, id)
create index if not exists idx_visits_created_id on public.visits(created_at desc, id desc);

alter table public.visits
  add constraint visits_visibility_valid
    check (visibility in ('public','friends','private'));

-- LISTS
create table if not exists public.lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  visibility text not null default 'friends',       -- list-level
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.lists
  add constraint lists_visibility_valid
    check (visibility in ('public','friends','private'));

create table if not exists public.list_items (
  list_id uuid not null references public.lists(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  added_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (list_id, place_id)
);

-- ACTIVITY (on-read feed; subject_id is the main entity id)
create table if not exists public.activity (
  id bigserial primary key,
  type text not null,                               -- 'visit'|'follow'|'list_add'
  actor_id uuid not null references public.users(id) on delete cascade,
  subject_id uuid,                                  -- visit.id or place.id or user.id
  visibility text not null default 'public',
  created_at timestamptz not null default now()
);

alter table public.activity
  add constraint activity_type_valid
    check (type in ('visit','follow','list_add')),
  add constraint activity_visibility_valid
    check (visibility in ('public','friends','private'));

create index if not exists idx_activity_actor_created on public.activity(actor_id, created_at desc);
create index if not exists idx_activity_created on public.activity(created_at desc);
-- Stable pagination composite (created_at, id)
create index if not exists idx_activity_created_id on public.activity(created_at desc, id desc);

-- LEADERBOARD
create table if not exists public.city_scores (
  user_id uuid not null references public.users(id) on delete cascade,
  city text not null,
  week_start_date date not null,
  weekly_points int not null default 0,
  lifetime_points int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, city, week_start_date)
);
create index if not exists idx_city_scores_rank on public.city_scores(city, week_start_date, weekly_points desc);

-- REPORTS (moderation)
create table if not exists public.reports (
  id bigserial primary key,
  reporter_id uuid not null references public.users(id) on delete cascade,
  target_type text not null,         -- 'visit'|'list'|'user'
  target_id uuid not null,
  reporter_comment text,
  screenshot_url text,
  status text not null default 'open',
  created_at timestamptz not null default now()
);

-- DEVICES (push)
create table if not exists public.devices (
  user_id uuid not null references public.users(id) on delete cascade,
  apns_token text not null,
  locale text,
  tz text,
  env text not null default 'prod',                 -- 'dev'|'prod'
  quiet_hours jsonb not null default jsonb_build_object('start','23:00','end','07:00'),
  last_active timestamptz not null default now(),
  primary key (user_id, apns_token),
  constraint devices_env_valid check (env in ('dev','prod'))
);

-- PUSH QUEUE (server-only)
create table if not exists public.push_queue (
  id bigserial primary key,
  user_id uuid not null references public.users(id) on delete cascade, -- recipient
  type text not null,                               -- 'new_follower'|'friend_visit'
  payload jsonb not null,
  deliver_after timestamptz not null default now(),
  tries smallint not null default 0,
  status text not null default 'queued',            -- 'queued'|'sent'|'failed'|'skipped'
  created_at timestamptz not null default now(),
  constraint push_type_valid check (type in ('new_follower','friend_visit')),
  constraint push_status_valid check (status in ('queued','sent','failed','skipped'))
);
create index if not exists idx_push_queue_due on public.push_queue(status, deliver_after);

-- REMOTE CONFIG
create table if not exists public.remote_config (
  key text primary key,
  value jsonb not null
);

-- ADMIN AUDIT (server-only)
create table if not exists public.admin_audit (
  id bigserial primary key,
  admin_user uuid,
  action text not null,           -- 'impersonate', 'moderate', ...
  details jsonb,
  created_at timestamptz not null default now()
);

-- CITY → TIMEZONE cache (used by Edge localNow)
create table if not exists public.city_timezones (
  city text primary key,
  tz text not null
);

-- ===================== SEEDS =====================
insert into public.remote_config(key, value) values
  ('push_friend_visit',   '{"enabled": true}'),
  ('rate_limits_on',      '{"enabled": true, "limits": {"visits_per_day": 30, "list_add_per_day": 100, "follow_per_day": 200}}'),
  ('auto_hide_threshold', '{"count": 3, "window_hours": 24}'),
  ('enable_open_now_beta','{"enabled": true}')
on conflict (key) do nothing;

insert into public.city_timezones(city, tz) values
  ('Tokyo',        'Asia/Tokyo'),
  ('Osaka',        'Asia/Tokyo'),
  ('Singapore',    'Asia/Singapore'),
  ('Hong_Kong',    'Asia/Hong_Kong')
on conflict (city) do nothing;

-- ===================== VIEWS =====================
create or replace view public.v_activity_visit as
select
  a.id          as activity_id,
  a.actor_id,
  a.created_at,
  a.visibility,
  v.id          as visit_id,
  v.place_id,
  v.rating
from public.activity a
join public.visits v
  on a.type = 'visit' and a.subject_id = v.id;

-- ===================== RLS (ENFORCING) =====================

-- USERS: hide deleted users globally; allow owner-only updates
alter table public.users enable row level security;
alter table public.users force row level security;

drop policy if exists users_select_policy on public.users;
create policy users_select_policy on public.users
for select using (deleted_at is null);

drop policy if exists users_update_own on public.users;
create policy users_update_own on public.users
for update using (id = app.current_user_id())
with check (id = app.current_user_id());

-- VISITS
alter table public.visits enable row level security;
alter table public.visits force row level security;

drop policy if exists visits_select_policy on public.visits;
create policy visits_select_policy on public.visits
for select using (
  (
    user_id = app.current_user_id()
    or visibility = 'public'
    or (visibility = 'friends' and app.is_friend(app.current_user_id(), user_id))
  )
  and app.can_see_user(app.current_user_id(), user_id)  -- not blocked & owner not deleted
);

drop policy if exists visits_write_policy on public.visits;
create policy visits_write_policy on public.visits
for all using (user_id = app.current_user_id())
with check (user_id = app.current_user_id());

-- LISTS
alter table public.lists enable row level security;
alter table public.lists force row level security;

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

drop policy if exists lists_write_policy on public.lists;
create policy lists_write_policy on public.lists
for all using (user_id = app.current_user_id())
with check (user_id = app.current_user_id());

-- LIST_ITEMS
alter table public.list_items enable row level security;
alter table public.list_items force row level security;

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

drop policy if exists list_items_write_policy on public.list_items;
create policy list_items_write_policy on public.list_items
for all using (
  exists (
    select 1 from public.lists l
    where l.id = list_id and l.user_id = app.current_user_id()
  )
)
with check (
  exists (
    select 1 from public.lists l
    where l.id = list_id and l.user_id = app.current_user_id()
  )
);

-- ACTIVITY
alter table public.activity enable row level security;
alter table public.activity force row level security;

drop policy if exists activity_select_policy on public.activity;
create policy activity_select_policy on public.activity
for select using (
  (
    actor_id = app.current_user_id()
    or visibility = 'public'
    or (visibility = 'friends' and app.is_friend(app.current_user_id(), actor_id))
  )
  and app.can_see_user(app.current_user_id(), actor_id)
);

-- DEVICES: owner-only read/write
alter table public.devices enable row level security;
alter table public.devices force row level security;

drop policy if exists devices_select_own on public.devices;
create policy devices_select_own on public.devices
for select using (user_id = app.current_user_id());

drop policy if exists devices_write_own on public.devices;
create policy devices_write_own on public.devices
for all using (user_id = app.current_user_id())
with check (user_id = app.current_user_id());

-- PUSH QUEUE & ADMIN AUDIT: server-only (RLS on, no client policies)
alter table public.push_queue enable row level security;
alter table public.push_queue force row level security;

alter table public.admin_audit enable row level security;
alter table public.admin_audit force row level security;

-- ===================== STORAGE (user-photos) RLS =====================
-- Bucket should exist in Supabase Console: name = 'user-photos' (public read, no public write)

-- NOTE: RLS is already enforced on storage.objects by Supabase.

-- Ensure RLS on storage.objects
-- alter table if exists storage.objects enable row level security;

-- Public READ only for 'user-photos' bucket
drop policy if exists "Public read user-photos" on storage.objects;
create policy "Public read user-photos"
on storage.objects for select
using (bucket_id = 'user-photos');

-- Owner-only INSERT into own folder "<uid>/..."
drop policy if exists "Users can upload to their folder" on storage.objects;
create policy "Users can upload to their folder"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'user-photos'
  and split_part(name, '/', 1) = app.current_user_id()::text
);

-- Owner-only UPDATE within own folder
drop policy if exists "Users can update files in their folder" on storage.objects;
create policy "Users can update files in their folder"
on storage.objects for update
to authenticated
using (
  bucket_id = 'user-photos'
  and split_part(name, '/', 1) = app.current_user_id()::text
)
with check (
  bucket_id = 'user-photos'
  and split_part(name, '/', 1) = app.current_user_id()::text
);

-- Owner-only DELETE within own folder
drop policy if exists "Users can delete files in their folder" on storage.objects;
create policy "Users can delete files in their folder"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'user-photos'
  and split_part(name, '/', 1) = app.current_user_id()::text
);

-- ===================== DONE =====================
