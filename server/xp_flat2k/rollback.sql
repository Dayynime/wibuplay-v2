-- Kembali ke rumus lama: total XP Lv.n = 100 * n * (n-1)
begin;
drop trigger if exists trg_user_xp_level on public.user_xp;
drop function if exists private.trg_user_xp_level();
create or replace function public.level_for_total_xp(p_total_xp bigint)
returns integer language plpgsql immutable as $function$
declare v_level int;
begin
  if p_total_xp <= 0 then return 1; end if;
  v_level := floor((1 + sqrt(1 + p_total_xp::double precision / 25.0)) / 2)::int;
  v_level := greatest(v_level, 1);
  while (100::bigint * (v_level + 1) * v_level) <= p_total_xp loop v_level := v_level + 1; end loop;
  while v_level > 1 and (100::bigint * v_level * (v_level - 1)) > p_total_xp loop v_level := v_level - 1; end loop;
  return v_level;
end; $function$;
update public.user_xp set level = public.level_for_total_xp(total_xp)
 where level is distinct from public.level_for_total_xp(total_xp);
drop function if exists public._level_old_formula(bigint);
commit;
