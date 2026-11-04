-- Clan yang tidak ikut leaderboard (mis. clan khusus admin).
-- Kolom baru default false: semua clan lama tetap ikut leaderboard.
alter table public.clans
  add column if not exists leaderboard_hidden boolean not null default false;
