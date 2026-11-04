-- =====================================================================
-- Pengaturan akses clan: mode join + level minimal + undangan.
--
--   join_mode: open      = langsung masuk tanpa persetujuan
--              approval  = request join, di-approve pengurus (perilaku lama, default)
--              invite    = hanya lewat undangan pengurus
--              closed    = tidak menerima anggota baru (undangan juga ditolak)
--   min_level: level XP minimal untuk join/request (undangan bebas level)
--
-- Edge Function lama (zenime-clan-join-request, -respond-request, -settings)
-- TIDAK diubah; aturan baru dipasang di dalam fungsi SQL submit_join_request
-- (signature & tipe return sama persis). Fitur baru lewat Edge Function
-- `clan-access`.
--
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres < clan_access.sql
-- =====================================================================

alter table public.clans
  add column if not exists join_mode text not null default 'approval',
  add column if not exists min_level integer not null default 1;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'clans_join_mode_valid') then
    alter table public.clans add constraint clans_join_mode_valid
      check (join_mode in ('open', 'approval', 'invite', 'closed'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'clans_min_level_range') then
    alter table public.clans add constraint clans_min_level_range
      check (min_level between 1 and 500);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- submit_join_request: versi baru (signature sama). Tambahan aturan:
-- mode closed/invite ditolak, level minimal dicek, mode open langsung masuk.
-- ---------------------------------------------------------------------
create or replace function public.submit_join_request(p_firebase_uid text, p_clan_id uuid)
returns public.clan_join_requests
language plpgsql
security definer
set search_path to 'public'
as $$
declare
    v_request public.clan_join_requests;
    v_clan public.clans;
    v_level int;
begin
    if exists (select 1 from clan_members where firebase_uid = p_firebase_uid) then
        raise exception 'Kamu udah gabung clan lain';
    end if;

    -- Kunci baris clan: mode open & cek kuota tidak balapan dengan join lain.
    select * into v_clan from clans where id = p_clan_id for update;
    if not found then
        raise exception 'Clan tidak ditemukan';
    end if;

    if v_clan.join_mode = 'closed' then
        raise exception 'Clan ini sedang tertutup, tidak menerima anggota baru';
    end if;
    if v_clan.join_mode = 'invite' then
        raise exception 'Clan ini hanya menerima anggota lewat undangan';
    end if;

    select level into v_level from user_xp where firebase_uid = p_firebase_uid;
    v_level := coalesce(v_level, 1);
    if v_level < v_clan.min_level then
        raise exception 'Butuh level % untuk bergabung (level kamu %)', v_clan.min_level, v_level;
    end if;

    if v_clan.member_count >= v_clan.member_limit then
        raise exception 'Clan udah penuh';
    end if;

    if v_clan.join_mode = 'open' then
        -- Langsung masuk. TIDAK membuat baris request (trigger request akan
        -- mengirim notif "ingin bergabung" ke pengurus padahal sudah masuk).
        insert into clan_members (clan_id, firebase_uid, role)
        values (p_clan_id, p_firebase_uid, 'member');
        update clans set member_count = member_count + 1, updated_at = now()
         where id = p_clan_id;
        -- Request pending lama dari user ini (kalau ada) ditutup.
        update clan_join_requests
           set status = 'accepted', resolved_at = now(), resolved_by = p_firebase_uid
         where firebase_uid = p_firebase_uid and status = 'pending';
        v_request := row(gen_random_uuid(), p_clan_id, p_firebase_uid, 'accepted',
                         now(), now(), p_firebase_uid)::public.clan_join_requests;
        return v_request;
    end if;

    insert into clan_join_requests (clan_id, firebase_uid)
    values (p_clan_id, p_firebase_uid)
    returning * into v_request;

    return v_request;
exception
    when unique_violation then
        if exists (select 1 from clan_members where firebase_uid = p_firebase_uid) then
            raise exception 'Kamu udah gabung clan lain';
        end if;
        raise exception 'Kamu udah punya request pending ke clan ini';
end;
$$;

-- ---------------------------------------------------------------------
-- Ubah mode join & level minimal (khusus leader, sama dengan pengaturan lain)
-- ---------------------------------------------------------------------
create or replace function public.update_clan_access(
  p_actor_uid text, p_clan_id uuid, p_join_mode text, p_min_level integer
)
returns public.clans
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_clan public.clans;
begin
  if not exists (select 1 from clans where id = p_clan_id and leader_uid = p_actor_uid) then
    raise exception 'Cuma leader clan yang bisa ubah settingan ini';
  end if;
  if p_join_mode is null or p_join_mode not in ('open', 'approval', 'invite', 'closed') then
    raise exception 'Mode join tidak valid';
  end if;
  if p_min_level is null or p_min_level < 1 or p_min_level > 500 then
    raise exception 'Level minimal harus 1 sampai 500';
  end if;

  update clans
     set join_mode = p_join_mode, min_level = p_min_level, updated_at = now()
   where id = p_clan_id
  returning * into v_clan;
  return v_clan;
end;
$$;

-- ---------------------------------------------------------------------
-- Undangan
-- ---------------------------------------------------------------------
create table if not exists public.clan_invites (
  id            uuid primary key default gen_random_uuid(),
  clan_id       uuid not null references public.clans(id) on delete cascade,
  from_uid      text not null,
  to_uid        text not null,
  status        text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz
);
-- Satu undangan pending per (clan, orang): undang berkali-kali tidak spam.
create unique index if not exists clan_invites_pending_uniq
  on public.clan_invites (clan_id, to_uid) where status = 'pending';
create index if not exists clan_invites_to_idx on public.clan_invites (to_uid, created_at desc);
create index if not exists clan_invites_from_idx on public.clan_invites (from_uid, created_at desc);

alter table public.clan_invites enable row level security;
revoke all on public.clan_invites from anon, authenticated;
grant all on public.clan_invites to service_role;

-- Undang [p_target] ke clan. Pengundang: pangkat >= 1 (sama dengan yang boleh
-- approve request). Return id undangan.
create or replace function public.clan_invite(p_actor_uid text, p_clan_id uuid, p_target_uid text)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'private'
as $$
declare
  v_role text;
  v_clan public.clans;
  v_id uuid;
begin
  if p_target_uid is null or p_target_uid = '' or p_target_uid = p_actor_uid then
    raise exception 'User tidak valid';
  end if;

  select role into v_role from clan_members where clan_id = p_clan_id and firebase_uid = p_actor_uid;
  if public.clan_role_rank(v_role) < 1 then
    raise exception 'Cuma pengurus clan yang bisa mengundang';
  end if;

  select * into v_clan from clans where id = p_clan_id;
  if not found then
    raise exception 'Clan tidak ditemukan';
  end if;
  if v_clan.join_mode = 'closed' then
    raise exception 'Clan sedang tertutup. Ubah mode join dulu untuk mengundang';
  end if;
  if v_clan.member_count >= v_clan.member_limit then
    raise exception 'Clan udah penuh';
  end if;
  if exists (select 1 from clan_members where firebase_uid = p_target_uid) then
    raise exception 'Dia sudah bergabung ke clan';
  end if;
  if exists (select 1 from banned_accounts where firebase_uid = p_target_uid) then
    raise exception 'User ini tidak bisa diundang';
  end if;
  -- Anti spam: maksimal 30 undangan per pengundang per 24 jam.
  if (select count(*) from clan_invites
       where from_uid = p_actor_uid and created_at > now() - interval '24 hours') >= 30 then
    raise exception 'Batas undangan hari ini sudah tercapai, coba lagi besok';
  end if;

  -- Undangan lama yang kedaluwarsa (> 7 hari) dibersihkan dulu.
  update clan_invites set status = 'expired', responded_at = now()
   where clan_id = p_clan_id and to_uid = p_target_uid and status = 'pending'
     and created_at < now() - interval '7 days';

  begin
    insert into clan_invites (clan_id, from_uid, to_uid)
    values (p_clan_id, p_actor_uid, p_target_uid)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Dia sudah diundang ke clan ini, tunggu jawabannya';
  end;

  perform private.push_notify(
    p_target_uid, p_actor_uid, 'clan_invite',
    'Undangan clan',
    private.display_name(p_actor_uid) || ' mengajak kamu bergabung ke ' || private.clan_label(p_clan_id::text),
    jsonb_build_object('invite_id', v_id::text, 'clan_id', p_clan_id::text, 'clan_name', v_clan.name));

  return v_id;
end;
$$;

-- Jawab undangan. accept = langsung masuk (bebas level minimal).
create or replace function public.clan_invite_respond(p_uid text, p_invite_id uuid, p_accept boolean)
returns uuid  -- clan_id
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_inv public.clan_invites;
  v_clan public.clans;
begin
  select * into v_inv from clan_invites where id = p_invite_id for update;
  if not found or v_inv.to_uid <> p_uid then
    raise exception 'Undangan tidak ditemukan';
  end if;

  -- Notif undangan ditandai dibaca & kedaluwarsa (tidak bisa dijawab ulang).
  update notifications
     set read_at = coalesce(read_at, now()), data = data || '{"expired": true}'::jsonb
   where type = 'clan_invite' and data->>'invite_id' = p_invite_id::text;

  if v_inv.status <> 'pending' then
    return null;  -- sudah dijawab / kedaluwarsa (Edge Function -> pesan jelas)
  end if;
  if v_inv.created_at < now() - interval '7 days' then
    update clan_invites set status = 'expired', responded_at = now() where id = p_invite_id;
    return null;
  end if;

  if not p_accept then
    update clan_invites set status = 'declined', responded_at = now() where id = p_invite_id;
    return v_inv.clan_id;
  end if;

  if exists (select 1 from clan_members where firebase_uid = p_uid) then
    raise exception 'Kamu udah gabung clan lain';
  end if;

  select * into v_clan from clans where id = v_inv.clan_id for update;
  if not found then
    raise exception 'Clan sudah tidak ada';
  end if;
  if v_clan.join_mode = 'closed' then
    raise exception 'Clan ini sedang tertutup';
  end if;
  if v_clan.member_count >= v_clan.member_limit then
    raise exception 'Clan udah penuh';
  end if;

  insert into clan_members (clan_id, firebase_uid, role) values (v_inv.clan_id, p_uid, 'member');
  update clans set member_count = member_count + 1, updated_at = now() where id = v_inv.clan_id;
  update clan_invites set status = 'accepted', responded_at = now() where id = p_invite_id;
  -- Undangan & request pending lain milik user ini ditutup.
  update clan_invites set status = 'expired', responded_at = now()
   where to_uid = p_uid and status = 'pending' and id <> p_invite_id;
  update clan_join_requests set status = 'accepted', resolved_at = now(), resolved_by = p_uid
   where firebase_uid = p_uid and status = 'pending' and clan_id = v_inv.clan_id;
  update clan_join_requests set status = 'rejected', resolved_at = now(), resolved_by = p_uid
   where firebase_uid = p_uid and status = 'pending';

  return v_inv.clan_id;
exception
  when unique_violation then
    raise exception 'Kamu udah gabung clan lain';
end;
$$;

-- Undangan yang masih menunggu jawaban user ini.
create or replace function public.clan_my_invites(p_uid text)
returns jsonb
language sql
security definer
set search_path to 'public', 'private'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'invite_id', i.id,
           'clan_id', i.clan_id,
           'clan_name', c.name,
           'clan_tag', c.tag,
           'photo_url', c.photo_url,
           'from_name', private.display_name(i.from_uid),
           'created_at', i.created_at
         ) order by i.created_at desc), '[]'::jsonb)
    from clan_invites i
    join clans c on c.id = i.clan_id
   where i.to_uid = p_uid and i.status = 'pending'
     and i.created_at > now() - interval '7 days';
$$;

revoke all on function public.update_clan_access(text, uuid, text, integer) from public, anon, authenticated;
revoke all on function public.clan_invite(text, uuid, text)                 from public, anon, authenticated;
revoke all on function public.clan_invite_respond(text, uuid, boolean)      from public, anon, authenticated;
revoke all on function public.clan_my_invites(text)                         from public, anon, authenticated;
grant execute on function public.update_clan_access(text, uuid, text, integer) to service_role;
grant execute on function public.clan_invite(text, uuid, text)                 to service_role;
grant execute on function public.clan_invite_respond(text, uuid, boolean)      to service_role;
grant execute on function public.clan_my_invites(text)                         to service_role;
