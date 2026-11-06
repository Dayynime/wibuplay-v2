-- =====================================================================
-- Chat: notifikasi pesan pribadi + jumlah belum dibaca (tab Teman & Clan).
--   * Trigger kirim notif (push) ke penerima tiap pesan pribadi baru.
--     Lewat private.push_notify -> ikut aturan anti-spam yang sudah ada.
--   * clan_chat_reads: kapan user terakhir membuka chat clan.
--   * chat_unread_counts(uid)  -> {private, clan} (maks 99+)
--   * clan_chat_mark_read(uid) -> tandai chat clan sudah dibaca
-- Hanya service_role (Edge Function `chat-unread`) yang bisa memanggil.
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < chat_unread.sql
-- =====================================================================
begin;

create table if not exists public.clan_chat_reads (
  firebase_uid text        primary key,
  clan_id      uuid        not null,
  last_read_at timestamptz not null default now()
);
alter table public.clan_chat_reads enable row level security;
revoke all on public.clan_chat_reads from anon, authenticated;
grant all on public.clan_chat_reads to service_role;

create index if not exists private_messages_unread_idx
  on public.private_messages (recipient_uid) where read_at is null;
create index if not exists clan_messages_clan_created_idx
  on public.clan_messages (clan_id, created_at);

-- ---------------------------------------------------------------------
create or replace function public.chat_unread_counts(p_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_priv int := 0;
  v_clan int := 0;
  m record;
  r public.clan_chat_reads;
begin
  select count(*) into v_priv from (
    select 1 from private_messages
     where recipient_uid = p_uid and read_at is null
       and not exists (select 1 from banned_accounts b where b.firebase_uid = sender_uid)
     limit 100) x;

  select clan_id, joined_at into m from clan_members where firebase_uid = p_uid;
  if found then
    select * into r from clan_chat_reads where firebase_uid = p_uid;
    if r.firebase_uid is null or r.clan_id <> m.clan_id then
      -- Pertama kali / pindah clan: mulai hitung dari sekarang (tidak 99+ mendadak).
      insert into clan_chat_reads (firebase_uid, clan_id, last_read_at)
      values (p_uid, m.clan_id, now())
      on conflict (firebase_uid) do update set clan_id = excluded.clan_id, last_read_at = excluded.last_read_at;
    else
      select count(*) into v_clan from (
        select 1 from clan_messages
         where clan_id = m.clan_id and deleted_at is null and firebase_uid <> p_uid
           and created_at > greatest(r.last_read_at, coalesce(m.joined_at, '-infinity'::timestamptz))
         limit 100) y;
    end if;
  end if;

  return jsonb_build_object('private', v_priv, 'clan', v_clan);
end;
$$;

create or replace function public.clan_chat_mark_read(p_uid text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into clan_chat_reads (firebase_uid, clan_id, last_read_at)
  select p_uid, clan_id, now() from clan_members where firebase_uid = p_uid
  on conflict (firebase_uid) do update set clan_id = excluded.clan_id, last_read_at = excluded.last_read_at;
$$;

revoke all on function public.chat_unread_counts(text)  from public, anon, authenticated;
revoke all on function public.clan_chat_mark_read(text) from public, anon, authenticated;
grant execute on function public.chat_unread_counts(text)  to service_role;
grant execute on function public.clan_chat_mark_read(text) to service_role;

-- ---------------------------------------------------------------------
-- Notif pesan pribadi. Gagal kirim notif TIDAK pernah menggagalkan pesan.
-- ---------------------------------------------------------------------
create or replace function private.trg_private_message_notify()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_name text;
  v_body text;
begin
  select username into v_name from chat_profiles where firebase_uid = new.sender_uid;
  v_body := case
    when new.message ~ '^\s*\[stiker:[A-Za-z0-9]{8}\]\s*$' then '🖼️ Stiker'
    when new.message ~ 'Kode room catur:' then '♟️ Mengajakmu main catur'
    else left(regexp_replace(new.message, '\s+', ' ', 'g'), 120)
  end;
  begin
    perform private.push_notify(
      new.recipient_uid, new.sender_uid, 'private_message',
      coalesce(nullif(v_name, ''), 'Teman') || ' 💬',
      v_body,
      jsonb_build_object('sender_uid', new.sender_uid, 'message_id', new.id)
    );
  exception when others then
    raise warning 'private_message notify gagal: %', sqlerrm;
  end;
  return null;
end;
$$;

drop trigger if exists trg_private_message_notify on public.private_messages;
create trigger trg_private_message_notify
  after insert on public.private_messages
  for each row execute function private.trg_private_message_notify();

commit;
