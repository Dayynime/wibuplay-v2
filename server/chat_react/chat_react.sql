-- =====================================================================
-- Reaksi emoji di pesan Chat Global & Chat Clan.
-- Satu orang = satu reaksi per pesan (pilih emoji lain = ganti, pilih emoji
-- yang sama = hapus). Emoji dibatasi ke daftar tetap.
-- Clan: hanya anggota clan pemilik pesan. User yang di-mute tidak bisa
-- memberi reaksi. Reaksi ikut terhapus saat pesannya dihapus.
-- Jalankan:  docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < chat_react.sql
-- =====================================================================
begin;

create table if not exists public.global_chat_reactions (
  message_id   bigint not null references public.global_chat_messages(id) on delete cascade,
  firebase_uid text not null,
  emoji        text not null,
  created_at   timestamptz not null default now(),
  primary key (message_id, firebase_uid)
);
create index if not exists global_chat_reactions_uid_idx on public.global_chat_reactions (firebase_uid, created_at);

create table if not exists public.clan_message_reactions (
  message_id   bigint not null references public.clan_messages(id) on delete cascade,
  firebase_uid text not null,
  emoji        text not null,
  created_at   timestamptz not null default now(),
  primary key (message_id, firebase_uid)
);
create index if not exists clan_message_reactions_uid_idx on public.clan_message_reactions (firebase_uid, created_at);

alter table public.global_chat_reactions enable row level security;
alter table public.clan_message_reactions enable row level security;
revoke all on public.global_chat_reactions, public.clan_message_reactions from anon, authenticated;
grant all on public.global_chat_reactions, public.clan_message_reactions to service_role;

create or replace function public._chat_react_emojis()
returns text[] language sql immutable as $$
  select array['👍', '😂', '❤️', '🔥', '😮', '😢'];
$$;

-- Ringkasan reaksi untuk sekumpulan pesan:
-- [{id, counts: {emoji: n}, mine: emoji|null}]
create or replace function public.chat_react_counts(p_uid text, p_channel text, p_ids bigint[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_clan text;
  v jsonb;
begin
  if p_channel = 'clan' then
    select clan_id into v_clan from clan_members where firebase_uid = p_uid;
    if v_clan is null then return '[]'::jsonb; end if;
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'counts', x.counts, 'mine', x.mine)), '[]'::jsonb)
      into v
    from (
      select r.message_id as id,
             jsonb_object_agg(r.emoji, r.n) as counts,
             max(r.mine) as mine
      from (
        select cr.message_id, cr.emoji, count(*) as n,
               max(case when cr.firebase_uid = p_uid then cr.emoji end) as mine
        from clan_message_reactions cr
        join clan_messages cm on cm.id = cr.message_id and cm.clan_id = v_clan
        where cr.message_id = any(p_ids[1:150])
        group by cr.message_id, cr.emoji
      ) r
      group by r.message_id
    ) x;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'counts', x.counts, 'mine', x.mine)), '[]'::jsonb)
      into v
    from (
      select r.message_id as id,
             jsonb_object_agg(r.emoji, r.n) as counts,
             max(r.mine) as mine
      from (
        select message_id, emoji, count(*) as n,
               max(case when firebase_uid = p_uid then emoji end) as mine
        from global_chat_reactions
        where message_id = any(p_ids[1:150])
        group by message_id, emoji
      ) r
      group by r.message_id
    ) x;
  end if;
  return v;
end;
$$;

-- Beri / ganti / hapus reaksi. p_emoji null = hapus. Return ringkasan pesan itu.
create or replace function public.chat_react_set(p_uid text, p_channel text, p_id bigint, p_emoji text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_clan text;
  v_recent int;
  m jsonb;
begin
  if p_emoji is not null and not (p_emoji = any(_chat_react_emojis())) then
    raise exception 'Reaksi tidak valid' using errcode = 'P0001';
  end if;
  if exists (select 1 from banned_accounts where firebase_uid = p_uid) then
    raise exception 'Akun kamu diblokir' using errcode = 'P0001';
  end if;
  if to_regprocedure('public.chat_mute_status(text)') is not null then
    m := chat_mute_status(p_uid);
    if coalesce((m ->> 'muted')::boolean, false) then
      raise exception '%', coalesce(m ->> 'message', 'Kamu sedang di-mute dari chat') using errcode = 'P0001';
    end if;
  end if;

  if p_channel = 'clan' then
    select clan_id into v_clan from clan_members where firebase_uid = p_uid;
    if v_clan is null or not exists (
      select 1 from clan_messages where id = p_id and clan_id = v_clan and deleted_at is null
    ) then
      raise exception 'Pesan tidak ditemukan' using errcode = 'P0001';
    end if;
    select count(*) into v_recent from clan_message_reactions
      where firebase_uid = p_uid and created_at > now() - interval '1 minute';
  elsif p_channel = 'global' then
    if not exists (select 1 from global_chat_messages where id = p_id) then
      raise exception 'Pesan tidak ditemukan' using errcode = 'P0001';
    end if;
    select count(*) into v_recent from global_chat_reactions
      where firebase_uid = p_uid and created_at > now() - interval '1 minute';
  else
    raise exception 'Channel tidak valid' using errcode = 'P0001';
  end if;

  if p_emoji is not null and v_recent >= 30 then
    raise exception 'Terlalu cepat, tunggu sebentar' using errcode = 'P0001';
  end if;

  if p_channel = 'clan' then
    if p_emoji is null then
      delete from clan_message_reactions where message_id = p_id and firebase_uid = p_uid;
    else
      insert into clan_message_reactions (message_id, firebase_uid, emoji) values (p_id, p_uid, p_emoji)
      on conflict (message_id, firebase_uid) do update set emoji = excluded.emoji, created_at = now();
    end if;
  else
    if p_emoji is null then
      delete from global_chat_reactions where message_id = p_id and firebase_uid = p_uid;
    else
      insert into global_chat_reactions (message_id, firebase_uid, emoji) values (p_id, p_uid, p_emoji)
      on conflict (message_id, firebase_uid) do update set emoji = excluded.emoji, created_at = now();
    end if;
  end if;

  return coalesce(chat_react_counts(p_uid, p_channel, array[p_id]) -> 0,
                  jsonb_build_object('id', p_id, 'counts', '{}'::jsonb, 'mine', null));
end;
$$;

revoke all on function public.chat_react_counts(text, text, bigint[]) from public, anon, authenticated;
revoke all on function public.chat_react_set(text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.chat_react_counts(text, text, bigint[]) to service_role;
grant execute on function public.chat_react_set(text, text, bigint, text) to service_role;

commit;
