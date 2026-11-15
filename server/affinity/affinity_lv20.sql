-- =====================================================================
-- Afinitas: maksimal Lv 20 (dulu Lv 5). 5 tahap x 4 level:
--   Lv1-4 Deai, 5-8 Kizuna, 9-12 Shinrai, 13-16 Kyoumei, 17-20 Eien.
-- * Hanya array 'levels' di _aff_cfg() yang diganti (setting lain di
--   server tetap seperti sekarang).
-- * Level semua pasangan dihitung ulang dari poinnya; level tidak pernah
--   turun (pakai greatest dengan level sekarang).
-- Jalankan: docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < affinity_lv20.sql
-- =====================================================================
begin;

do $$
declare
  d   text := pg_get_functiondef('public._aff_cfg()'::regprocedure);
  old text := 'jsonb_build_array(0, 500, 2000, 6000, 15000)';
  neu text := 'jsonb_build_array(0, 300, 800, 1500, 2500, 4000, 6000, 8500, 11500, 15000, '
              '19000, 24000, 30000, 37000, 45000, 54000, 64000, 75000, 87000, 100000)';
begin
  if position(old in d) = 0 then
    raise exception 'Array level lama tidak ditemukan di _aff_cfg(), dibatalkan';
  end if;
  execute replace(d, old, neu);
end $$;

create or replace function public._aff_level_name(p int)
returns text language sql immutable
as $$
  select case
    when p is null or p < 1 then ''
    else (array['Deai','Kizuna','Shinrai','Kyoumei','Eien'])[least(5, (p - 1) / 4 + 1)] || ' Lv ' || p
  end
$$;

-- Hitung ulang level dari poin (tanpa notifikasi). Level lama Lv5 (>=15.000 poin) -> Lv10, dst.
update public.affinities
   set level = greatest(level, public._aff_level(points))
 where public._aff_level(points) > level;

select jsonb_array_length(public._aff_cfg()->'levels') as jumlah_level,
       public._aff_level(15000) as lv_15000,
       public._aff_level(100000) as lv_100000,
       public._aff_level_name(10) as nama_lv10;
select level, count(*) from public.affinities group by level order by level;
commit;
