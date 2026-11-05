-- =====================================================================
-- Upgrade pohon beberapa level sekaligus (+1 / +5 / +10 / Maks).
--   tree_upgrade(p_uid, p_premium, p_count default 1)
--   Total biaya = jumlah biaya tiap level, dipotong SEKALI (atomik).
--   Pemanggilan lama tanpa p_count tetap jalan (= +1 level).
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < tree_multi.sql
-- =====================================================================
begin;

drop function if exists public.tree_upgrade(text, boolean);

create or replace function public.tree_upgrade(p_uid text, p_premium boolean, p_count integer default 1)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c      public.tree_config;
  s      public.tree_state;
  v_from int;
  v_n    int;
  v_cost bigint;
  v_bal  bigint;
begin
  select * into c from public.tree_config where id = 1;
  -- sync dulu supaya buah yang tumbuh sebelum upgrade dihitung pakai kecepatan lama
  select * into s from public._tree_sync(p_uid, p_premium);

  if s.level >= c.max_level then
    raise exception 'Pohon kamu sudah level maksimal';
  end if;

  v_from := s.level;
  v_n := least(greatest(coalesce(p_count, 1), 1), c.max_level - s.level);
  select sum(public._tree_upgrade_cost(l)) into v_cost
    from generate_series(s.level, s.level + v_n - 1) l;

  update public.user_coins
     set balance = balance - v_cost,
         updated_at = now()
   where firebase_uid = p_uid and balance >= v_cost
  returning balance into v_bal;

  if not found then
    if v_n = 1 then
      raise exception 'ZCoin kamu kurang. Butuh % ZCoin buat upgrade', v_cost;
    end if;
    raise exception 'ZCoin kamu kurang. Butuh % ZCoin buat upgrade % level', v_cost, v_n;
  end if;

  update public.tree_state
     set level = level + v_n, updated_at = now()
   where firebase_uid = p_uid
  returning * into s;

  insert into public.tree_coin_log (firebase_uid, kind, amount, detail)
  values (p_uid, 'upgrade', -v_cost::int,
          jsonb_build_object('from_level', v_from, 'to_level', s.level, 'levels', v_n));

  return jsonb_build_object(
    'cost', v_cost,
    'levels', v_n,
    'balance', v_bal,
    'tree', public._tree_json(s, p_premium)
  );
end $function$;

revoke all on function public.tree_upgrade(text, boolean, integer) from public, anon, authenticated;
grant execute on function public.tree_upgrade(text, boolean, integer) to service_role;

-- _tree_json: tambah upgrade_cost_base & upgrade_cost_step (sisanya sama).
CREATE OR REPLACE FUNCTION public._tree_json(s tree_state, p_premium boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
      'coins_per_fruit', nx.coins_per_fruit,
      'daily_cap', public._tree_daily_cap(s.level + 1)
    );
    v_cost := public._tree_upgrade_cost(s.level);
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
    'daily_cap', public._tree_daily_cap(s.level),
    'upgrade_cost', v_cost,
    -- biaya Lv.n -> n+1 = upgrade_cost_base + upgrade_cost_step * n (buat hitung +5/+10/Maks di app)
    'upgrade_cost_base', c.upgrade_cost_base,
    'upgrade_cost_step', c.upgrade_cost_per_level,
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
end $function$;

commit;
