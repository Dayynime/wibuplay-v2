-- =====================================================================
-- Level XP user: maksimal 2.000 XP per level, tidak ada yang turun level.
--   level = yang lebih tinggi antara rumus lama (total Lv.n = 100*n*(n-1))
--           dan 1 + floor(total_xp / 2000).
--   Lv.1-20 tetap rumus lama (cepat); mulai Lv.20 (38.000 XP) rata 2.000/level.
-- Semua user dihitung ulang dari total XP-nya: XP banyak loncat level, XP sedikit tetap.
-- Trigger memastikan SEMUA jalur XP (nonton, donasi, bonus premium, dll)
-- memakai rumus ini, walaupun fungsinya masih menulis level dengan rumus lama.
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < xp_flat2k.sql
-- =====================================================================
begin;

-- Rumus lama (dipakai sebagai batas bawah supaya tidak ada yang turun level).
create or replace function public._level_old_formula(p_total_xp bigint)
returns integer
language plpgsql
immutable
as $function$
declare v_level int;
begin
  if p_total_xp is null or p_total_xp <= 0 then return 1; end if;
  v_level := greatest(floor((1 + sqrt(1 + p_total_xp::double precision / 25.0)) / 2)::int, 1);
  while (100::bigint * (v_level + 1) * v_level) <= p_total_xp loop v_level := v_level + 1; end loop;
  while v_level > 1 and (100::bigint * v_level * (v_level - 1)) > p_total_xp loop v_level := v_level - 1; end loop;
  return v_level;
end;
$function$;

create or replace function public.level_for_total_xp(p_total_xp bigint)
returns integer
language sql
immutable
as $$
  select greatest(
    public._level_old_formula(p_total_xp),
    (1 + greatest(coalesce(p_total_xp, 0), 0) / 2000)::int
  )
$$;

create or replace function private.trg_user_xp_level()
returns trigger
language plpgsql
as $$
begin
  new.level := public.level_for_total_xp(new.total_xp);
  return new;
end;
$$;

drop trigger if exists trg_user_xp_level on public.user_xp;
create trigger trg_user_xp_level
  before insert or update on public.user_xp
  for each row execute function private.trg_user_xp_level();

-- Hitung ulang level semua user (total_xp tidak berubah, leaderboard bulanan aman).
update public.user_xp
   set level = public.level_for_total_xp(total_xp)
 where level is distinct from public.level_for_total_xp(total_xp);

commit;

-- Ringkasan
select count(*) as total_user, max(level) as level_tertinggi,
       count(*) filter (where level >= 100) as lv100_plus,
       count(*) filter (where level between 50 and 99) as lv50_99,
       count(*) filter (where level between 10 and 49) as lv10_49,
       count(*) filter (where level < 10) as di_bawah_lv10
  from public.user_xp;
