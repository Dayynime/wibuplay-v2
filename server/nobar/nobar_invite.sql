-- =====================================================================
-- Undangan Nobar ke teman (notif lonceng + push lewat private.push_notify).
-- Jalankan SETELAH nobar.sql:
--   docker exec -i supabase-db psql -U postgres -d postgres < nobar_invite.sql
-- =====================================================================

create table if not exists public.nobar_invites (
  id            uuid primary key default gen_random_uuid(),
  room_id       uuid not null references public.nobar_rooms(id) on delete cascade,
  from_uid      text not null,
  to_uid        text not null,
  status        text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz
);
create index if not exists nobar_invites_to_idx   on public.nobar_invites (to_uid, created_at desc);
create index if not exists nobar_invites_room_idx on public.nobar_invites (room_id, to_uid);

alter table public.nobar_invites enable row level security;
revoke all on public.nobar_invites from anon, authenticated;
grant all on public.nobar_invites to service_role;

-- Kirim notif (lonceng + push) lewat jalur yang sama dengan notif teman/clan.
create or replace function public.nobar_notify(
  p_to text, p_from text, p_type text, p_title text, p_body text, p_data jsonb
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  perform private.push_notify(p_to, p_from, p_type, p_title, p_body, p_data);
end;
$$;

-- Tandai notif undangan sudah dibaca (dijawab) atau kedaluwarsa.
create or replace function public.nobar_close_invite_notif(p_invite uuid, p_expired boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications
     set read_at = coalesce(read_at, now()),
         data = case when p_expired then data || '{"expired": true}'::jsonb else data end
   where type = 'nobar_invite' and data->>'invite_id' = p_invite::text;
end;
$$;

revoke all on function public.nobar_notify(text, text, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.nobar_close_invite_notif(uuid, boolean)          from public, anon, authenticated;
grant execute on function public.nobar_notify(text, text, text, text, text, jsonb) to service_role;
grant execute on function public.nobar_close_invite_notif(uuid, boolean)          to service_role;
