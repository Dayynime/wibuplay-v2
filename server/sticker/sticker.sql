-- =====================================================================
-- Stiker buatan user (upload khusus Premium, wajib disetujui developer/admin).
--
-- Alur: sign (cek premium + kuota, buat path) -> upload ke bucket PRIVAT
-- sticker-staging lewat signed URL -> register (server cek file) -> antrean
-- review -> approve: file disalin ke bucket publik `stickers` & tampil di
-- katalog untuk semua user.
--
-- Stiker dikirim di chat/komentar sebagai teks "[stiker:KODE]" lewat fungsi
-- chat yang sudah ada (rate limit, ban, pertemanan tetap berlaku). App hanya
-- merender kode yang ada di katalog (status approved).
--
-- Hanya service_role (Edge Function `sticker`) yang boleh memanggil fungsi.
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < sticker.sql
-- =====================================================================

begin;

create table if not exists public.stickers (
  id            uuid        primary key default gen_random_uuid(),
  code          text        not null unique check (code ~ '^[A-Za-z0-9]{8}$'),
  uploader_uid  text        not null,
  name          text        not null check (char_length(name) between 1 and 30),
  mime          text        not null check (mime in ('image/png', 'image/webp', 'image/gif', 'image/jpeg')),
  size_bytes    integer,
  status        text        not null default 'uploading'
                check (status in ('uploading', 'pending', 'approved', 'rejected', 'removed')),
  staging_path  text        not null,
  public_path   text,
  reject_reason text,
  reviewed_by   text,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists stickers_status_idx   on public.stickers (status, created_at);
create index if not exists stickers_uploader_idx on public.stickers (uploader_uid, created_at desc);

alter table public.stickers enable row level security;
revoke all on public.stickers from anon, authenticated;
grant all on public.stickers to service_role;

-- Katalog publik: hanya stiker yang disetujui.
create or replace view public.sticker_catalog as
  select code, name, public_path as path, reviewed_at as approved_at
    from public.stickers
   where status = 'approved' and public_path is not null;
revoke all on public.sticker_catalog from public;
grant select on public.sticker_catalog to anon, authenticated, service_role;

-- Bucket: staging privat (menunggu review) & publik (sudah disetujui). Maks 1 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('sticker-staging', 'sticker-staging', false, 1048576, array['image/png','image/webp','image/gif','image/jpeg']),
  ('stickers',        'stickers',        true,  1048576, array['image/png','image/webp','image/gif','image/jpeg'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Pengaturan
-- ---------------------------------------------------------------------
create or replace function public._sticker_cfg()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'max_bytes',     1048576,  -- 1 MB
    'per_day',       5,        -- upload per 24 jam per akun
    'max_pending',   10        -- stiker menunggu review per akun
  );
$$;

create or replace function public._sticker_is_reviewer(p_uid text)
returns boolean language sql stable set search_path = public as $$
  select exists (select 1 from user_roles where firebase_uid = p_uid and role in ('developer', 'admin'));
$$;

-- ---------------------------------------------------------------------
-- Upload: buat baris + path staging. Return {id, path}
-- ---------------------------------------------------------------------
create or replace function public.sticker_create_upload(p_uid text, p_name text, p_mime text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg    jsonb := public._sticker_cfg();
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
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
  insert into stickers (id, code, uploader_uid, name, mime, staging_path)
  values (v_id, v_code, p_uid, v_name, p_mime, v_path);

  return jsonb_build_object('id', v_id, 'path', v_path, 'max_bytes', (cfg->>'max_bytes')::int);
end;
$$;

-- File sudah diupload & dicek Edge Function -> masuk antrean review.
create or replace function public.sticker_mark_uploaded(p_uid text, p_id uuid, p_size integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_size is null or p_size < 1 or p_size > (public._sticker_cfg()->>'max_bytes')::int then
    raise exception 'Ukuran file maksimal 1 MB';
  end if;
  update stickers set status = 'pending', size_bytes = p_size
   where id = p_id and uploader_uid = p_uid and status = 'uploading';
  if not found then
    raise exception 'Upload tidak ditemukan atau sudah diproses';
  end if;
end;
$$;

-- File tidak lolos cek -> baris dibuang (kuota harian tetap terpakai).
create or replace function public.sticker_discard(p_uid text, p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update stickers set status = 'rejected', reject_reason = 'File tidak valid'
   where id = p_id and uploader_uid = p_uid and status = 'uploading';
$$;

-- Stiker milik user (terbaru dulu).
create or replace function public.sticker_my(p_uid text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'code', code, 'name', name, 'status', status,
           'path', case when status = 'approved' then public_path end,
           'reject_reason', reject_reason, 'created_at', created_at
         ) order by created_at desc), '[]'::jsonb)
    from (select * from stickers
           where uploader_uid = p_uid and status <> 'uploading'
           order by created_at desc limit 50) s;
$$;

-- ---------------------------------------------------------------------
-- Admin (developer & admin)
-- ---------------------------------------------------------------------
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
             'id', s.id, 'code', s.code, 'name', s.name, 'status', s.status, 'mime', s.mime,
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

-- p_action: approve (pending -> approved, butuh p_public_path) | reject | remove (approved -> removed)
-- Return baris sebelum diubah (Edge Function butuh path untuk hapus file).
create or replace function public.sticker_admin_review(
  p_actor text, p_id uuid, p_action text, p_reason text, p_public_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  s public.stickers;
  v_reason text := nullif(btrim(left(coalesce(p_reason, ''), 120)), '');
begin
  if not public._sticker_is_reviewer(p_actor) then
    raise exception 'Kamu tidak punya akses';
  end if;

  select * into s from stickers where id = p_id for update;
  if not found then
    raise exception 'Stiker tidak ditemukan';
  end if;

  if p_action = 'approve' then
    if s.status <> 'pending' then raise exception 'Stiker ini sudah diproses'; end if;
    if p_public_path is null or p_public_path !~ '^[A-Za-z0-9]{8}\.(png|webp|gif|jpg)$' then
      raise exception 'Path stiker tidak valid';
    end if;
    update stickers set status = 'approved', public_path = p_public_path, reject_reason = null,
                        reviewed_by = p_actor, reviewed_at = now()
     where id = p_id;
    perform private.push_notify(
      s.uploader_uid, p_actor, 'sticker_reviewed',
      'Stiker kamu disetujui! 🎉',
      'Stiker "' || s.name || '" sekarang bisa dipakai semua orang.',
      jsonb_build_object('sticker_id', s.id, 'code', s.code, 'status', 'approved')
    );
  elsif p_action = 'reject' then
    if s.status <> 'pending' then raise exception 'Stiker ini sudah diproses'; end if;
    update stickers set status = 'rejected', reject_reason = v_reason,
                        reviewed_by = p_actor, reviewed_at = now()
     where id = p_id;
    perform private.push_notify(
      s.uploader_uid, p_actor, 'sticker_reviewed',
      'Stiker kamu ditolak',
      'Stiker "' || s.name || '" ditolak' || coalesce(': ' || v_reason, '.'),
      jsonb_build_object('sticker_id', s.id, 'status', 'rejected')
    );
  elsif p_action = 'remove' then
    if s.status <> 'approved' then raise exception 'Hanya stiker aktif yang bisa diturunkan'; end if;
    update stickers set status = 'removed', reject_reason = v_reason,
                        reviewed_by = p_actor, reviewed_at = now()
     where id = p_id;
  else
    raise exception 'Aksi tidak dikenal';
  end if;

  return jsonb_build_object('code', s.code, 'mime', s.mime,
                            'staging_path', s.staging_path, 'public_path', s.public_path);
end;
$$;

revoke all on function public._sticker_cfg()                                    from public, anon, authenticated;
revoke all on function public._sticker_is_reviewer(text)                        from public, anon, authenticated;
revoke all on function public.sticker_create_upload(text, text, text)           from public, anon, authenticated;
revoke all on function public.sticker_mark_uploaded(text, uuid, integer)        from public, anon, authenticated;
revoke all on function public.sticker_discard(text, uuid)                       from public, anon, authenticated;
revoke all on function public.sticker_my(text)                                  from public, anon, authenticated;
revoke all on function public.sticker_admin_list(text, text, integer)           from public, anon, authenticated;
revoke all on function public.sticker_admin_review(text, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.sticker_create_upload(text, text, text)           to service_role;
grant execute on function public.sticker_mark_uploaded(text, uuid, integer)        to service_role;
grant execute on function public.sticker_discard(text, uuid)                       to service_role;
grant execute on function public.sticker_my(text)                                  to service_role;
grant execute on function public.sticker_admin_list(text, text, integer)           to service_role;
grant execute on function public.sticker_admin_review(text, uuid, text, text, text) to service_role;

commit;
