-- 20251011_add_visits_keyset_indexes.sql
-- Phase: Week-1 "Stable cursors on hot paths"

-- Place feed: WHERE place_id = ? ORDER BY created_at DESC, id DESC
create index if not exists visits_place_created_id_desc
  on public.visits (place_id, created_at desc, id desc);

comment on index visits_place_created_id_desc is
  'Keyset pagination for place feeds: (place_id, created_at desc, id desc).';

-- User timeline (optional but recommended): WHERE user_id = ? ORDER BY created_at DESC, id DESC
create index if not exists visits_user_created_id_desc
  on public.visits (user_id, created_at desc, id desc);

comment on index visits_user_created_id_desc is
  'Keyset pagination for user timelines: (user_id, created_at desc, id desc).';

-- Down (manual, only if ever needed)
-- drop index if exists visits_place_created_id_desc;
-- drop index if exists visits_user_created_id_desc;
