-- =====================================================================
-- POHON ZCOIN — TOKO DEKORASI + KUNJUNGI POHON TEMAN
-- Jalankan SETELAH pohon_zcoin.sql. Aman dijalankan ulang.
-- Harga/nama item bisa diubah langsung di tabel tree_items kapan saja
-- (menjalankan ulang file ini TIDAK menimpa perubahanmu).
-- =====================================================================

-- ---------- Katalog item ----------
create table if not exists public.tree_items (
  id              text primary key,
  slot            text not null check (slot in ('tree', 'fruit', 'tree_deco', 'ground', 'pet', 'effect')),
  name            text not null,
  description     text not null default '',
  rarity          text not null check (rarity in ('common', 'rare', 'epic', 'legendary')),
  price           int  not null check (price >= 0),
  premium_only    boolean not null default false,
  available_from  timestamptz,
  available_until timestamptz,
  sort            int  not null default 0,
  active          boolean not null default true
);

-- ---------- Item yang dimiliki ----------
create table if not exists public.tree_inventory (
  firebase_uid text not null,
  item_id      text not null references public.tree_items (id),
  price_paid   int  not null default 0,
  bought_at    timestamptz not null default now(),
  primary key (firebase_uid, item_id)
);

-- ---------- Item yang sedang dipasang ----------
create table if not exists public.tree_equipped (
  firebase_uid text primary key,
  tree_skin    text references public.tree_items (id),
  fruit_skin   text references public.tree_items (id),
  tree_deco    text references public.tree_items (id),
  ground       text[] not null default '{}',
  pet          text references public.tree_items (id),
  effect       text references public.tree_items (id),
  updated_at   timestamptz not null default now()
);

alter table public.tree_items     enable row level security;
alter table public.tree_inventory enable row level security;
alter table public.tree_equipped  enable row level security;
revoke all on table public.tree_items, public.tree_inventory, public.tree_equipped
  from public, anon, authenticated;

-- Log ZCoin pohon sekarang juga mencatat belanja toko.
alter table public.tree_coin_log drop constraint if exists tree_coin_log_kind_check;
alter table public.tree_coin_log add constraint tree_coin_log_kind_check
  check (kind in ('harvest', 'upgrade', 'shop'));

-- ---------- Isi katalog awal ----------
insert into public.tree_items (id, slot, name, description, rarity, price, premium_only, available_until, sort) values
  -- Skin pohon
  ('tree_sakura',   'tree', 'Sakura',        'Kanopi pink dengan kelopak berguguran',   'rare',      750,  false, null, 1),
  ('tree_autumn',   'tree', 'Musim Gugur',   'Daun oranye-merah ala musim gugur',       'rare',      750,  false, null, 2),
  ('tree_snow',     'tree', 'Pohon Salju',   'Pohon bersalju dengan salju turun',       'epic',      2000, false, null, 3),
  ('tree_neon',     'tree', 'Pohon Neon',    'Glowing ala cyberpunk',                   'epic',      2000, true,  null, 4),
  ('tree_gold',     'tree', 'Pohon Emas',    'Pohon emas berkilauan',                   'legendary', 5000, false, null, 5),
  -- Skin buah
  ('fruit_apple',   'fruit', 'Apel Merah',   'Buah jadi apel merah',                    'common',    250,  false, null, 1),
  ('fruit_peach',   'fruit', 'Persik',       'Buah jadi persik',                        'common',    250,  false, null, 2),
  ('fruit_star',    'fruit', 'Bintang',      'Buah berbentuk bintang emas',             'rare',      750,  false, null, 3),
  ('fruit_candy',   'fruit', 'Permen',       'Buah jadi permen lolipop',                'rare',      750,  false, null, 4),
  ('fruit_lantern', 'fruit', 'Lentera',      'Buah jadi lentera kecil menyala',         'epic',      2000, false, null, 5),
  ('fruit_crystal', 'fruit', 'Koin Kristal', 'Buah kristal berkilau',                   'legendary', 5000, false, null, 6),
  -- Hiasan pohon
  ('deco_lights',   'tree_deco', 'Lampu Kelap-kelip', 'Untaian lampu warna-warni',      'common',    300,  false, null, 1),
  ('deco_nest',     'tree_deco', 'Sarang Burung',     'Sarang dengan tiga telur',       'common',    300,  false, null, 2),
  ('deco_lanterns', 'tree_deco', 'Lampion Jepang',    'Tiga lampion merah bergoyang',   'rare',      750,  false, null, 3),
  ('deco_swing',    'tree_deco', 'Ayunan',            'Ayunan kayu yang berayun',       'rare',      750,  false, null, 4),
  ('deco_clanflag', 'tree_deco', 'Bendera Clan',      'Bendera dengan tag clan kamu',   'rare',      1000, false, null, 5),
  ('deco_treehouse','tree_deco', 'Rumah Pohon',       'Rumah kayu mungil di dahan',     'epic',      2000, false, null, 6),
  -- Hiasan tanah
  ('ground_fence',  'ground', 'Pagar Kayu',    'Pagar kayu sederhana',                  'common',    250,  false, null, 1),
  ('ground_bench',  'ground', 'Bangku Taman',  'Bangku buat santai',                    'common',    300,  false, null, 2),
  ('ground_sign',   'ground', 'Papan Nama',    'Papan berisi username kamu',            'common',    300,  false, null, 3),
  ('ground_stonelantern','ground','Lentera Batu','Lentera batu khas Jepang',            'common',    400,  false, null, 4),
  ('ground_mushroom','ground','Jamur Menyala', 'Jamur yang menyala di malam hari',      'rare',      750,  false, null, 5),
  ('ground_torii',  'ground', 'Gerbang Torii', 'Gerbang merah khas kuil',               'rare',      1000, false, null, 6),
  ('ground_pond',   'ground', 'Kolam Koi',     'Kolam kecil dengan ikan koi berenang',  'epic',      2000, false, null, 7),
  -- Pet
  ('pet_bird',      'pet', 'Burung Biru',   'Burung kecil hinggap di pohon',            'common',    500,  false, null, 1),
  ('pet_slime',     'pet', 'Slime',         'Slime yang lompat-lompat',                 'rare',      1000, false, null, 2),
  ('pet_cat',       'pet', 'Kucing Tidur',  'Kucing tidur di dahan',                    'rare',      1500, false, null, 3),
  ('pet_kitsune',   'pet', 'Kitsune',       'Rubah dengan api biru',                    'legendary', 5000, true,  null, 4),
  -- Efek suasana
  ('fx_goldflies',  'effect', 'Kunang Emas',  'Kunang-kunang emas, siang dan malam',    'rare',      1000, false, null, 1),
  ('fx_petals',     'effect', 'Hujan Kelopak','Kelopak bunga berjatuhan',               'rare',      1000, false, null, 2),
  ('fx_fuji',       'effect', 'Gunung Fuji',  'Latar Gunung Fuji',                      'epic',      2000, false, null, 3),
  ('fx_aurora',     'effect', 'Aurora',       'Aurora menari di langit malam',          'epic',      2500, false, null, 4),
  ('fx_fireworks',  'effect', 'Kembang Api',  'Kembang api di langit',                  'epic',      2500, false, null, 5),
  -- Set Halloween (terbatas)
  ('fruit_pumpkin', 'fruit',  'Labu Kecil',   'Halloween: buah jadi labu',              'rare',      800,  false, '2026-11-03 00:00+07', 90),
  ('ground_pumpkin','ground', 'Labu Halloween','Halloween: labu berukir menyala',       'common',    300,  false, '2026-11-03 00:00+07', 90),
  ('fx_bats',       'effect', 'Kelelawar',    'Halloween: kelelawar beterbangan',       'rare',      800,  false, '2026-11-03 00:00+07', 90)
on conflict (id) do nothing;

-- =====================================================================
-- Fungsi
-- =====================================================================

create or replace function public._tree_equipped_json(p_uid text)
returns jsonb
language sql stable
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object(
       'tree', e.tree_skin, 'fruit', e.fruit_skin, 'tree_deco', e.tree_deco,
       'ground', to_jsonb(e.ground), 'pet', e.pet, 'effect', e.effect)
     from public.tree_equipped e where e.firebase_uid = p_uid),
    jsonb_build_object('tree', null, 'fruit', null, 'tree_deco', null,
                       'ground', '[]'::jsonb, 'pet', null, 'effect', null)
  );
$$;

-- tree_get sekarang ikut mengirim dekorasi yang dipasang.
create or replace function public.tree_get(p_uid text, p_premium boolean)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  s public.tree_state;
begin
  select * into s from public._tree_sync(p_uid, p_premium);
  return public._tree_json(s, p_premium)
         || jsonb_build_object('equipped', public._tree_equipped_json(p_uid));
end $$;

create or replace function public.tree_shop(p_uid text)
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
begin
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', i.id, 'slot', i.slot, 'name', i.name, 'description', i.description,
               'rarity', i.rarity, 'price', i.price, 'premium_only', i.premium_only,
               'available_until', i.available_until)
             order by i.slot, i.sort, i.price)
      from public.tree_items i
      where i.active
        and (
          ((i.available_from is null or i.available_from <= now())
            and (i.available_until is null or i.available_until > now()))
          or exists (select 1 from public.tree_inventory v
                      where v.firebase_uid = p_uid and v.item_id = i.id)
        )
    ), '[]'::jsonb),
    'owned', coalesce((select jsonb_agg(v.item_id) from public.tree_inventory v
                        where v.firebase_uid = p_uid), '[]'::jsonb),
    'equipped', public._tree_equipped_json(p_uid)
  );
end $$;

create or replace function public.tree_buy(p_uid text, p_premium boolean, p_item text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  it    public.tree_items;
  v_bal bigint;
begin
  select * into it from public.tree_items where id = p_item and active;
  if not found then
    raise exception 'Item tidak ditemukan';
  end if;
  if (it.available_from is not null and it.available_from > now())
     or (it.available_until is not null and it.available_until <= now()) then
    raise exception 'Item ini sudah tidak dijual';
  end if;
  if it.premium_only and not p_premium then
    raise exception 'Item ini khusus Premium';
  end if;

  perform pg_advisory_xact_lock(hashtext('tree_buy:' || p_uid));

  if exists (select 1 from public.tree_inventory where firebase_uid = p_uid and item_id = p_item) then
    raise exception 'Kamu sudah punya item ini';
  end if;

  if it.price > 0 then
    update public.user_coins
       set balance = balance - it.price, updated_at = now()
     where firebase_uid = p_uid and balance >= it.price
    returning balance into v_bal;
    if not found then
      raise exception 'ZCoin kamu kurang. Butuh % ZCoin', it.price;
    end if;
  else
    select balance into v_bal from public.user_coins where firebase_uid = p_uid;
  end if;

  insert into public.tree_inventory (firebase_uid, item_id, price_paid)
  values (p_uid, p_item, it.price);

  insert into public.tree_coin_log (firebase_uid, kind, amount, detail)
  values (p_uid, 'shop', -it.price, jsonb_build_object('item', p_item));

  return jsonb_build_object('balance', coalesce(v_bal, 0), 'item', p_item);
end $$;

create or replace function public.tree_equip(p_uid text, p_item text, p_on boolean)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_slot text;
  e      public.tree_equipped;
begin
  select slot into v_slot from public.tree_items where id = p_item;
  if v_slot is null then
    raise exception 'Item tidak ditemukan';
  end if;
  if p_on and not exists (select 1 from public.tree_inventory
                           where firebase_uid = p_uid and item_id = p_item) then
    raise exception 'Beli dulu item ini';
  end if;

  insert into public.tree_equipped (firebase_uid) values (p_uid)
  on conflict (firebase_uid) do nothing;
  select * into e from public.tree_equipped where firebase_uid = p_uid for update;

  if v_slot = 'ground' then
    if p_on then
      if not (p_item = any (e.ground)) then
        if coalesce(array_length(e.ground, 1), 0) >= 2 then
          raise exception 'Maks 2 hiasan tanah. Lepas salah satu dulu';
        end if;
        e.ground := e.ground || p_item;
      end if;
    else
      e.ground := array_remove(e.ground, p_item);
    end if;
  elsif v_slot = 'tree' then
    e.tree_skin := case when p_on then p_item when e.tree_skin = p_item then null else e.tree_skin end;
  elsif v_slot = 'fruit' then
    e.fruit_skin := case when p_on then p_item when e.fruit_skin = p_item then null else e.fruit_skin end;
  elsif v_slot = 'tree_deco' then
    e.tree_deco := case when p_on then p_item when e.tree_deco = p_item then null else e.tree_deco end;
  elsif v_slot = 'pet' then
    e.pet := case when p_on then p_item when e.pet = p_item then null else e.pet end;
  elsif v_slot = 'effect' then
    e.effect := case when p_on then p_item when e.effect = p_item then null else e.effect end;
  end if;

  update public.tree_equipped
     set tree_skin = e.tree_skin, fruit_skin = e.fruit_skin, tree_deco = e.tree_deco,
         ground = e.ground, pet = e.pet, effect = e.effect, updated_at = now()
   where firebase_uid = p_uid;

  return public._tree_equipped_json(p_uid);
end $$;

-- Lihat pohon teman (read-only + status siram).
create or replace function public.tree_visit(p_viewer text, p_owner text, p_owner_premium boolean)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c      public.tree_config;
  s      public.tree_state;
  st     record;
  v_recv int;
  v_mine boolean;
begin
  if p_viewer <> p_owner and not exists (
    select 1 from public.friendships
     where status = 'accepted'
       and ((requester_uid = p_viewer and addressee_uid = p_owner)
         or (requester_uid = p_owner and addressee_uid = p_viewer))
  ) then
    raise exception 'Cuma bisa lihat pohon teman';
  end if;

  select * into c from public.tree_config where id = 1;
  select * into s from public._tree_sync(p_owner, p_owner_premium);
  select * into st from public._tree_stats(s.level, p_owner_premium);

  select count(*) into v_recv from public.tree_water_log
   where receiver_uid = p_owner and day = public._tree_today();
  v_mine := exists (select 1 from public.tree_water_log
                     where giver_uid = p_viewer and receiver_uid = p_owner
                       and day = public._tree_today());

  return jsonb_build_object(
    'level', s.level,
    'fruits', s.fruits,
    'capacity', st.capacity,
    'premium', p_owner_premium,
    'water_received_today', v_recv,
    'water_receive_limit', c.water_receive_per_day,
    'watered_by_me', v_mine,
    'equipped', public._tree_equipped_json(p_owner)
  );
end $$;

-- ---------- Hak eksekusi: cuma service_role ----------
revoke all on function public._tree_equipped_json(text)              from public, anon, authenticated;
revoke all on function public.tree_get(text, boolean)                from public, anon, authenticated;
revoke all on function public.tree_shop(text)                        from public, anon, authenticated;
revoke all on function public.tree_buy(text, boolean, text)          from public, anon, authenticated;
revoke all on function public.tree_equip(text, text, boolean)        from public, anon, authenticated;
revoke all on function public.tree_visit(text, text, boolean)        from public, anon, authenticated;

grant execute on function public.tree_get(text, boolean)         to service_role;
grant execute on function public.tree_shop(text)                 to service_role;
grant execute on function public.tree_buy(text, boolean, text)   to service_role;
grant execute on function public.tree_equip(text, text, boolean) to service_role;
grant execute on function public.tree_visit(text, text, boolean) to service_role;

-- Cek (harus 0 baris):
-- select routine_name, grantee from information_schema.routine_privileges
--  where routine_schema = 'public' and routine_name like '%tree%'
--    and grantee in ('anon','authenticated','PUBLIC');
