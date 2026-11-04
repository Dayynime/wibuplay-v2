# Deploy Akses Clan (mode join, level minimal, undangan)

## 1. Backup (VPS)
```bash
mkdir -p ~/backup
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > ~/backup/db-sebelum-clan-access-$(date +%F-%H%M).dump
# Simpan definisi submit_join_request yang lama (buat rollback):
docker exec supabase-db psql -U postgres -d postgres -tA -c "select pg_get_functiondef('public.submit_join_request(text,uuid)'::regprocedure) || ';'" > ~/backup/submit_join_request-lama.sql
ls -lh ~/backup/db-sebelum-clan-access-* ~/backup/submit_join_request-lama.sql
```

## 2. Pasang
```bash
mkdir -p ~/clan_access && tar -xzf ~/clan-access-server.tar.gz -C ~/clan_access
docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < ~/clan_access/clan_access.sql
mkdir -p /home/zenime/supabase/docker/volumes/functions/clan-access
cp ~/clan_access/index.ts /home/zenime/supabase/docker/volumes/functions/clan-access/index.ts
cd /home/zenime/supabase/docker && docker compose restart functions
curl -s -X POST https://supabase.zenime.biz.id/functions/v1/clan-access -H "Content-Type: application/json" -d '{}'; echo
```
Harus membalas `{"error":"Kamu harus login dulu"}`.

Semua clan lama otomatis `approval` (Butuh Persetujuan) + level minimal 1,
jadi perilakunya sama seperti sebelumnya sampai leader mengubahnya.

## 3. Cek
```bash
docker exec supabase-db psql -U postgres -d postgres -c "select join_mode, min_level, count(*) from public.clans group by 1,2;"
```

## Rollback
```bash
docker exec -i supabase-db psql -U postgres -d postgres < ~/backup/submit_join_request-lama.sql
rm -rf /home/zenime/supabase/docker/volumes/functions/clan-access
cd /home/zenime/supabase/docker && docker compose restart functions
docker exec -i supabase-db psql -U postgres -d postgres -c "drop function if exists public.update_clan_access(text,uuid,text,integer), public.clan_invite(text,uuid,text), public.clan_invite_respond(text,uuid,boolean), public.clan_my_invites(text); drop table if exists public.clan_invites; alter table public.clans drop column if exists join_mode, drop column if exists min_level;"
```
