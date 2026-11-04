# Deploy Stiker

## 1. Backup (VPS)
```bash
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > ~/backup/db-sebelum-stiker-$(date +%F-%H%M).dump
ls -lh ~/backup/db-sebelum-stiker-*
```

## 2. Pasang
```bash
mkdir -p ~/sticker && tar -xzf ~/sticker-server.tar.gz -C ~/sticker
docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < ~/sticker/sticker.sql
mkdir -p /home/zenime/supabase/docker/volumes/functions/sticker
cp ~/sticker/index.ts /home/zenime/supabase/docker/volumes/functions/sticker/index.ts
cd /home/zenime/supabase/docker && docker compose restart functions
```

## 3. Cek
```bash
curl -s -w "\nHTTP %{http_code}\n" -X POST https://supabase.zenime.biz.id/functions/v1/sticker -H "Content-Type: application/json" -d '{}'
curl -s -w "\nHTTP %{http_code}\n" "https://supabase.zenime.biz.id/rest/v1/sticker_catalog?select=code&limit=1" -H "apikey: <ANON_KEY>"
docker exec supabase-db psql -U postgres -d postgres -c "select id, public, file_size_limit from storage.buckets where id like 'sticker%';"
```
- curl pertama: `{"error":"Kamu harus login dulu"}` HTTP 401
- curl kedua: `[]` HTTP 200
- 2 bucket: sticker-staging (f) dan stickers (t)

## Ubah aturan
Edit `public._sticker_cfg()` di sticker.sql (max_bytes, per_day, max_pending) lalu jalankan ulang SQL-nya.
Reviewer = role `developer` dan `admin` (fungsi `_sticker_is_reviewer`).

## Rollback
```bash
rm -rf /home/zenime/supabase/docker/volumes/functions/sticker
cd /home/zenime/supabase/docker && docker compose restart functions
docker exec -i supabase-db psql -U postgres -d postgres -c "drop view if exists public.sticker_catalog; drop function if exists public.sticker_create_upload(text,text,text), public.sticker_mark_uploaded(text,uuid,integer), public.sticker_discard(text,uuid), public.sticker_my(text), public.sticker_admin_list(text,text,integer), public.sticker_admin_review(text,uuid,text,text,text), public._sticker_is_reviewer(text), public._sticker_cfg(); drop table if exists public.stickers;"
```
(Bucket & file stiker dibiarkan; hapus manual kalau perlu.)
