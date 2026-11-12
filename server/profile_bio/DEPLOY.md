# Deploy Bio Profil

## 1. Backup (VPS)
```bash
mkdir -p ~/backup
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > ~/backup/db-sebelum-profile-bio-$(date +%F-%H%M).dump
ls -lh ~/backup/db-sebelum-profile-bio-*
```

## 2. Pasang
```bash
unzip -o ~/profile-bio-server.zip -d ~/profile_bio
docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < ~/profile_bio/profile_bio.sql
mkdir -p /home/zenime/supabase/docker/volumes/functions/profile-bio
cp ~/profile_bio/index.ts /home/zenime/supabase/docker/volumes/functions/profile-bio/index.ts
cd /home/zenime/supabase/docker && docker compose restart functions
curl -s -X POST https://supabase.zenime.biz.id/functions/v1/profile-bio -H "Content-Type: application/json" -d '{}'; echo
```
Harus membalas `{"error":"Kamu harus login dulu"}`.

Cek kolom kebaca publik (harus balas `[...]`, bukan error):
```bash
curl -s "https://supabase.zenime.biz.id/rest/v1/chat_profiles?select=firebase_uid,bio&limit=1" -H "apikey: <ANON_KEY>"; echo
```

## Tes di app
1. Isi bio di Edit Profil, simpan, bio muncul di profil sendiri dan profil publik.
2. Ganti username / foto lalu cek bio **masih ada**. Edge Function
   `chat-save-profile` tidak ada di repo ini; kalau ternyata dia menimpa semua
   kolom (bio jadi kosong), kabari supaya diperbaiki di sana.

## Audit
```sql
select firebase_uid, username, bio from public.chat_profiles where bio is not null order by firebase_uid limit 50;
```

## Rollback
```bash
rm -rf /home/zenime/supabase/docker/volumes/functions/profile-bio
cd /home/zenime/supabase/docker && docker compose restart functions
docker exec -i supabase-db psql -U postgres -d postgres -c "drop function if exists public.profile_bio_set(text, text); alter table public.chat_profiles drop constraint if exists chat_profiles_bio_len; alter table public.chat_profiles drop column if exists bio;"
```
App tetap aman walau kolom belum/tidak ada: bio diambil dengan query terpisah,
kalau gagal bio cuma tidak tampil (profil lain tetap jalan).
