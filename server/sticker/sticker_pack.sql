-- =====================================================================
-- Pack stiker: stiker dikelompokkan per pack (tab di lembar stiker).
--   * kolom stickers.pack (opsional, 1-24 karakter; kosong = "Lainnya")
--   * sticker_create_upload(..., p_pack default null): app lama tetap jalan
--   * katalog, "Stiker saya" & antrean admin ikut menampilkan pack
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < sticker_pack.sql
-- =====================================================================
begin;

alter table public.stickers
  add column if not exists pack text check (pack is null or char_length(pack) between 1 and 24);
create index if not exists stickers_pack_idx on public.stickers (lower(pack)) where pack is not null;

-- Kolom baru ditambah di AKHIR view (aturan create or replace view).
create or replace view public.sticker_catalog as
  select code, name, public_path as path, reviewed_at as approved_at, pack
    from public.stickers
   where status = 'approved' and public_path is not null;

drop function if exists public.sticker_create_upload(text, text, text);

create or replace function public.sticker_create_upload(p_uid text, p_name text, p_mime text, p_pack text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg    jsonb := public._sticker_cfg();
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_pack text := nullif(btrim(regexp_replace(coalesce(p_pack, ''), '\s+', ' ', 'g')), '');
  v_canon text;
  v_ext  text;
  v_id   uuid := gen_random_uuid();
  v_code text;
  v_path text;
  i      int;
begin
  if p_uid is null or p_uid !~ '^[A-Za-z0-9_-]{1,128}$' then
    raise exception 'User tidak valid';
  end if;
  if exists (select 1 from banned_accounts where firebase_uid = p_uid) then
    raise exception 'Akun ini diblokir';
  end if;
  if not exists (
    select 1 from premium_status
     where firebase_uid = p_uid and is_premium
       and (expires_at is null or expires_at > now())
  ) then
    raise exception 'Upload stiker khusus pengguna Premium';
  end if;

  if char_length(v_name) < 1 or char_length(v_name) > 30 then
    raise exception 'Nama stiker 1-30 karakter';
  end if;
  if v_pack is not null and char_length(v_pack) > 24 then
    raise exception 'Nama pack maksimal 24 karakter';
  end if;
  -- Pack yang sudah ada dipakai ejaannya (wowo = Wowo = WOWO).
  if v_pack is not null then
    select pack into v_canon from stickers
     where lower(pack) = lower(v_pack) and status in ('uploading', 'pending', 'approved')
     order by created_at limit 1;
    v_pack := coalesce(v_canon, v_pack);
  end if;
  v_ext := case p_mime when 'image/png' then 'png' when 'image/webp' then 'webp'
                       when 'image/gif' then 'gif' when 'image/jpeg' then 'jpg' end;
  if v_ext is null then
    raise exception 'Format harus PNG, JPG, WebP, atau GIF';
  end if;

  -- Kunci per akun supaya cek kuota + insert tidak bisa diakali request paralel.
  perform pg_advisory_xact_lock(hashtext('sticker:' || p_uid));

  if (select count(*) from stickers
       where uploader_uid = p_uid and created_at > now() - interval '24 hours')
     >= (cfg->>'per_day')::int then
    raise exception 'Batas % upload stiker per hari sudah tercapai', (cfg->>'per_day')::int;
  end if;
  if (select count(*) from stickers where uploader_uid = p_uid and status = 'pending')
     >= (cfg->>'max_pending')::int then
    raise exception 'Masih ada % stiker menunggu review. Tunggu disetujui dulu ya', (cfg->>'max_pending')::int;
  end if;

  -- Kode publik 8 karakter (dipakai di pesan "[stiker:KODE]").
  for i in 1..10 loop
    v_code := (
      select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789',
                               1 + floor(random() * 57)::int, 1), '')
        from generate_series(1, 8)
    );
    exit when not exists (select 1 from stickers where code = v_code);
  end loop;

  v_path := v_id::text || '.' || v_ext;
  insert into stickers (id, code, uploader_uid, name, mime, staging_path, pack)
  values (v_id, v_code, p_uid, v_name, p_mime, v_path, v_pack);

  return jsonb_build_object('id', v_id, 'path', v_path, 'max_bytes', (cfg->>'max_bytes')::int);
end;
$$;

create or replace function public.sticker_my(p_uid text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'code', code, 'name', name, 'status', status, 'pack', pack,
           'path', case when status = 'approved' then public_path end,
           'reject_reason', reject_reason, 'created_at', created_at
         ) order by created_at desc), '[]'::jsonb)
    from (select * from stickers
           where uploader_uid = p_uid and status <> 'uploading'
           order by created_at desc limit 50) s;
$$;

create or replace function public.sticker_admin_list(p_actor text, p_status text, p_offset integer)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not public._sticker_is_reviewer(p_actor) then
    raise exception 'Kamu tidak punya akses';
  end if;
  if p_status not in ('pending', 'approved', 'rejected', 'removed') then
    raise exception 'Filter tidak valid';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', s.id, 'code', s.code, 'name', s.name, 'status', s.status, 'mime', s.mime, 'pack', s.pack,
             'size_bytes', s.size_bytes, 'staging_path', s.staging_path, 'path', s.public_path,
             'uploader_uid', s.uploader_uid,
             'uploader_name', coalesce(p.username, 'Pengguna'),
             'reject_reason', s.reject_reason, 'created_at', s.created_at
           ) order by s.created_at), '[]'::jsonb)
      from (select * from stickers where status = p_status
             order by case when p_status = 'pending' then created_at end asc,
                      created_at desc
             offset greatest(coalesce(p_offset, 0), 0) limit 30) s
      left join chat_profiles p on p.firebase_uid = s.uploader_uid
  );
end;
$$;

revoke all on function public.sticker_create_upload(text, text, text, text) from public, anon, authenticated;
grant execute on function public.sticker_create_upload(text, text, text, text) to service_role;

commit;
