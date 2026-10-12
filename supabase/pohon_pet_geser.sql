-- =====================================================================
-- POHON ZCOIN — GESER POSISI PET LOTTIE (asset_dx / asset_dy)
-- Jalankan SETELAH pohon_pet_lottie.sql. Aman dijalankan ulang.
--
-- asset_dx: geser ke kanan (+) / kiri (-)   } satuan = ukuran kotak animasi
-- asset_dy: geser ke bawah (+) / atas (-)   } contoh 0.15 = 15% tinggi kotak
-- =====================================================================

alter table public.tree_items add column if not exists asset_dx numeric not null default 0;
alter table public.tree_items add column if not exists asset_dy numeric not null default 0;

alter table public.tree_items drop constraint if exists tree_items_asset_dxdy_check;
alter table public.tree_items add constraint tree_items_asset_dxdy_check
  check (asset_dx between -1 and 1 and asset_dy between -1 and 1);

create or replace function public._tree_equipped_json(p_uid text)
returns jsonb
language sql stable
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object(
       'tree', e.tree_skin, 'fruit', e.fruit_skin, 'tree_deco', e.tree_deco,
       'ground', to_jsonb(e.ground), 'pet', e.pet, 'effect', e.effect,
       'pet_asset', (select jsonb_build_object('file', i.asset, 'place', i.asset_place, 'scale', i.asset_scale,
                                               'dx', i.asset_dx, 'dy', i.asset_dy)
                       from public.tree_items i
                      where i.id = e.pet and i.asset is not null))
     from public.tree_equipped e where e.firebase_uid = p_uid),
    jsonb_build_object('tree', null, 'fruit', null, 'tree_deco', null,
                       'ground', '[]'::jsonb, 'pet', null, 'effect', null, 'pet_asset', null)
  );
$$;

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
               'available_until', i.available_until,
               'asset', i.asset, 'asset_place', i.asset_place, 'asset_scale', i.asset_scale,
               'asset_dx', i.asset_dx, 'asset_dy', i.asset_dy)
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

revoke all on function public._tree_equipped_json(text) from public, anon, authenticated;
revoke all on function public.tree_shop(text)           from public, anon, authenticated;
grant execute on function public.tree_shop(text)        to service_role;

-- Contoh: turunkan kucing 15% biar nempel di kanopi
-- update tree_items set asset_dy = 0.15 where id = 'pet_cat';
