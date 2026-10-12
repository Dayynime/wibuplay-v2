-- =====================================================================
-- POHON ZCOIN (mini game idle) — Wibuplay / Zenime
-- Jalankan sekali di SQL Editor Supabase (aman dijalankan ulang).
--
-- Prinsip keamanan:
--   * Semua tabel RLS ON tanpa policy + revoke anon/authenticated
--     -> client TIDAK bisa baca/tulis langsung.
--   * Semua fungsi cuma bisa dieksekusi service_role (Edge Function
--     `tree-game`), yang mengambil firebase_uid dari Firebase ID Token.
--   * Buah dihitung pakai JAM SERVER (now()), jam HP tidak dipakai.
-- =====================================================================

-- ---------- Konfigurasi (ubah angka di sini kapan saja, tanpa redeploy) ----------
create table if not exists public.tree_config (
  id                     int primary key default 1 check (id = 1),
  base_interval_min      int     not null default 120,  -- Lv.1: 1 buah tiap 120 menit
  interval_step_min      int     not null default 10,   -- tiap naik level, 10 menit lebih cepat
  min_interval_min       int     not null default 60,   -- paling cepat 1 buah / 60 menit
  base_capacity          int     not null default 6,    -- Lv.1 maksimal 6 buah di pohon
  max_level              int     not null default 10,
  upgrade_cost_per_level int     not null default 100,  -- biaya Lv.N -> N+1 = 100 * N ZCoin
  premium_speed          numeric not null default 1.5,  -- Premium tumbuh 1.5x lebih cepat
  daily_coin_cap         int     not null default 50,   -- maksimal ZCoin dari pohon per hari (WIB)
  water_bonus_min        int     not null default 30,   -- 1x siram = buah tumbuh 30 menit lebih cepat
  water_give_per_day     int     not null default 5,    -- user boleh nyiram maks 5x per hari
  water_receive_per_day  int     not null default 5     -- 1 pohon maks disiram 5x per hari
);
insert into public.tree_config (id) values (1) on conflict (id) do nothing;

-- ---------- State pohon per user ----------
create table if not exists public.tree_state (
  firebase_uid  text primary key,
  level         int         not null default 1,
  fruits        int         not null default 0,
  grow_anchor   timestamptz not null default now(),  -- awal pertumbuhan buah berikutnya
  coins_day     date        not null default ((now() at time zone 'Asia/Jakarta')::date),
  coins_today   int         not null default 0,
  total_fruits  bigint      not null default 0,
  total_coins   bigint      not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------- Log siram ----------
create table if not exists public.tree_water_log (
  id           bigserial primary key,
  giver_uid    text not null,
  receiver_uid text not null,
  day          date not null,
  created_at   timestamptz not null default now(),
  unique (giver_uid, receiver_uid, day)
);
create index if not exists tree_water_log_receiver_day on public.tree_water_log (receiver_uid, day);
create index if not exists tree_water_log_giver_day    on public.tree_water_log (giver_uid, day);

-- ---------- Log ZCoin dari/ke pohon (audit) ----------
create table if not exists public.tree_coin_log (
  id           bigserial primary key,
  firebase_uid text not null,
  kind         text not null check (kind in ('harvest', 'upgrade')),
  amount       int  not null,
  detail       jsonb,
  created_at   timestamptz not null default now()
);
create index if not exists tree_coin_log_uid_time on public.tree_coin_log (firebase_uid, created_at desc);

-- ---------- Kunci akses langsung ----------
alter table public.tree_config    enable row level security;
alter table public.tree_state     enable row level security;
alter table public.tree_water_log enable row level security;
alter table public.tree_coin_log  enable row level security;

revoke all on table public.tree_config, public.tree_state, public.tree_water_log, public.tree_coin_log
  from public, anon, authenticated;
revoke all on sequence public.tree_water_log_id_seq, public.tree_coin_log_id_seq
  from public, anon, authenticated;

-- =====================================================================
-- Helper internal
-- =====================================================================

create or replace function public._tree_today()
returns date
language sql stable
set search_path = public
as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

-- Statistik pohon untuk level tertentu.
create or replace function public._tree_stats(p_level int, p_premium boolean)
returns table (interval_sec int, capacity int, coins_per_fruit int)
language plpgsql stable
set search_path = public
as $$
declare
  c public.tree_config;
begin
  select * into c from public.tree_config where id = 1;
  interval_sec := ceil(
    greatest(c.min_interval_min, c.base_interval_min - (p_level - 1) * c.interval_step_min) * 60.0
    / (case when p_premium then greatest(c.premium_speed, 1) else 1 end)
  )::int;
  capacity        := c.base_capacity + (p_level - 1) / 2;  -- Lv.10 = 10 buah
  coins_per_fruit := 1 + (p_level - 1) / 3;                 -- Lv.10 = 4 ZCoin/buah
  return next;
end $$;

-- Hitung buah yang sudah matang (pakai jam server) lalu simpan. Mengunci baris.
-- Kalau pohon penuh, pertumbuhan berhenti (anchor digeser ke sekarang).
create or replace function public._tree_sync(p_uid text, p_premium boolean)
returns public.tree_state
language plpgsql
set search_path = public
as $$
declare
  s  public.tree_state;
  st record;
  n  int;
begin
  insert into public.tree_state (firebase_uid) values (p_uid)
  on conflict (firebase_uid) do nothing;

  select * into s from public.tree_state where firebase_uid = p_uid for update;
  select * into st from public._tree_stats(s.level, p_premium);

  if s.fruits >= st.capacity then
    s.fruits := st.capacity;
    s.grow_anchor := now();
  else
    n := floor(extract(epoch from (now() - s.grow_anchor)) / st.interval_sec)::int;
    if n > 0 then
      if s.fruits + n >= st.capacity then
        s.fruits := st.capacity;
        s.grow_anchor := now();
      else
        s.fruits := s.fruits + n;
        s.grow_anchor := s.grow_anchor + make_interval(secs => n * st.interval_sec);
      end if;
    end if;
  end if;

  if s.coins_day <> public._tree_today() then
    s.coins_day := public._tree_today();
    s.coins_today := 0;
  end if;

  update public.tree_state
     set fruits = s.fruits,
         grow_anchor = s.grow_anchor,
         coins_day = s.coins_day,
         coins_today = s.coins_today,
         updated_at = now()
   where firebase_uid = p_uid;

  return s;
end $$;

-- State pohon versi JSON buat app.
create or replace function public._tree_json(s public.tree_state, p_premium boolean)
returns jsonb
language plpgsql stable
set search_path = public
as $$
declare
  c      public.tree_config;
  st     record;
  nx     record;
  v_next jsonb := null;
  v_cost int   := null;
  v_recv int;
  v_gave int;
begin
  select * into c from public.tree_config where id = 1;
  select * into st from public._tree_stats(s.level, p_premium);

  if s.level < c.max_level then
    select * into nx from public._tree_stats(s.level + 1, p_premium);
    v_next := jsonb_build_object(
      'interval_sec', nx.interval_sec,
      'capacity', nx.capacity,
      'coins_per_fruit', nx.coins_per_fruit
    );
    v_cost := c.upgrade_cost_per_level * s.level;
  end if;

  select count(*) into v_recv from public.tree_water_log
   where receiver_uid = s.firebase_uid and day = public._tree_today();
  select count(*) into v_gave from public.tree_water_log
   where giver_uid = s.firebase_uid and day = public._tree_today();

  return jsonb_build_object(
    'level', s.level,
    'max_level', c.max_level,
    'fruits', s.fruits,
    'capacity', st.capacity,
    'interval_sec', st.interval_sec,
    'coins_per_fruit', st.coins_per_fruit,
    'next_fruit_at', case when s.fruits >= st.capacity then null
                          else s.grow_anchor + make_interval(secs => st.interval_sec) end,
    'coins_today', case when s.coins_day = public._tree_today() then s.coins_today else 0 end,
    'daily_cap', c.daily_coin_cap,
    'upgrade_cost', v_cost,
    'next', v_next,
    'premium', p_premium,
    'premium_speed', c.premium_speed,
    'water_received_today', v_recv,
    'water_receive_limit', c.water_receive_per_day,
    'water_given_today', v_gave,
    'water_give_limit', c.water_give_per_day,
    'water_bonus_min', c.water_bonus_min,
    'total_coins', s.total_coins,
    'server_now', now()
  );
end $$;

-- =====================================================================
-- RPC (dipanggil Edge Function tree-game pakai service_role)
-- =====================================================================

create or replace function public.tree_get(p_uid text, p_premium boolean)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  s public.tree_state;
begin
  select * into s from public._tree_sync(p_uid, p_premium);
  return public._tree_json(s, p_premium);
end $$;

create or replace function public.tree_harvest(p_uid text, p_premium boolean, p_count int)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c       public.tree_config;
  s       public.tree_state;
  st      record;
  v_room  int;
  v_count int;
  v_coins int;
  v_bal   bigint;
begin
  if p_count is null or p_count < 1 then
    raise exception 'Jumlah panen tidak valid';
  end if;

  select * into c from public.tree_config where id = 1;
  select * into s from public._tree_sync(p_uid, p_premium);

  if s.fruits <= 0 then
    raise exception 'Belum ada buah yang matang';
  end if;

  v_room := c.daily_coin_cap - s.coins_today;
  if v_room <= 0 then
    raise exception 'Batas % ZCoin dari pohon hari ini sudah tercapai. Balik lagi besok ya!', c.daily_coin_cap;
  end if;

  select * into st from public._tree_stats(s.level, p_premium);
  v_count := least(p_count, s.fruits, ceil(v_room::numeric / st.coins_per_fruit)::int);
  v_coins := least(v_count * st.coins_per_fruit, v_room);

  update public.tree_state
     set fruits = fruits - v_count,
         coins_today = coins_today + v_coins,
         total_fruits = total_fruits + v_count,
         total_coins = total_coins + v_coins,
         updated_at = now()
   where firebase_uid = p_uid
  returning * into s;

  insert into public.user_coins (firebase_uid, balance)
  values (p_uid, v_coins)
  on conflict (firebase_uid) do update
    set balance = public.user_coins.balance + excluded.balance,
        updated_at = now()
  returning balance into v_bal;

  insert into public.tree_coin_log (firebase_uid, kind, amount, detail)
  values (p_uid, 'harvest', v_coins, jsonb_build_object('fruits', v_count));

  return jsonb_build_object(
    'harvested', v_count,
    'coins', v_coins,
    'balance', v_bal,
    'tree', public._tree_json(s, p_premium)
  );
end $$;

create or replace function public.tree_upgrade(p_uid text, p_premium boolean)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c      public.tree_config;
  s      public.tree_state;
  v_cost int;
  v_bal  bigint;
begin
  select * into c from public.tree_config where id = 1;
  -- sync dulu supaya buah yang tumbuh sebelum upgrade dihitung pakai kecepatan lama
  select * into s from public._tree_sync(p_uid, p_premium);

  if s.level >= c.max_level then
    raise exception 'Pohon kamu sudah level maksimal';
  end if;

  v_cost := c.upgrade_cost_per_level * s.level;

  update public.user_coins
     set balance = balance - v_cost,
         updated_at = now()
   where firebase_uid = p_uid and balance >= v_cost
  returning balance into v_bal;

  if not found then
    raise exception 'ZCoin kamu kurang. Butuh % ZCoin buat upgrade', v_cost;
  end if;

  update public.tree_state
     set level = level + 1, updated_at = now()
   where firebase_uid = p_uid
  returning * into s;

  insert into public.tree_coin_log (firebase_uid, kind, amount, detail)
  values (p_uid, 'upgrade', -v_cost, jsonb_build_object('to_level', s.level));

  return jsonb_build_object(
    'cost', v_cost,
    'balance', v_bal,
    'tree', public._tree_json(s, p_premium)
  );
end $$;

create or replace function public.tree_water(p_giver text, p_receiver text, p_receiver_premium boolean)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c       public.tree_config;
  s       public.tree_state;
  st      record;
  v_today date := public._tree_today();
  v_gave  int;
  v_recv  int;
begin
  if p_giver = p_receiver then
    raise exception 'Nggak bisa nyiram pohon sendiri';
  end if;

  if not exists (
    select 1 from public.friendships
     where status = 'accepted'
       and ((requester_uid = p_giver and addressee_uid = p_receiver)
         or (requester_uid = p_receiver and addressee_uid = p_giver))
  ) then
    raise exception 'Cuma bisa nyiram pohon teman';
  end if;

  select * into c from public.tree_config where id = 1;

  -- kunci jatah si penyiram (cegah spam request paralel)
  perform pg_advisory_xact_lock(hashtext('tree_water:' || p_giver));
  -- kunci baris pohon penerima
  select * into s from public._tree_sync(p_receiver, p_receiver_premium);

  select count(*) into v_gave from public.tree_water_log
   where giver_uid = p_giver and day = v_today;
  if v_gave >= c.water_give_per_day then
    raise exception 'Jatah siram kamu hari ini sudah habis (% kali)', c.water_give_per_day;
  end if;

  if exists (select 1 from public.tree_water_log
              where giver_uid = p_giver and receiver_uid = p_receiver and day = v_today) then
    raise exception 'Kamu sudah nyiram pohon dia hari ini';
  end if;

  select count(*) into v_recv from public.tree_water_log
   where receiver_uid = p_receiver and day = v_today;
  if v_recv >= c.water_receive_per_day then
    raise exception 'Pohon dia sudah cukup disiram hari ini';
  end if;

  select * into st from public._tree_stats(s.level, p_receiver_premium);
  if s.fruits >= st.capacity then
    raise exception 'Pohon dia lagi penuh buah, belum bisa disiram';
  end if;

  insert into public.tree_water_log (giver_uid, receiver_uid, day)
  values (p_giver, p_receiver, v_today);

  update public.tree_state
     set grow_anchor = grow_anchor - make_interval(mins => c.water_bonus_min),
         updated_at = now()
   where firebase_uid = p_receiver;

  -- materialisasi buah yang jadi matang karena siraman
  perform public._tree_sync(p_receiver, p_receiver_premium);

  return jsonb_build_object(
    'ok', true,
    'bonus_min', c.water_bonus_min,
    'given_today', v_gave + 1,
    'give_limit', c.water_give_per_day
  );
end $$;

create or replace function public.tree_water_status(p_uid text)
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select jsonb_build_object(
    'watered', coalesce(jsonb_agg(l.receiver_uid), '[]'::jsonb),
    'given_today', count(*),
    'give_limit', (select water_give_per_day from public.tree_config where id = 1),
    'bonus_min', (select water_bonus_min from public.tree_config where id = 1)
  )
  from public.tree_water_log l
  where l.giver_uid = p_uid and l.day = public._tree_today();
$$;

-- ---------- Hak eksekusi: cuma service_role ----------
revoke all on function public._tree_today()                         from public, anon, authenticated;
revoke all on function public._tree_stats(int, boolean)             from public, anon, authenticated;
revoke all on function public._tree_sync(text, boolean)             from public, anon, authenticated;
revoke all on function public._tree_json(public.tree_state, boolean) from public, anon, authenticated;
revoke all on function public.tree_get(text, boolean)               from public, anon, authenticated;
revoke all on function public.tree_harvest(text, boolean, int)      from public, anon, authenticated;
revoke all on function public.tree_upgrade(text, boolean)           from public, anon, authenticated;
revoke all on function public.tree_water(text, text, boolean)       from public, anon, authenticated;
revoke all on function public.tree_water_status(text)               from public, anon, authenticated;

grant execute on function public.tree_get(text, boolean)          to service_role;
grant execute on function public.tree_harvest(text, boolean, int) to service_role;
grant execute on function public.tree_upgrade(text, boolean)      to service_role;
grant execute on function public.tree_water(text, text, boolean)  to service_role;
grant execute on function public.tree_water_status(text)          to service_role;

-- Cek cepat (harus 0 baris = aman):
-- select routine_name, grantee from information_schema.routine_privileges
--  where routine_schema = 'public' and routine_name like '%tree%'
--    and grantee in ('anon','authenticated','PUBLIC');
