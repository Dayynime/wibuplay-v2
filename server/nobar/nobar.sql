-- =====================================================================
-- Nobar (nonton bareng) + voice chat, maksimal 5 orang per room.
-- Jalankan sekali di VPS:
--   docker exec -i supabase-db psql -U postgres < nobar.sql
-- Semua tabel TANPA policy RLS: hanya Edge Function `nobar-room`
-- (service role) yang boleh baca/tulis. App tidak menyentuh tabel ini.
-- =====================================================================

create table if not exists public.nobar_rooms (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,
  host_uid     text not null,
  movie_id     text not null,
  movie_title  text,
  poster_url   text,
  episode_id   text not null,
  position_ms  integer not null default 0,
  playing      boolean not null default false,
  state_at     timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  closed_at    timestamptz
);

create table if not exists public.nobar_members (
  room_id       uuid not null references public.nobar_rooms(id) on delete cascade,
  firebase_uid  text not null,
  joined_at     timestamptz not null default now(),
  last_seen     timestamptz not null default now(),
  primary key (room_id, firebase_uid)
);
create index if not exists nobar_members_uid_idx on public.nobar_members (firebase_uid);

-- User yang dikeluarkan host tidak bisa masuk lagi ke room yang sama.
create table if not exists public.nobar_bans (
  room_id       uuid not null references public.nobar_rooms(id) on delete cascade,
  firebase_uid  text not null,
  created_at    timestamptz not null default now(),
  primary key (room_id, firebase_uid)
);

alter table public.nobar_rooms   enable row level security;
alter table public.nobar_members enable row level security;
alter table public.nobar_bans    enable row level security;
revoke all on public.nobar_rooms, public.nobar_members, public.nobar_bans from anon, authenticated;

-- ---------------------------------------------------------------------
-- Host pindah otomatis kalau host keluar / tidak aktif > 90 detik
-- (aplikasinya mati, sinyal hilang). Room ditutup kalau sudah kosong.
-- Return true kalau host berganti atau room ditutup.
-- ---------------------------------------------------------------------
create or replace function public._nobar_fix_host(p_room uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_host text;
  v_new  text;
begin
  -- Anggota yang hilang > 3 menit dianggap sudah keluar.
  delete from nobar_members
   where room_id = p_room and last_seen < now() - interval '3 minutes';

  if not exists (select 1 from nobar_members where room_id = p_room) then
    update nobar_rooms set closed_at = now() where id = p_room and closed_at is null;
    return true;
  end if;

  select host_uid into v_host from nobar_rooms where id = p_room;
  if exists (
    select 1 from nobar_members
     where room_id = p_room and firebase_uid = v_host
       and last_seen > now() - interval '90 seconds'
  ) then
    return false;
  end if;

  select firebase_uid into v_new
    from nobar_members
   where room_id = p_room and last_seen > now() - interval '90 seconds'
   order by joined_at asc
   limit 1;
  if v_new is null or v_new = v_host then
    return false;
  end if;
  update nobar_rooms set host_uid = v_new where id = p_room;
  return true;
end;
$$;

-- Tandai user masih aktif. Return: 'ok' | 'ok_changed' | 'closed' | 'not_member'
create or replace function public.nobar_touch(p_room uuid, p_uid text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_closed timestamptz;
  v_changed boolean;
begin
  select closed_at into v_closed from nobar_rooms where id = p_room for update;
  if not found or v_closed is not null then return 'closed'; end if;
  update nobar_members set last_seen = now()
   where room_id = p_room and firebase_uid = p_uid;
  if not found then return 'not_member'; end if;
  v_changed := _nobar_fix_host(p_room);
  return case when v_changed then 'ok_changed' else 'ok' end;
end;
$$;

-- Masuk room secara atomik (kapasitas dicek di dalam lock baris room).
-- Return: 'ok' | 'closed' | 'banned' | 'full'
create or replace function public.nobar_join(p_room uuid, p_uid text, p_max integer)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_closed timestamptz;
begin
  select closed_at into v_closed from nobar_rooms where id = p_room for update;
  if not found or v_closed is not null then return 'closed'; end if;
  if exists (select 1 from nobar_bans where room_id = p_room and firebase_uid = p_uid) then
    return 'banned';
  end if;
  update nobar_members set last_seen = now()
   where room_id = p_room and firebase_uid = p_uid;
  if found then return 'ok'; end if;

  delete from nobar_members
   where room_id = p_room and last_seen < now() - interval '3 minutes';
  if (select count(*) from nobar_members where room_id = p_room) >= p_max then
    return 'full';
  end if;
  insert into nobar_members (room_id, firebase_uid) values (p_room, p_uid);
  return 'ok';
end;
$$;

-- Keluar dari room. Return true kalau host berganti / room ditutup.
create or replace function public.nobar_leave(p_room uuid, p_uid text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform 1 from nobar_rooms where id = p_room for update;
  if not found then return false; end if;
  delete from nobar_members where room_id = p_room and firebase_uid = p_uid;
  return _nobar_fix_host(p_room);
end;
$$;

revoke all on function public._nobar_fix_host(uuid)            from public, anon, authenticated;
revoke all on function public.nobar_touch(uuid, text)          from public, anon, authenticated;
revoke all on function public.nobar_join(uuid, text, integer)  from public, anon, authenticated;
revoke all on function public.nobar_leave(uuid, text)          from public, anon, authenticated;
grant execute on function public.nobar_touch(uuid, text)         to service_role;
grant execute on function public.nobar_join(uuid, text, integer) to service_role;
grant execute on function public.nobar_leave(uuid, text)         to service_role;
grant all on public.nobar_rooms, public.nobar_members, public.nobar_bans to service_role;
