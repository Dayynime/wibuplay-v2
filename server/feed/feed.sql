-- =====================================================================
-- Feed: postingan user (teks + 1 gambar), like, dan komentar.
--   * Bikin postingan: khusus Premium.
--   * Like & komentar: semua user login.
--   * Tab "Semua" (publik) & "Teman" (teman + diri sendiri).
--   * Akun diblokir / sedang di-mute tidak bisa posting, like, komentar.
--   * Hapus postingan: pemilik atau developer/admin/moderator.
--   * Hapus komentar: penulis komentar, pemilik postingan, atau pemegang role.
--   * Komentar baru -> notif (push) ke pemilik postingan.
-- Gambar: app upload ke bucket privat `feed-staging` (signed URL), Edge
-- Function `feed` cek isinya lalu menyalin ke bucket publik `feed`.
-- Butuh _chat_role_rank & chat_mute_status (chat_mute.sql, sudah terpasang).
-- Jalankan:  docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < feed.sql
-- =====================================================================
begin;

create table if not exists public.feed_posts (
  id            bigserial primary key,
  firebase_uid  text not null,
  body          text not null default '' check (char_length(body) <= 1000),
  image_path    text,
  image_w       int,
  image_h       int,
  like_count    int not null default 0,
  comment_count int not null default 0,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  deleted_by    text
);
create index if not exists feed_posts_live_idx on public.feed_posts (id desc) where deleted_at is null;
create index if not exists feed_posts_uid_idx on public.feed_posts (firebase_uid, id desc);

create table if not exists public.feed_likes (
  post_id      bigint not null references public.feed_posts(id) on delete cascade,
  firebase_uid text not null,
  created_at   timestamptz not null default now(),
  primary key (post_id, firebase_uid)
);
create index if not exists feed_likes_uid_idx on public.feed_likes (firebase_uid, created_at);

create table if not exists public.feed_comments (
  id           bigserial primary key,
  post_id      bigint not null references public.feed_posts(id) on delete cascade,
  firebase_uid text not null,
  body         text not null check (char_length(body) between 1 and 500),
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  deleted_by   text
);
create index if not exists feed_comments_post_idx on public.feed_comments (post_id, id);
create index if not exists feed_comments_uid_idx on public.feed_comments (firebase_uid, created_at);

create table if not exists public.feed_uploads (
  id           uuid primary key default gen_random_uuid(),
  firebase_uid text not null,
  mime         text not null,
  staging_path text not null,
  used         boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists feed_uploads_uid_idx on public.feed_uploads (firebase_uid, created_at);

alter table public.feed_posts    enable row level security;
alter table public.feed_likes    enable row level security;
alter table public.feed_comments enable row level security;
alter table public.feed_uploads  enable row level security;
revoke all on public.feed_posts, public.feed_likes, public.feed_comments, public.feed_uploads from anon, authenticated;
grant all on public.feed_posts, public.feed_likes, public.feed_comments, public.feed_uploads to service_role;
grant usage, select on sequence public.feed_posts_id_seq, public.feed_comments_id_seq to service_role;

-- Gambar maks 2 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('feed-staging', 'feed-staging', false, 2097152, array['image/png','image/webp','image/jpeg']),
  ('feed',         'feed',         true,  2097152, array['image/png','image/webp','image/jpeg'])
on conflict (id) do nothing;

-- --------------------------------------------------------------- helper
create or replace function public._feed_guard(p_uid text)
returns void language plpgsql stable security definer set search_path = public as $$
declare
  m jsonb;
begin
  if exists (select 1 from banned_accounts where firebase_uid = p_uid) then
    raise exception 'Akun kamu diblokir' using errcode = 'P0001';
  end if;
  m := chat_mute_status(p_uid);
  if coalesce((m ->> 'muted')::boolean, false) then
    raise exception '%', coalesce(m ->> 'message', 'Kamu sedang di-mute') using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public._feed_premium(p_uid text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from premium_status
     where firebase_uid = p_uid and is_premium
       and (expires_at is null or expires_at > now())
  );
$$;

create or replace function public._feed_post_json(p public.feed_posts, p_viewer text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'uid', p.firebase_uid,
    'username', coalesce(nullif(btrim(cp.username), ''), 'Pengguna'),
    'avatar_url', cp.avatar_url,
    'username_color', cp.username_color,
    'user_number', cp.user_number,
    'body', p.body,
    'image_path', p.image_path,
    'image_w', p.image_w,
    'image_h', p.image_h,
    'like_count', p.like_count,
    'comment_count', p.comment_count,
    'liked', exists (select 1 from feed_likes l where l.post_id = p.id and l.firebase_uid = p_viewer),
    'created_at', p.created_at
  )
  from (select 1) _
  left join chat_profiles cp on cp.firebase_uid = p.firebase_uid;
$$;

-- --------------------------------------------------------------- upload
-- Return {id, path} untuk signed upload ke bucket feed-staging.
create or replace function public.feed_upload_begin(p_uid text, p_mime text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_ext text := case p_mime when 'image/png' then 'png' when 'image/webp' then 'webp' when 'image/jpeg' then 'jpg' end;
  v_id uuid := gen_random_uuid();
begin
  if v_ext is null then raise exception 'Gambar harus JPG, PNG, atau WebP' using errcode = 'P0001'; end if;
  perform _feed_guard(p_uid);
  if not _feed_premium(p_uid) then
    raise exception 'Bikin postingan khusus pengguna Premium' using errcode = 'P0001';
  end if;
  if (select count(*) from feed_uploads where firebase_uid = p_uid and created_at > now() - interval '1 day') >= 30 then
    raise exception 'Batas upload gambar hari ini sudah habis' using errcode = 'P0001';
  end if;
  insert into feed_uploads (id, firebase_uid, mime, staging_path)
  values (v_id, p_uid, p_mime, v_id::text || '.' || v_ext);
  return jsonb_build_object('id', v_id, 'path', v_id::text || '.' || v_ext);
end;
$$;

-- --------------------------------------------------------------- posting
-- p_image_path = path di bucket publik `feed` (sudah disalin Edge Function).
create or replace function public.feed_post_create(
  p_uid text, p_body text, p_upload uuid, p_image_path text, p_w int, p_h int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_body text := btrim(coalesce(p_body, ''));
  r feed_posts;
begin
  perform _feed_guard(p_uid);
  if not _feed_premium(p_uid) then
    raise exception 'Bikin postingan khusus pengguna Premium' using errcode = 'P0001';
  end if;
  if v_body = '' and p_image_path is null then
    raise exception 'Tulis sesuatu atau pilih gambar dulu' using errcode = 'P0001';
  end if;
  if char_length(v_body) > 1000 then
    raise exception 'Postingan maksimal 1000 karakter' using errcode = 'P0001';
  end if;
  if exists (select 1 from feed_posts where firebase_uid = p_uid and created_at > now() - interval '1 minute') then
    raise exception 'Tunggu sebentar sebelum posting lagi' using errcode = 'P0001';
  end if;
  if (select count(*) from feed_posts where firebase_uid = p_uid and created_at > now() - interval '1 day') >= 15 then
    raise exception 'Batas postingan hari ini sudah habis (15)' using errcode = 'P0001';
  end if;
  if p_upload is not null then
    update feed_uploads set used = true where id = p_upload and firebase_uid = p_uid and not used;
    if not found then raise exception 'Gambar tidak valid, upload ulang' using errcode = 'P0001'; end if;
  end if;

  insert into feed_posts (firebase_uid, body, image_path, image_w, image_h)
  values (p_uid, v_body, p_image_path,
          case when p_image_path is null then null else least(greatest(coalesce(p_w, 0), 0), 10000) end,
          case when p_image_path is null then null else least(greatest(coalesce(p_h, 0), 0), 10000) end)
  returning * into r;
  return _feed_post_json(r, p_uid);
end;
$$;

-- p_tab: 'all' | 'friends'. p_before: id terakhir yang sudah dimuat (0 = terbaru).
-- Tab Teman: ambil postingan terbaru tiap teman lewat index (firebase_uid, id),
-- jadi tetap cepat walaupun total postingan sudah banyak.
create or replace function public.feed_list(p_uid text, p_tab text, p_before bigint, p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 20), 1), 40);
  v_before bigint := coalesce(p_before, 0);
  v_ids bigint[];
  v_uids text[];
begin
  if p_tab = 'friends' then
    select array_agg(distinct u) into v_uids from (
      select case when requester_uid = p_uid then addressee_uid else requester_uid end as u
        from friendships
       where status = 'accepted' and (requester_uid = p_uid or addressee_uid = p_uid)
      union all
      select p_uid
    ) x;
    select array_agg(q.id order by q.id desc) into v_ids from (
      select q.id
        from unnest(v_uids) as f(uid)
        cross join lateral (
          select id from feed_posts q
           where q.firebase_uid = f.uid and q.deleted_at is null
             and (v_before <= 0 or q.id < v_before)
           order by q.id desc
           limit v_lim
        ) q
       where not exists (select 1 from banned_accounts b where b.firebase_uid = f.uid)
       order by q.id desc
       limit v_lim
    ) q;
  else
    select array_agg(q.id order by q.id desc) into v_ids from (
      select p.id from feed_posts p
       where p.deleted_at is null
         and (v_before <= 0 or p.id < v_before)
         and not exists (select 1 from banned_accounts b where b.firebase_uid = p.firebase_uid)
       order by p.id desc
       limit v_lim
    ) q;
  end if;
  if v_ids is null then return '[]'::jsonb; end if;
  return (
    select coalesce(jsonb_agg(_feed_post_json(p, p_uid) order by p.id desc), '[]'::jsonb)
      from feed_posts p where p.id = any(v_ids)
  );
end;
$$;

create or replace function public.feed_get(p_uid text, p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  r feed_posts;
begin
  select * into r from feed_posts where id = p_id and deleted_at is null;
  if r.id is null then raise exception 'Postingan sudah dihapus' using errcode = 'P0001'; end if;
  return _feed_post_json(r, p_uid);
end;
$$;

-- Return image_path (untuk dihapus dari storage) atau null.
create or replace function public.feed_post_delete(p_uid text, p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r feed_posts;
begin
  select * into r from feed_posts where id = p_id and deleted_at is null for update;
  if r.id is null then raise exception 'Postingan tidak ditemukan' using errcode = 'P0001'; end if;
  if r.firebase_uid <> p_uid and _chat_role_rank(p_uid) < 1 then
    raise exception 'Kamu tidak bisa menghapus postingan ini' using errcode = 'P0001';
  end if;
  update feed_posts set deleted_at = now(), deleted_by = p_uid where id = p_id;
  return jsonb_build_object('image_path', r.image_path);
end;
$$;

-- --------------------------------------------------------------- like
create or replace function public.feed_like(p_uid text, p_id bigint, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_n int;
begin
  if not exists (select 1 from feed_posts where id = p_id and deleted_at is null) then
    raise exception 'Postingan sudah dihapus' using errcode = 'P0001';
  end if;
  if p_on then
    perform _feed_guard(p_uid);
    if (select count(*) from feed_likes where firebase_uid = p_uid and created_at > now() - interval '1 minute') >= 40 then
      raise exception 'Terlalu cepat, tunggu sebentar' using errcode = 'P0001';
    end if;
    insert into feed_likes (post_id, firebase_uid) values (p_id, p_uid) on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n > 0 then update feed_posts set like_count = like_count + 1 where id = p_id; end if;
  else
    delete from feed_likes where post_id = p_id and firebase_uid = p_uid;
    get diagnostics v_n = row_count;
    if v_n > 0 then update feed_posts set like_count = greatest(like_count - 1, 0) where id = p_id; end if;
  end if;
  return (select jsonb_build_object('liked', p_on, 'like_count', like_count) from feed_posts where id = p_id);
end;
$$;

-- --------------------------------------------------------------- komentar
create or replace function public._feed_comment_json(c public.feed_comments)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id,
    'post_id', c.post_id,
    'uid', c.firebase_uid,
    'username', coalesce(nullif(btrim(cp.username), ''), 'Pengguna'),
    'avatar_url', cp.avatar_url,
    'username_color', cp.username_color,
    'body', c.body,
    'created_at', c.created_at
  )
  from (select 1) _
  left join chat_profiles cp on cp.firebase_uid = c.firebase_uid;
$$;

-- 30 komentar terlama setelah p_after (0 = dari awal), urut lama -> baru.
create or replace function public.feed_comments_list(p_id bigint, p_after bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(_feed_comment_json(c) order by c.id), '[]'::jsonb)
  from feed_comments c
  where c.id in (
    select id from feed_comments
     where post_id = p_id and deleted_at is null and id > coalesce(p_after, 0)
     order by id limit 30
  );
$$;

create or replace function public.feed_comment_add(p_uid text, p_id bigint, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_body text := btrim(coalesce(p_body, ''));
  v_owner text;
  v_name text;
  c feed_comments;
begin
  perform _feed_guard(p_uid);
  if v_body = '' then raise exception 'Komentar kosong' using errcode = 'P0001'; end if;
  if char_length(v_body) > 500 then raise exception 'Komentar maksimal 500 karakter' using errcode = 'P0001'; end if;
  select firebase_uid into v_owner from feed_posts where id = p_id and deleted_at is null;
  if v_owner is null then raise exception 'Postingan sudah dihapus' using errcode = 'P0001'; end if;
  if (select count(*) from feed_comments where firebase_uid = p_uid and created_at > now() - interval '1 minute') >= 8 then
    raise exception 'Terlalu cepat, tunggu sebentar' using errcode = 'P0001';
  end if;

  insert into feed_comments (post_id, firebase_uid, body) values (p_id, p_uid, v_body) returning * into c;
  update feed_posts set comment_count = comment_count + 1 where id = p_id;

  if v_owner <> p_uid then
    select nullif(btrim(username), '') into v_name from chat_profiles where firebase_uid = p_uid;
    begin
      perform private.push_notify(
        v_owner, p_uid, 'feed_comment',
        coalesce(v_name, 'Seseorang') || ' mengomentari postinganmu',
        left(regexp_replace(v_body, '\s+', ' ', 'g'), 120),
        jsonb_build_object('post_id', p_id, 'comment_id', c.id)
      );
    exception when others then
      raise warning 'feed_comment notify gagal: %', sqlerrm;
    end;
  end if;
  return _feed_comment_json(c);
end;
$$;

create or replace function public.feed_comment_delete(p_uid text, p_comment bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  c feed_comments;
  v_owner text;
begin
  select * into c from feed_comments where id = p_comment and deleted_at is null for update;
  if c.id is null then raise exception 'Komentar tidak ditemukan' using errcode = 'P0001'; end if;
  select firebase_uid into v_owner from feed_posts where id = c.post_id;
  if c.firebase_uid <> p_uid and v_owner is distinct from p_uid and _chat_role_rank(p_uid) < 1 then
    raise exception 'Kamu tidak bisa menghapus komentar ini' using errcode = 'P0001';
  end if;
  update feed_comments set deleted_at = now(), deleted_by = p_uid where id = p_comment;
  update feed_posts set comment_count = greatest(comment_count - 1, 0) where id = c.post_id;
end;
$$;

-- --------------------------------------------------------------- izin
do $$
declare
  f text;
begin
  foreach f in array array[
    'public._feed_guard(text)', 'public._feed_premium(text)',
    'public._feed_post_json(public.feed_posts, text)', 'public._feed_comment_json(public.feed_comments)',
    'public.feed_upload_begin(text, text)', 'public.feed_post_create(text, text, uuid, text, int, int)',
    'public.feed_list(text, text, bigint, int)', 'public.feed_get(text, bigint)',
    'public.feed_post_delete(text, bigint)', 'public.feed_like(text, bigint, boolean)',
    'public.feed_comments_list(bigint, bigint)', 'public.feed_comment_add(text, bigint, text)',
    'public.feed_comment_delete(text, bigint)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

commit;
