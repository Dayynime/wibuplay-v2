# Deploy Nobar (server)

Dua bagian: SQL (tabel + fungsi) dan Edge Function `nobar-room`.
`nobar-room` memakai `_shared/wp.ts` (db + verifyUser) dan `turn.ts` milik
chess-game (disalin), jadi env TURN_SECRET / TURN_URLS yang sudah ada langsung dipakai.

## 1. Backup (di VPS)

```bash
mkdir -p ~/backup
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > ~/backup/db-sebelum-nobar-$(date +%F-%H%M).dump
tar czf ~/backup/functions-sebelum-nobar-$(date +%F-%H%M).tgz -C /home/zenime/supabase/docker/volumes functions
ls -lh ~/backup | tail -2
```

## 2. Kirim zip (di Termux HP)

```bash
scp ~/storage/downloads/nobar-server.zip zenime@202.155.17.171:~/
```

## 3. Pasang (di VPS)

```bash
unzip -o ~/nobar-server.zip -d ~/nobar
docker exec -i supabase-db psql -U postgres -d postgres < ~/nobar/nobar.sql

F=/home/zenime/supabase/docker/volumes/functions
mkdir -p $F/nobar-room
cp ~/nobar/index.ts $F/nobar-room/index.ts
cp $F/chess-game/turn.ts $F/nobar-room/turn.ts
cd /home/zenime/supabase/docker && docker compose restart functions
```

## 4. Cek

```bash
docker exec -i supabase-db psql -U postgres -d postgres -c "\dt public.nobar_*"
ls /home/zenime/supabase/docker/volumes/functions/nobar-room
curl -s -X POST https://supabase.zenime.biz.id/functions/v1/nobar-room -H "Content-Type: application/json" -d '{}'
docker logs --tail 30 supabase-edge-functions 2>&1 | grep -i "nobar\|error"
```

- Tabel: harus ada 3 (`nobar_rooms`, `nobar_members`, `nobar_bans`).
- Folder: harus ada `index.ts` dan `turn.ts`.
- curl tanpa login harus membalas JSON `{"error": ...}` (status 401), BUKAN
  "function not found" / error import. Artinya function sudah jalan.

## Rollback

```bash
rm -rf /home/zenime/supabase/docker/volumes/functions/nobar-room
cd /home/zenime/supabase/docker && docker compose restart functions
docker exec -i supabase-db psql -U postgres -d postgres -c "drop table if exists public.nobar_bans, public.nobar_members, public.nobar_rooms cascade; drop function if exists public.nobar_touch(uuid,text), public.nobar_join(uuid,text,integer), public.nobar_leave(uuid,text), public._nobar_fix_host(uuid);"
```

## Tambahan: undangan Nobar ke teman (nobar_invite.sql)

Cek dulu fungsi notif yang dipakai (harus ada, 6 argumen: text x5 + jsonb):

```bash
docker exec -i supabase-db psql -U postgres -d postgres -c "\df private.push_notify"
```

Lalu (setelah backup):

```bash
docker exec -i supabase-db psql -U postgres -d postgres < ~/nobar/nobar_invite.sql
cp ~/nobar/index.ts /home/zenime/supabase/docker/volumes/functions/nobar-room/index.ts
cd /home/zenime/supabase/docker && docker compose restart functions
```

Rollback bagian ini saja:

```bash
docker exec -i supabase-db psql -U postgres -d postgres -c "drop table if exists public.nobar_invites; drop function if exists public.nobar_notify(text,text,text,text,text,jsonb), public.nobar_close_invite_notif(uuid,boolean);"
```
