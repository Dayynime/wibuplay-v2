# Deploy Nobar (server)

Dua bagian: SQL (tabel + fungsi) dan Edge Function `nobar-room`.
Semua perintah dijalankan dari Termux, SSH ke `zenime@202.155.17.171`.

## 0. Backup dulu

```bash
cd ~
mkdir -p ~/backup
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > ~/backup/db-sebelum-nobar-$(date +%F-%H%M).dump
tar czf ~/backup/functions-sebelum-nobar-$(date +%F-%H%M).tgz -C /home/zenime/supabase/docker/volumes functions
ls -lh ~/backup | tail -3
```

## 1. Cek nama env TURN yang dipakai chess-game

Voice nobar memakai server TURN yang sama dengan voice catur.

```bash
grep -n "Deno.env.get" /home/zenime/supabase/docker/volumes/functions/chess-game/index.ts
```

Function `nobar-room` membaca `TURN_URLS` (dipisah koma) dan `TURN_SECRET`
(static-auth-secret coturn). Kalau chess-game pakai nama lain atau format
kredensial lain, samakan bagian `TURN_*` dan fungsi `turnCredentials()` di
`index.ts` sebelum deploy. Tanpa TURN, voice tetap jalan di WiFi, tapi bisa
gagal di data seluler (app akan memberi tahu).

## 2. Jalankan SQL

```bash
unzip -o nobar-server.zip -d ~/nobar
docker exec -i supabase-db psql -U postgres -d postgres < ~/nobar/nobar.sql
```

Cek:

```bash
docker exec -i supabase-db psql -U postgres -d postgres -c "\dt public.nobar_*"
```

## 3. Pasang Edge Function

```bash
mkdir -p /home/zenime/supabase/docker/volumes/functions/nobar-room
cp ~/nobar/index.ts /home/zenime/supabase/docker/volumes/functions/nobar-room/index.ts
cd /home/zenime/supabase/docker && docker compose restart functions
```

## 4. Tes cepat

```bash
docker logs --tail 50 supabase-edge-functions 2>&1 | grep -i nobar
```

Lalu dari app: buka anime, tekan **Nobar** di bawah video. Kalau muncul
"Server bermasalah", lihat log di atas.

## Rollback

```bash
rm -rf /home/zenime/supabase/docker/volumes/functions/nobar-room
cd /home/zenime/supabase/docker && docker compose restart functions
docker exec -i supabase-db psql -U postgres -d postgres -c "drop table if exists public.nobar_bans, public.nobar_members, public.nobar_rooms cascade; drop function if exists public.nobar_touch(uuid,text), public.nobar_join(uuid,text,integer), public.nobar_leave(uuid,text), public._nobar_fix_host(uuid);"
```

## Catatan

- Import di `index.ts` memakai `npm:@supabase/supabase-js@2` dan `npm:jose@5`.
  Kalau function lain di VPS memakai cara import berbeda (mis. lewat
  `_shared/wp.ts`), samakan saja; logika verifikasi tokennya sama
  (JWKS dari tabel `public.firebase_jwks`).
- Ping ke app dikirim lewat `POST $SUPABASE_URL/realtime/v1/api/broadcast`.
  Kalau gagal, app tetap memuat ulang data room tiap 30 detik.
