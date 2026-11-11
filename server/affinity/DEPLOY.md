# Deploy Afinitas

## 0. Cek dulu (tidak mengubah apa pun)
Pastikan tabel & kolom yang dipakai trigger poin memang ada:
```bash
docker exec -i supabase-db psql -U postgres -d postgres -c "
select table_name, string_agg(column_name, ', ' order by column_name) as kolom
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('private_messages','chess_games','nobar_members','global_chat_messages','user_last_seen','friendships','chat_profiles','banned_accounts','notifications')
   and column_name in ('sender_uid','recipient_uid','white_uid','black_uid','status','ply','room_id','firebase_uid','last_seen',
                       'gift_days','gift_recipient_uid','requester_uid','addressee_uid','username','avatar_url','user_number','type','data','read_at')
 group by table_name order by table_name;"
docker exec -i supabase-db psql -U postgres -d postgres -c "\df private.push_notify"
```
Yang harus muncul:

| Tabel | Kolom |
|---|---|
| banned_accounts | firebase_uid |
| chat_profiles | avatar_url, firebase_uid, user_number, username |
| chess_games | black_uid, ply, status, white_uid |
| friendships | addressee_uid, requester_uid, status |
| global_chat_messages | firebase_uid, gift_days, gift_recipient_uid |
| nobar_members | firebase_uid, last_seen, room_id |
| notifications | data, read_at, type |
| private_messages | recipient_uid, sender_uid |
| user_last_seen | firebase_uid, last_seen |

`private.push_notify` juga harus ada. Kalau ada yang beda, kirim hasilnya dulu sebelum lanjut.

## 1. Backup (VPS)
```bash
mkdir -p ~/backup
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > ~/backup/db-sebelum-afinitas-$(date +%F-%H%M).dump
ls -lh ~/backup/db-sebelum-afinitas-*
```

## 2. Pasang
```bash
unzip -o ~/afinitas-server.zip -d ~/affinity
docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < ~/affinity/affinity.sql
mkdir -p /home/zenime/supabase/docker/volumes/functions/affinity
cp ~/affinity/index.ts /home/zenime/supabase/docker/volumes/functions/affinity/index.ts
cd /home/zenime/supabase/docker && docker compose restart functions
curl -s -X POST https://supabase.zenime.biz.id/functions/v1/affinity -H "Content-Type: application/json" -d '{}'; echo
```
Harus membalas `{"error":"Kamu harus login dulu"}`.

Cek trigger poin terpasang (harus 6 baris):
```bash
docker exec -i supabase-db psql -U postgres -d postgres -c "select tgname, tgrelid::regclass from pg_trigger where tgname like 'trg_aff_%' order by 1;"
```

## Ubah angka
Edit fungsi `public._aff_cfg()` di affinity.sql (slot, batas level, poin, batas harian,
bonus jenis, kedaluwarsa, cooldown, penurunan poin) lalu jalankan ulang SQL-nya.

## Audit
```sql
select type, count(*) from public.affinities group by type;
select * from public.affinity_requests order by created_at desc limit 30;
select * from public.affinity_points_log where day = (now() at time zone 'Asia/Jakarta')::date order by points desc limit 30;
```

## Rollback
```bash
rm -rf /home/zenime/supabase/docker/volumes/functions/affinity
cd /home/zenime/supabase/docker && docker compose restart functions
docker exec -i supabase-db psql -U postgres -d postgres -c "
drop trigger if exists trg_aff_private_message on public.private_messages;
drop trigger if exists trg_aff_chess on public.chess_games;
drop trigger if exists trg_aff_nobar on public.nobar_members;
drop trigger if exists trg_aff_gift on public.global_chat_messages;
drop trigger if exists trg_aff_online on public.user_last_seen;
drop trigger if exists trg_aff_friendship_end on public.friendships;
drop table if exists public.affinity_moments, public.affinity_points_log, public.affinity_requests, public.affinities cascade;"
```
Atau pulihkan backup dari langkah 1.
