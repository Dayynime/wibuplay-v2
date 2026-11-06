-- =====================================================================
-- Mention @teman di Chat Global & Chat Clan -> notifikasi (push).
-- Aturan:
--   * pesan harus milik pengirim & masih baru (< 10 menit)
--   * yang di-mention WAJIB teman (friendships accepted)
--   * Chat Clan: yang di-mention harus anggota clan yang sama
--   * teks pesan harus memuat "@<username>" orang itu
--   * maks 5 orang per pesan; notif lewat private.push_notify (anti-spam bawaan)
-- Sekalian: perbaikan perbandingan clan_id di clan_giveaway_check_claim
-- (clan_members.clan_id bisa bertipe uuid).
-- Jalankan:  docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < chat_mention.sql
-- =====================================================================
begin;

create or replace function public.chat_mention_notify(p_uid text, p_channel text, p_message_id bigint, p_targets text[])
returns int language plpgsql security definer set search_path = public as $$
declare
  v_text text;
  v_clan text;
  v_sender text;
  v_target text;
  v_name text;
  v_body text;
  v_sent int := 0;
begin
  if p_channel = 'clan' then
    select message, clan_id::text into v_text, v_clan
      from clan_messages
     where id = p_message_id and firebase_uid = p_uid and deleted_at is null
       and created_at > now() - interval '10 minutes';
  elsif p_channel = 'global' then
    select message into v_text
      from global_chat_messages
     where id = p_message_id and firebase_uid = p_uid
       and created_at > now() - interval '10 minutes';
  else
    raise exception 'Channel tidak valid' using errcode = 'P0001';
  end if;
  if v_text is null then return 0; end if;

  select nullif(btrim(username), '') into v_sender from chat_profiles where firebase_uid = p_uid;
  v_body := left(regexp_replace(v_text, '\s+', ' ', 'g'), 120);

  for v_target in
    select distinct t from unnest(coalesce(p_targets, '{}')) t where t is not null and t <> p_uid limit 5
  loop
    -- wajib teman
    if not exists (
      select 1 from friendships
       where status = 'accepted'
         and ((requester_uid = p_uid and addressee_uid = v_target)
           or (requester_uid = v_target and addressee_uid = p_uid))
    ) then
      continue;
    end if;
    -- chat clan: harus anggota clan yang sama
    if p_channel = 'clan' and not exists (
      select 1 from clan_members where firebase_uid = v_target and clan_id::text = v_clan
    ) then
      continue;
    end if;
    -- teks harus benar-benar menyebut @username orang itu
    select nullif(btrim(username), '') into v_name from chat_profiles where firebase_uid = v_target;
    if v_name is null or position(lower('@' || v_name) in lower(v_text)) = 0 then
      continue;
    end if;
    begin
      perform private.push_notify(
        v_target, p_uid, 'chat_mention',
        coalesce(v_sender, 'Temanmu') || ' menyebutmu di ' || case when p_channel = 'clan' then 'Chat Clan' else 'Chat Global' end,
        v_body,
        jsonb_build_object('channel', p_channel, 'message_id', p_message_id, 'sender_uid', p_uid)
      );
      v_sent := v_sent + 1;
    exception when others then
      raise warning 'chat_mention notify gagal: %', sqlerrm;
    end;
  end loop;
  return v_sent;
end;
$$;

revoke all on function public.chat_mention_notify(text, text, bigint, text[]) from public, anon, authenticated;
grant execute on function public.chat_mention_notify(text, text, bigint, text[]) to service_role;

-- Perbaikan: clan_members.clan_id bisa uuid, jadi bandingkan sebagai teks.
create or replace function public.clan_giveaway_check_claim(p_uid text, p_id bigint)
returns void language plpgsql stable security definer set search_path = public as $$
declare
  v_clan text;
begin
  select clan_id into v_clan from premium_giveaways where id = p_id;
  if v_clan is null then return; end if;
  if not exists (select 1 from clan_members where firebase_uid = p_uid and clan_id::text = v_clan) then
    raise exception 'Giveaway ini khusus anggota clan' using errcode = 'P0001';
  end if;
end;
$$;

commit;
