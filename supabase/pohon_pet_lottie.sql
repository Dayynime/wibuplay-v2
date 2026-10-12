-- =====================================================================
-- POHON ZCOIN — PET ANIMASI LOTTIE
-- Jalankan SETELAH pohon_dekorasi.sql. Aman dijalankan ulang.
--
-- File animasi (.json Lottie) diupload ke bucket publik `tree-assets`
-- lewat Supabase Studio -> Storage. Lalu isi kolom `asset` item pet dengan
-- nama filenya (contoh di bagian bawah).
-- =====================================================================

-- ---------- Kolom aset di katalog ----------
alter table public.tree_items add column if not exists asset text;
alter table public.tree_items add column if not exists asset_place text not null default 'ground_right';
alter table public.tree_items add column if not exists asset_scale numeric not null default 1;

alter table public.tree_items drop constraint if exists tree_items_asset_check;
alter table public.tree_items add constraint tree_items_asset_check
  check (asset is null or asset ~ '^[A-Za-z0-9._-]{1,80}\.json$');

alter table public.tree_items drop constraint if exists tree_items_asset_place_check;
alter table public.tree_items add constraint tree_items_asset_place_check
  check (asset_place in ('ground_left', 'ground_right', 'canopy_top', 'branch_left', 'branch_right'));

alter table public.tree_items drop constraint if exists tree_items_asset_scale_check;
alter table public.tree_items add constraint tree_items_asset_scale_check
  check (asset_scale > 0 and asset_scale <= 3);

-- ---------- Bucket publik buat file animasi ----------
insert into storage.buckets (id, name, public)
values ('tree-assets', 'tree-assets', true)
on conflict (id) do update set public = true;

-- Batasi cuma file JSON maks 2 MB (dilewati kalau versi storage-mu belum punya kolomnya).
do $$
begin
  update storage.buckets
     set file_size_limit = 2097152,
         allowed_mime_types = array['application/json']
   where id = 'tree-assets';
exception when undefined_column then
  null;
end $$;

-- ---------- Dekorasi terpasang ikut membawa info animasi pet ----------
create or replace function public._tree_equipped_json(p_uid text)
returns jsonb
language sql stable
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object(
       'tree', e.tree_skin, 'fruit', e.fruit_skin, 'tree_deco', e.tree_deco,
       'ground', to_jsonb(e.ground), 'pet', e.pet, 'effect', e.effect,
       'pet_asset', (select jsonb_build_object('file', i.asset, 'place', i.asset_place, 'scale', i.asset_scale)
                       from public.tree_items i
                      where i.id = e.pet and i.asset is not null))
     from public.tree_equipped e where e.firebase_uid = p_uid),
    jsonb_build_object('tree', null, 'fruit', null, 'tree_deco', null,
                       'ground', '[]'::jsonb, 'pet', null, 'effect', null, 'pet_asset', null)
  );
$$;

-- ---------- Toko ikut mengirim info animasi ----------
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
               'asset', i.asset, 'asset_place', i.asset_place, 'asset_scale', i.asset_scale)
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

-- =====================================================================
-- CONTOH: pasang animasi ke pet (jalankan setelah file diupload)
-- =====================================================================
-- Posisi (asset_place):
--   ground_left / ground_right  = duduk di tanah kiri/kanan batang
--   canopy_top                  = di puncak kanopi (ikut goyang)
--   branch_left / branch_right  = di dahan bawah kanopi (ikut goyang)
-- asset_scale: 1 = normal, 1.3 = lebih besar, 0.8 = lebih kecil
--
-- update tree_items set asset = 'kitsune.json', asset_place = 'ground_right', asset_scale = 1   where id = 'pet_kitsune';
-- update tree_items set asset = 'cat.json',     asset_place = 'branch_left',  asset_scale = 0.9 where id = 'pet_cat';
-- update tree_items set asset = 'bird.json',    asset_place = 'canopy_top',   asset_scale = 0.7 where id = 'pet_bird';
-- update tree_items set asset = 'slime.json',   asset_place = 'ground_left',  asset_scale = 0.9 where id = 'pet_slime';
--
-- Pet BARU tanpa update APK:
-- insert into tree_items (id, slot, name, description, rarity, price, asset, asset_place, asset_scale, sort)
-- values ('pet_panda', 'pet', 'Panda', 'Panda gemoy', 'epic', 3000, 'panda.json', 'ground_left', 1, 10);
