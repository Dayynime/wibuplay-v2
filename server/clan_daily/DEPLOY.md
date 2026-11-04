# Deploy Daily Clan

## 1. Backup (VPS)
```bash
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > ~/backup/db-sebelum-clan-daily-$(date +%F-%H%M).dump
ls -lh ~/backup/db-sebelum-clan-daily-*
```

## 2. Pasang
```bash
unzip -o ~/clan-daily-server.zip -d ~/clan_daily
docker exec -i supabase-db psql -U postgres -d postgres < ~/clan_daily/clan_daily.sql
mkdir -p /home/zenime/supabase/docker/volumes/functions/clan-daily
cp ~/clan_daily/index.ts /home/zenime/supabase/docker/volumes/functions/clan-daily/index.ts
cd /home/zenime/supabase/docker && docker compose restart functions
curl -s -X POST https://supabase.zenime.biz.id/functions/v1/clan-daily -H "Content-Type: application/json" -d '{}'; echo
```
Harus membalas `{"error":"Kamu harus login dulu"}`.

## Ubah angka
Edit fungsi `public._clan_daily_cfg()` di clan_daily.sql (base, step, max_days,
bonus, bonus_pct, bonus_min_members, min_account_days) lalu jalankan ulang SQL-nya.

## Audit
```sql
select firebase_uid, day, streak, reward, bonus_reward from public.clan_daily_checkins order by created_at desc limit 50;
select * from public.coin_transactions where metadata->>'source' in ('clan_daily','clan_daily_bonus') order by created_at desc limit 50;
```

## Rollback
```bash
rm -rf /home/zenime/supabase/docker/volumes/functions/clan-daily
cd /home/zenime/supabase/docker && docker compose restart functions
docker exec -i supabase-db psql -U postgres -d postgres -c "drop function if exists public.clan_daily_state(text), public.clan_daily_checkin(text), public.clan_daily_bonus(text), public._clan_daily_cfg(), public._clan_daily_today(), public._clan_daily_day_start(date); drop table if exists public.clan_daily_checkins;"
```
(ZCoin yang sudah masuk tetap tercatat di coin_transactions.)
