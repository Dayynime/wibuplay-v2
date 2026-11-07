-- =====================================================================
-- Danmaku: komentar singkat yang melayang di video pada detik tertentu.
--   * content_key: 'a:<episodeId>' (anime) / 'd:<slug>' (donghua)
--   * maks 50 karakter, warna dari daftar tetap
--   * akun diblokir / di-mute tidak bisa kirim
--   * batas: 1 per 4 detik, 30 per 10 menit per akun
--   * hapus: pengirim sendiri atau developer/admin/moderator
-- Butuh _chat_role_rank & chat_mute_status (chat_mute.sql, sudah terpasang).
-- Jalankan:  docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < danmaku.sql
-- =====================================================================
begin;

create table if not exists public.danmaku (
  id           bigserial primary key,
  content_key  text not null check (char_length(content_key) between 3 and 160),
  t_ms         int  not null check (t_ms between 0 and 21600000),
  firebase_uid text not null,
  body         text not null check (char_length(body) between 1 and 50),
  color        text,
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  deleted_by   text
);
create index if not exists danmaku_key_idx on public.danmaku (content_key, t_ms) where deleted_at is null;
create index if not exists danmaku_uid_idx on public.danmaku (firebase_uid, created_at);

alter table public.danmaku enable row level security;
revoke all on public.danmaku from anon, authenticated;
grant all on public.danmaku to service_role;
grant usage, select on sequence public.danmaku_id_seq to service_role;

create or replace function public._danmaku_colors()
returns text[] language sql immutable as $$
  select array['#FFFFFF', '#FF5C7A', '#FFD54A', '#4ADE80', '#22D3EE', '#C084FC'];
$$;

-- Semua danmaku satu episode (maks 2000, urut waktu), bentuk ringkas:
-- [[id, t_ms, body, color, uid], ...]
create or replace function public.danmaku_list(p_key text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_array(d.id, d.t_ms, d.body, d.color, d.firebase_uid) order by d.t_ms, d.id), '[]'::jsonb)
  from (
    select id, t_ms, body, color, firebase_uid
      from danmaku
     where content_key = p_key and deleted_at is null
     order by id desc
     limit 2000
  ) d;
$$;

create or replace function public.danmaku_send(p_uid text, p_key text, p_t int, p_body text, p_color text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_body text := btrim(regexp_replace(coalesce(p_body, ''), '\s+', ' ', 'g'));
  v_color text := case when p_color = any(_danmaku_colors()) then p_color else null end;
  m jsonb;
  r danmaku;
begin
  if exists (select 1 from banned_accounts where firebase_uid = p_uid) then
    raise exception 'Akun kamu diblokir' using errcode = 'P0001';
  end if;
  m := chat_mute_status(p_uid);
  if coalesce((m ->> 'muted')::boolean, false) then
    raise exception '%', coalesce(m ->> 'message', 'Kamu sedang di-mute') using errcode = 'P0001';
  end if;
  if v_body = '' then raise exception 'Komentar kosong' using errcode = 'P0001'; end if;
  if char_length(v_body) > 50 then raise exception 'Maksimal 50 karakter' using errcode = 'P0001'; end if;
  if p_key is null or p_key !~ '^[ad]:[^[:space:]]{1,158}$' then
    raise exception 'Episode tidak valid' using errcode = 'P0001';
  end if;
  if p_t is null or p_t < 0 or p_t > 21600000 then
    raise exception 'Waktu tidak valid' using errcode = 'P0001';
  end if;
  if exists (select 1 from danmaku where firebase_uid = p_uid and created_at > now() - interval '4 seconds') then
    raise exception 'Pelan-pelan, tunggu sebentar' using errcode = 'P0001';
  end if;
  if (select count(*) from danmaku where firebase_uid = p_uid and created_at > now() - interval '10 minutes') >= 30 then
    raise exception 'Terlalu banyak danmaku, istirahat dulu ya' using errcode = 'P0001';
  end if;

  insert into danmaku (content_key, t_ms, firebase_uid, body, color)
  values (p_key, p_t, p_uid, v_body, v_color)
  returning * into r;
  return jsonb_build_array(r.id, r.t_ms, r.body, r.color, r.firebase_uid);
end;
$$;

create or replace function public.danmaku_delete(p_uid text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_owner text;
begin
  select firebase_uid into v_owner from danmaku where id = p_id and deleted_at is null;
  if v_owner is null then raise exception 'Danmaku tidak ditemukan' using errcode = 'P0001'; end if;
  if v_owner <> p_uid and _chat_role_rank(p_uid) < 1 then
    raise exception 'Kamu tidak bisa menghapus danmaku ini' using errcode = 'P0001';
  end if;
  update danmaku set deleted_at = now(), deleted_by = p_uid where id = p_id;
end;
$$;

revoke all on function public._danmaku_colors() from public, anon, authenticated;
revoke all on function public.danmaku_list(text) from public, anon, authenticated;
revoke all on function public.danmaku_send(text, text, int, text, text) from public, anon, authenticated;
revoke all on function public.danmaku_delete(text, bigint) from public, anon, authenticated;
grant execute on function public._danmaku_colors() to service_role;
grant execute on function public.danmaku_list(text) to service_role;
grant execute on function public.danmaku_send(text, text, int, text, text) to service_role;
grant execute on function public.danmaku_delete(text, bigint) to service_role;

commit;
