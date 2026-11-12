-- =====================================================================
-- Bio profil: teks singkat (maks 150 karakter, maks 4 baris) di profil.
-- Disimpan di kolom baru chat_profiles.bio (nullable, tidak mengganggu
-- Zenime/kolom lain). Dibaca publik lewat REST (sama seperti username);
-- ditulis HANYA lewat Edge Function `profile-bio` (UID dari Firebase token).
-- Jalankan:  docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < profile_bio.sql
-- =====================================================================
begin;

alter table public.chat_profiles add column if not exists bio text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'chat_profiles_bio_len' and conrelid = 'public.chat_profiles'::regclass
  ) then
    alter table public.chat_profiles
      add constraint chat_profiles_bio_len check (bio is null or char_length(bio) <= 150);
  end if;
end $$;

-- Kalau hak baca chat_profiles diatur per kolom, kolom baru perlu izin sendiri.
grant select (bio) on public.chat_profiles to anon, authenticated;

-- Simpan bio milik p_uid. Kosong = hapus bio. Mengembalikan bio yang tersimpan.
create or replace function public.profile_bio_set(p_uid text, p_bio text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v text;
begin
  v := coalesce(p_bio, '');
  -- Rapikan: CRLF -> LF, spasi di ujung baris dibuang, maks 1 baris kosong beruntun.
  v := replace(v, E'\r', '');
  v := regexp_replace(v, E'[ \t]+\n', E'\n', 'g');
  v := regexp_replace(v, E'\n{3,}', E'\n\n', 'g');
  v := btrim(v, E' \t\n');
  if char_length(v) > 150 then
    raise exception 'Bio maksimal 150 karakter' using errcode = 'P0001';
  end if;
  if array_length(string_to_array(v, E'\n'), 1) > 4 then
    raise exception 'Bio maksimal 4 baris' using errcode = 'P0001';
  end if;
  update chat_profiles set bio = nullif(v, '') where firebase_uid = p_uid;
  if not found then
    raise exception 'Profil belum ada, buka Chat atau Profil dulu' using errcode = 'P0001';
  end if;
  return nullif(v, '');
end;
$$;

revoke all on function public.profile_bio_set(text, text) from public, anon, authenticated;
grant execute on function public.profile_bio_set(text, text) to service_role;

commit;
