-- =====================================================================
-- Chat nobar: pesan teks per room (disimpan, anggota baru bisa lihat
-- 50 pesan terakhir). Ikut terhapus saat room dihapus (cascade).
-- Hanya service_role (Edge Function nobar-room) yang bisa akses.
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < nobar_chat.sql
-- =====================================================================
begin;

create table if not exists public.nobar_messages (
  id           bigserial   primary key,
  room_id      uuid        not null references public.nobar_rooms(id) on delete cascade,
  firebase_uid text        not null,
  message      text        not null check (char_length(message) between 1 and 300),
  created_at   timestamptz not null default now()
);
create index if not exists nobar_messages_room_idx on public.nobar_messages (room_id, id);
create index if not exists nobar_messages_rate_idx on public.nobar_messages (room_id, firebase_uid, created_at);

alter table public.nobar_messages enable row level security;
revoke all on public.nobar_messages from anon, authenticated;
grant all on public.nobar_messages to service_role;
grant usage, select on sequence public.nobar_messages_id_seq to service_role;

commit;
