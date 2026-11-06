-- =====================================================================
-- Mute chat: user tidak bisa kirim pesan di Chat Global, Chat Clan, dan
-- Komentar episode selama 1 jam / 1 hari / 1 minggu / permanen.
-- Yang boleh mute: developer, admin, moderator (user_roles), dan hanya ke
-- user dengan role LEBIH RENDAH. Ditegakkan lewat trigger BEFORE INSERT,
-- jadi berlaku untuk semua jalur kirim (Edge Function maupun PostgREST).
-- Chat pribadi & chat nobar tidak terkena.
-- Jalankan:  docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < chat_mute.sql
-- =====================================================================
begin;

create table if not exists public.chat_mutes (
  firebase_uid text primary key,
  muted_until  timestamptz,            -- null = permanen
  reason       text,
  muted_by     text not null,
  created_at   timestamptz not null default now()
);
alter table public.chat_mutes enable row level security;
revoke all on public.chat_mutes from anon, authenticated;
grant all on public.chat_mutes to service_role;

-- Peringkat role: developer 3, admin 2, moderator 1, user biasa 0.
create or replace function public._chat_role_rank(p_uid text)
returns int language sql stable set search_path = public as $$
  select coalesce(max(case role when 'developer' then 3 when 'admin' then 2 when 'moderator' then 1 else 0 end), 0)
  from user_roles where firebase_uid = p_uid;
$$;

-- Mute yang masih berlaku (null kalau tidak di-mute).
create or replace function public._chat_active_mute(p_uid text)
returns public.chat_mutes language sql stable set search_path = public as $$
  select * from chat_mutes
  where firebase_uid = p_uid and (muted_until is null or muted_until > now());
$$;

create or replace function public._chat_mute_text(m public.chat_mutes)
returns text language sql stable as $$
  select case
    when m.muted_until is null then 'Kamu di-mute permanen dari chat'
    else 'Kamu di-mute dari chat sampai '
         || to_char(m.muted_until at time zone 'Asia/Jakarta', 'DD/MM HH24:MI') || ' WIB'
  end;
$$;

-- --------------------------------------------------------------- trigger
create or replace function private.trg_chat_mute_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  m chat_mutes;
begin
  -- Pesan sistem di chat global (gift / giveaway / event wallpaper) tidak
  -- diblokir supaya transaksi yang sudah dibayar tidak gagal.
  if tg_table_name = 'global_chat_messages' then
    -- if terpisah: kolom gift_* cuma ada di tabel ini.
    if new.gift_days is not null or new.giveaway_id is not null or new.wp_event_id is not null then
      return new;
    end if;
  end if;
  select * into m from _chat_active_mute(new.firebase_uid);
  if m.firebase_uid is not null then
    raise exception '%', _chat_mute_text(m) using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_chat_mute_guard on public.global_chat_messages;
create trigger trg_chat_mute_guard before insert on public.global_chat_messages
  for each row execute function private.trg_chat_mute_guard();
drop trigger if exists trg_chat_mute_guard on public.clan_messages;
create trigger trg_chat_mute_guard before insert on public.clan_messages
  for each row execute function private.trg_chat_mute_guard();
drop trigger if exists trg_chat_mute_guard on public.episode_comments;
create trigger trg_chat_mute_guard before insert on public.episode_comments
  for each row execute function private.trg_chat_mute_guard();

-- --------------------------------------------------------------- aksi
-- Status mute diri sendiri: {muted, permanent, until, reason, message}
create or replace function public.chat_mute_status(p_uid text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m chat_mutes;
begin
  select * into m from _chat_active_mute(p_uid);
  if m.firebase_uid is null then
    return jsonb_build_object('muted', false);
  end if;
  return jsonb_build_object(
    'muted', true,
    'permanent', m.muted_until is null,
    'until', m.muted_until,
    'reason', m.reason,
    'message', _chat_mute_text(m)
  );
end;
$$;

-- p_duration: '1h' | '1d' | '1w' | 'perm'
create or replace function public.chat_mute_set(p_actor text, p_target text, p_duration text, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor int := _chat_role_rank(p_actor);
  v_until timestamptz;
  v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 120), '');
begin
  if v_actor < 1 then raise exception 'Kamu tidak punya akses'; end if;
  if p_target is null or p_target = '' then raise exception 'User tidak valid'; end if;
  if p_target = p_actor then raise exception 'Tidak bisa mute diri sendiri'; end if;
  if _chat_role_rank(p_target) >= v_actor then
    raise exception 'Tidak bisa mute user dengan role setara atau lebih tinggi';
  end if;
  v_until := case p_duration
    when '1h' then now() + interval '1 hour'
    when '1d' then now() + interval '1 day'
    when '1w' then now() + interval '7 days'
    when 'perm' then null
    else 'epoch'::timestamptz
  end;
  if v_until = 'epoch'::timestamptz then raise exception 'Durasi tidak valid'; end if;

  insert into chat_mutes (firebase_uid, muted_until, reason, muted_by, created_at)
  values (p_target, v_until, v_reason, p_actor, now())
  on conflict (firebase_uid) do update
    set muted_until = excluded.muted_until, reason = excluded.reason,
        muted_by = excluded.muted_by, created_at = excluded.created_at;
  return chat_mute_status(p_target);
end;
$$;

create or replace function public.chat_mute_clear(p_actor text, p_target text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor int := _chat_role_rank(p_actor);
begin
  if v_actor < 1 then raise exception 'Kamu tidak punya akses'; end if;
  if _chat_role_rank(p_target) >= v_actor then
    raise exception 'Tidak bisa mengubah mute user dengan role setara atau lebih tinggi';
  end if;
  delete from chat_mutes where firebase_uid = p_target;
  return jsonb_build_object('muted', false);
end;
$$;

-- Status mute user lain (untuk menu moderator). Hanya pemegang role.
create or replace function public.chat_mute_check(p_actor text, p_target text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if _chat_role_rank(p_actor) < 1 then raise exception 'Kamu tidak punya akses'; end if;
  return chat_mute_status(p_target);
end;
$$;

revoke all on function public._chat_role_rank(text) from public, anon, authenticated;
revoke all on function public._chat_active_mute(text) from public, anon, authenticated;
revoke all on function public.chat_mute_status(text) from public, anon, authenticated;
revoke all on function public.chat_mute_set(text, text, text, text) from public, anon, authenticated;
revoke all on function public.chat_mute_clear(text, text) from public, anon, authenticated;
revoke all on function public.chat_mute_check(text, text) from public, anon, authenticated;
grant execute on function public.chat_mute_status(text) to service_role;
grant execute on function public.chat_mute_set(text, text, text, text) to service_role;
grant execute on function public.chat_mute_clear(text, text) to service_role;
grant execute on function public.chat_mute_check(text, text) to service_role;

commit;
