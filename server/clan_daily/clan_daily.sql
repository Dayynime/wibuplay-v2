-- =====================================================================
-- Daily Clan: absen harian anggota clan -> ZCoin (naik sesuai streak) +
-- bonus bareng kalau >= 50% anggota clan absen di hari yang sama.
--
-- Semua aturan & angka di sini (server). App hanya menekan tombol.
-- Hanya service_role (Edge Function `clan-daily`) yang boleh memanggil.
--
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres < clan_daily.sql
-- =====================================================================

create table if not exists public.clan_daily_checkins (
  firebase_uid   text        not null,
  day            date        not null,           -- tanggal WIB
  clan_id        uuid        not null,
  streak         integer     not null check (streak >= 1),
  reward         integer     not null check (reward > 0),
  bonus_claimed  boolean     not null default false,
  bonus_reward   integer     not null default 0,
  created_at     timestamptz not null default now(),
  -- SATU absen per AKUN per hari (bukan per clan): pindah clan tidak
  -- membuat absen dua kali, dan request bersamaan tetap cuma sekali.
  primary key (firebase_uid, day)
);
create index if not exists clan_daily_clan_day_idx on public.clan_daily_checkins (clan_id, day);

alter table public.clan_daily_checkins enable row level security;
revoke all on public.clan_daily_checkins from anon, authenticated;
grant all on public.clan_daily_checkins to service_role;

-- ---------------------------------------------------------------------
-- Pengaturan (ubah di sini kalau mau ganti angka)
-- ---------------------------------------------------------------------
create or replace function public._clan_daily_cfg()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'base', 5,              -- ZCoin hari ke-1
    'step', 5,              -- +5 tiap hari streak
    'max_days', 7,          -- mentok di hari ke-7 (35 ZCoin)
    'bonus', 10,            -- bonus bareng
    'bonus_pct', 50,        -- minimal % anggota yang absen
    'bonus_min_members', 3, -- clan minimal 3 anggota untuk bonus
    'min_account_days', 3   -- umur akun minimal (anti akun baru / bot)
  );
$$;

-- Tanggal & awal hari menurut WIB (jam server, bukan jam HP).
create or replace function public._clan_daily_today()
returns date
language sql
stable
as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

create or replace function public._clan_daily_day_start(p_day date)
returns timestamptz
language sql
immutable
as $$ select (p_day::timestamp at time zone 'Asia/Jakarta') $$;

-- ---------------------------------------------------------------------
-- Status untuk ditampilkan di app
-- ---------------------------------------------------------------------
create or replace function public.clan_daily_state(p_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg jsonb := public._clan_daily_cfg();
  v_day date := public._clan_daily_today();
  v_start timestamptz := public._clan_daily_day_start(public._clan_daily_today());
  m record;
  t record;
  v_prev int;
  v_next_streak int;
  v_eligible int := 0;
  v_checked int := 0;
  v_need int := 0;
begin
  select * into m from clan_members where firebase_uid = p_uid;
  if not found then
    return jsonb_build_object('member', false);
  end if;

  select * into t from clan_daily_checkins where firebase_uid = p_uid and day = v_day;
  select streak into v_prev from clan_daily_checkins where firebase_uid = p_uid and day = v_day - 1;
  v_next_streak := case when t.firebase_uid is not null then t.streak else coalesce(v_prev, 0) + 1 end;

  select count(*) into v_eligible
    from clan_members where clan_id = m.clan_id and joined_at < v_start;
  select count(*) into v_checked
    from clan_daily_checkins c
    join clan_members cm on cm.firebase_uid = c.firebase_uid and cm.clan_id = m.clan_id and cm.joined_at < v_start
   where c.clan_id = m.clan_id and c.day = v_day;
  v_need := ceil(v_eligible * (cfg->>'bonus_pct')::numeric / 100)::int;

  return jsonb_build_object(
    'member', true,
    'day', v_day,
    'joined_today', m.joined_at >= v_start,
    'checked_in', t.firebase_uid is not null,
    'streak', v_next_streak,
    'reward_today', case when t.firebase_uid is not null then t.reward
                         else ((cfg->>'base')::int + (least(v_next_streak, (cfg->>'max_days')::int) - 1) * (cfg->>'step')::int) end,
    'max_days', (cfg->>'max_days')::int,
    'base', (cfg->>'base')::int,
    'step', (cfg->>'step')::int,
    'bonus', (cfg->>'bonus')::int,
    'bonus_min_members', (cfg->>'bonus_min_members')::int,
    'eligible_members', v_eligible,
    'checked_members', v_checked,
    'needed_members', greatest(v_need, (cfg->>'bonus_min_members')::int),
    'bonus_claimed', coalesce(t.bonus_claimed, false),
    'bonus_ready', coalesce(
                     t.firebase_uid is not null and not coalesce(t.bonus_claimed, false)
                     and t.clan_id = m.clan_id
                     and v_eligible >= (cfg->>'bonus_min_members')::int
                     and v_checked >= v_need, false)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Absen. Return jsonb {ok, code, reward, streak, balance}
-- code: ok | not_member | joined_today | account_new | no_profile | banned | already
-- ---------------------------------------------------------------------
create or replace function public.clan_daily_checkin(p_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg jsonb := public._clan_daily_cfg();
  v_day date := public._clan_daily_today();
  v_start timestamptz := public._clan_daily_day_start(public._clan_daily_today());
  m record;
  v_created timestamptz;
  v_prev int;
  v_streak int;
  v_reward int;
  v_balance bigint;
begin
  if exists (select 1 from banned_accounts where firebase_uid = p_uid) then
    return jsonb_build_object('ok', false, 'code', 'banned');
  end if;

  select * into m from clan_members where firebase_uid = p_uid;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_member');
  end if;
  -- Harus sudah anggota sebelum hari ini dimulai (tutup trik join-absen-keluar).
  if m.joined_at >= v_start then
    return jsonb_build_object('ok', false, 'code', 'joined_today');
  end if;

  select created_at into v_created from chat_profiles where firebase_uid = p_uid;
  if v_created is null then
    return jsonb_build_object('ok', false, 'code', 'no_profile');
  end if;
  if v_created > now() - make_interval(days => (cfg->>'min_account_days')::int) then
    return jsonb_build_object('ok', false, 'code', 'account_new');
  end if;

  select streak into v_prev from clan_daily_checkins where firebase_uid = p_uid and day = v_day - 1;
  v_streak := coalesce(v_prev, 0) + 1;
  v_reward := (cfg->>'base')::int + (least(v_streak, (cfg->>'max_days')::int) - 1) * (cfg->>'step')::int;

  insert into clan_daily_checkins (firebase_uid, day, clan_id, streak, reward)
  values (p_uid, v_day, m.clan_id, v_streak, v_reward)
  on conflict (firebase_uid, day) do nothing;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'already');
  end if;

  v_balance := public.credit_coin(
    p_uid, v_reward, 'adjustment',
    'clan_daily:' || p_uid || ':' || v_day,
    jsonb_build_object('source', 'clan_daily', 'day', v_day, 'streak', v_streak, 'clan_id', m.clan_id)
  );

  return jsonb_build_object('ok', true, 'code', 'ok', 'reward', v_reward, 'streak', v_streak, 'balance', v_balance);
end;
$$;

-- ---------------------------------------------------------------------
-- Klaim bonus bareng. code: ok | not_checked | already | clan_changed |
--                           clan_small | not_enough | banned
-- ---------------------------------------------------------------------
create or replace function public.clan_daily_bonus(p_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg jsonb := public._clan_daily_cfg();
  v_day date := public._clan_daily_today();
  v_start timestamptz := public._clan_daily_day_start(public._clan_daily_today());
  t record;
  m record;
  v_eligible int;
  v_checked int;
  v_need int;
  v_bonus int := (cfg->>'bonus')::int;
  v_balance bigint;
begin
  if exists (select 1 from banned_accounts where firebase_uid = p_uid) then
    return jsonb_build_object('ok', false, 'code', 'banned');
  end if;

  -- Kunci baris absen hari ini: klaim bersamaan tetap cuma sekali.
  select * into t from clan_daily_checkins where firebase_uid = p_uid and day = v_day for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_checked');
  end if;
  if t.bonus_claimed then
    return jsonb_build_object('ok', false, 'code', 'already');
  end if;

  select * into m from clan_members where firebase_uid = p_uid;
  if not found or m.clan_id <> t.clan_id then
    return jsonb_build_object('ok', false, 'code', 'clan_changed');
  end if;

  -- Hanya anggota yang sudah bergabung SEBELUM hari ini yang dihitung,
  -- jadi kick/invite hari ini tidak bisa memanipulasi persentase.
  select count(*) into v_eligible
    from clan_members where clan_id = t.clan_id and joined_at < v_start;
  if v_eligible < (cfg->>'bonus_min_members')::int then
    return jsonb_build_object('ok', false, 'code', 'clan_small');
  end if;
  select count(*) into v_checked
    from clan_daily_checkins c
    join clan_members cm on cm.firebase_uid = c.firebase_uid and cm.clan_id = t.clan_id and cm.joined_at < v_start
   where c.clan_id = t.clan_id and c.day = v_day;
  v_need := ceil(v_eligible * (cfg->>'bonus_pct')::numeric / 100)::int;
  if v_checked < v_need then
    return jsonb_build_object('ok', false, 'code', 'not_enough', 'checked', v_checked, 'needed', v_need);
  end if;

  update clan_daily_checkins
     set bonus_claimed = true, bonus_reward = v_bonus
   where firebase_uid = p_uid and day = v_day;

  v_balance := public.credit_coin(
    p_uid, v_bonus, 'adjustment',
    'clan_daily_bonus:' || p_uid || ':' || v_day,
    jsonb_build_object('source', 'clan_daily_bonus', 'day', v_day, 'clan_id', t.clan_id)
  );

  return jsonb_build_object('ok', true, 'code', 'ok', 'bonus', v_bonus, 'balance', v_balance);
end;
$$;

revoke all on function public._clan_daily_cfg()             from public, anon, authenticated;
revoke all on function public._clan_daily_today()           from public, anon, authenticated;
revoke all on function public._clan_daily_day_start(date)   from public, anon, authenticated;
revoke all on function public.clan_daily_state(text)        from public, anon, authenticated;
revoke all on function public.clan_daily_checkin(text)      from public, anon, authenticated;
revoke all on function public.clan_daily_bonus(text)        from public, anon, authenticated;
grant execute on function public.clan_daily_state(text)     to service_role;
grant execute on function public.clan_daily_checkin(text)   to service_role;
grant execute on function public.clan_daily_bonus(text)     to service_role;
