-- =====================================================================
-- Afinitas: ikatan dua user (Soulmate, Crush, Partner, Twin, Nakama, Kin,
-- Senpai/Kouhai, Rival). Semua gratis, harus berteman, butuh persetujuan.
--
--   * affinities           : ikatan aktif (1 baris per pasangan, user_a < user_b)
--   * affinity_requests    : permintaan (pending/accepted/declined/cancelled/expired)
--   * affinity_points_log  : poin harian per pasangan per sumber (batas harian + statistik)
--   * affinity_moments     : momen (mulai, naik level, 30/100/365 hari, catur 100, nobar 50)
--
-- Poin masuk OTOMATIS lewat trigger di tabel yang sudah ada:
--   private_messages (chat), chess_games (catur selesai), nobar_members (nobar),
--   global_chat_messages (gift Premium), user_last_seen (sama-sama aktif hari ini).
-- Trigger dibungkus exception: kalau afinitas error, aksi aslinya TETAP jalan.
--
-- Semua tabel terkunci (tanpa policy). Hanya service_role (Edge Function
-- `affinity`) yang memanggil fungsi publik di bawah.
--
-- Jalankan: docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < affinity.sql
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
create table if not exists public.affinities (
  id                  uuid primary key default gen_random_uuid(),
  user_a              text not null,
  user_b              text not null,
  type                text not null,
  role_a              text,
  role_b              text,
  points              integer not null default 0 check (points >= 0),
  level               smallint not null default 1,
  created_at          timestamptz not null default now(),   -- bersama sejak (tetap walau ganti jenis)
  type_since          timestamptz not null default now(),
  last_interaction_at timestamptz not null default now(),
  last_decay_at       timestamptz not null default now(),
  check (user_a < user_b),
  unique (user_a, user_b)
);
create index if not exists affinities_a_idx on public.affinities (user_a);
create index if not exists affinities_b_idx on public.affinities (user_b);

create table if not exists public.affinity_requests (
  id           uuid primary key default gen_random_uuid(),
  from_uid     text not null,
  to_uid       text not null,
  type         text not null,
  from_role    text,
  to_role      text,
  message      text check (message is null or char_length(message) <= 120),
  status       text not null default 'pending'
               check (status in ('pending', 'accepted', 'declined', 'cancelled', 'expired')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz
);
create index if not exists affinity_requests_to_idx   on public.affinity_requests (to_uid, status);
create index if not exists affinity_requests_from_idx on public.affinity_requests (from_uid, status);
create index if not exists affinity_requests_pending_idx on public.affinity_requests (created_at) where status = 'pending';
-- Satu permintaan pending per pasangan (arah mana pun).
create unique index if not exists affinity_requests_one_pending
  on public.affinity_requests (least(from_uid, to_uid), greatest(from_uid, to_uid)) where status = 'pending';

create table if not exists public.affinity_points_log (
  user_a  text    not null,
  user_b  text    not null,
  day     date    not null,
  source  text    not null,
  points  integer not null default 0,
  count   integer not null default 0,
  primary key (user_a, user_b, day, source)
);

create table if not exists public.affinity_moments (
  id         bigserial primary key,
  user_a     text not null,
  user_b     text not null,
  kind       text not null,          -- start | level | days | chess | nobar | type
  value      text not null default '',
  created_at timestamptz not null default now(),
  unique (user_a, user_b, kind, value)
);
create index if not exists affinity_moments_pair_idx on public.affinity_moments (user_a, user_b, created_at desc);

alter table public.affinities          enable row level security;
alter table public.affinity_requests   enable row level security;
alter table public.affinity_points_log enable row level security;
alter table public.affinity_moments    enable row level security;
revoke all on public.affinities, public.affinity_requests, public.affinity_points_log, public.affinity_moments from anon, authenticated;
grant all on public.affinities, public.affinity_requests, public.affinity_points_log, public.affinity_moments to service_role;
grant usage, select on sequence public.affinity_moments_id_seq to service_role;

-- ---------------------------------------------------------------------
-- Pengaturan (ubah angka di sini lalu jalankan ulang file ini)
-- ---------------------------------------------------------------------
create or replace function public._aff_cfg()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'slots', jsonb_build_object(
      'soulmate', 1, 'crush', 1, 'partner', 1, 'twin', 1,
      'nakama', 5, 'kin', 5, 'senpai', 5, 'rival', 5),
    -- Poin minimal tiap level (Lv1..Lv5): Deai, Kizuna, Shinrai, Kyoumei, Eien
    'levels', jsonb_build_array(0, 500, 2000, 6000, 15000),
    -- Poin per kejadian & batas poin per hari per pasangan
    'points', jsonb_build_object('chat', 2, 'chess', 20, 'nobar', 25, 'gift', 50, 'online', 10),
    'caps',   jsonb_build_object('chat', 40, 'chess', 100, 'nobar', 75, 'gift', 1000000, 'online', 10),
    -- Jenis yang dapat x1.5 dari sumber tertentu (poin & batas)
    'bonus',  jsonb_build_object('nakama', 'nobar', 'rival', 'chess', 'senpai', 'chat'),
    'chess_min_ply', 10,          -- catur minimal 10 langkah baru dapat poin
    'max_pending', 3,             -- permintaan keluar yang menunggu jawaban
    'expire_days', 7,
    'decline_cooldown_days', 3,
    'decay_after_days', 14,       -- tidak berinteraksi 14 hari -> poin turun
    'decay_pct', 2                -- 2% per hari, tidak turun di bawah batas level
  );
$$;

create or replace function public._aff_today()
returns date language sql stable
as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

create or replace function public._aff_valid_type(p text)
returns boolean language sql immutable
as $$ select p in ('soulmate','crush','partner','twin','nakama','kin','senpai','rival') $$;

-- Pasangan peran: kin = kakak/adik, senpai = senpai/kouhai. Jenis lain tanpa peran.
create or replace function public._aff_other_role(p_type text, p_role text)
returns text language sql immutable
as $$
  select case
    when p_type = 'kin'    and p_role = 'kakak'  then 'adik'
    when p_type = 'kin'    and p_role = 'adik'   then 'kakak'
    when p_type = 'senpai' and p_role = 'senpai' then 'kouhai'
    when p_type = 'senpai' and p_role = 'kouhai' then 'senpai'
    else null end
$$;

create or replace function public._aff_level(p_points int)
returns int language plpgsql immutable
as $$
declare
  lv jsonb := public._aff_cfg()->'levels';
  i int;
  r int := 1;
begin
  for i in 0 .. jsonb_array_length(lv) - 1 loop
    if p_points >= (lv->>i)::int then r := i + 1; end if;
  end loop;
  return r;
end;
$$;

create or replace function public._aff_type_name(p text)
returns text language sql immutable
as $$
  select case p
    when 'soulmate' then 'Soulmate' when 'crush' then 'Crush' when 'partner' then 'Partner'
    when 'twin' then 'Twin' when 'nakama' then 'Nakama' when 'kin' then 'Kin'
    when 'senpai' then 'Senpai · Kouhai' when 'rival' then 'Rival' else p end
$$;

create or replace function public._aff_level_name(p int)
returns text language sql immutable
as $$
  select case p when 1 then 'Deai' when 2 then 'Kizuna' when 3 then 'Shinrai'
                when 4 then 'Kyoumei' when 5 then 'Eien' else '' end
$$;

create or replace function public._aff_name(p_uid text)
returns text language sql stable security definer set search_path = public
as $$ select coalesce(nullif(username, ''), 'Teman') from chat_profiles where firebase_uid = p_uid $$;

create or replace function public._aff_notify(p_to text, p_from text, p_type text, p_title text, p_body text, p_data jsonb)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  perform private.push_notify(p_to, p_from, p_type, p_title, p_body, p_data);
exception when others then
  raise warning 'affinity notify gagal: %', sqlerrm;
end;
$$;

create or replace function public._aff_close_notif(p_request uuid, p_expired boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications
     set read_at = coalesce(read_at, now()),
         data = case when p_expired then data || '{"expired": true}'::jsonb else data end
   where type = 'affinity_request' and data->>'request_id' = p_request::text;
exception when others then
  raise warning 'affinity close notif gagal: %', sqlerrm;
end;
$$;

-- Permintaan yang lewat batas waktu -> expired (dipanggil di awal tiap aksi).
create or replace function public._aff_expire()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    update affinity_requests set status = 'expired', responded_at = now()
     where status = 'pending'
       and created_at < now() - make_interval(days => (public._aff_cfg()->>'expire_days')::int)
    returning id
  loop
    perform public._aff_close_notif(r.id, true);
  end loop;
end;
$$;

-- Poin turun pelan kalau lama tidak berinteraksi (tidak di bawah batas level).
create or replace function public._aff_decay(p_uid text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg jsonb := public._aff_cfg();
  v_after int := (cfg->>'decay_after_days')::int;
  v_pct numeric := (cfg->>'decay_pct')::numeric / 100;
begin
  update affinities f
     set points = greatest((cfg->'levels'->>(f.level - 1))::int,
                           floor(f.points * power(1 - v_pct, x.d))::int),
         last_decay_at = now()
    from (
      select id,
             floor(extract(epoch from now() - greatest(last_decay_at, last_interaction_at + make_interval(days => v_after))) / 86400)::int as d
        from affinities
       where (user_a = p_uid or user_b = p_uid)
         and last_interaction_at < now() - make_interval(days => v_after)
    ) x
   where f.id = x.id and x.d >= 1;
end;
$$;

create or replace function public._aff_slot_used(p_uid text, p_type text, p_exclude uuid)
returns int language sql stable security definer set search_path = public
as $$
  select count(*)::int from affinities
   where (user_a = p_uid or user_b = p_uid) and type = p_type
     and id <> coalesce(p_exclude, '00000000-0000-0000-0000-000000000000'::uuid)
$$;

create or replace function public._aff_are_friends(p1 text, p2 text)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from friendships
     where status = 'accepted'
       and ((requester_uid = p1 and addressee_uid = p2) or (requester_uid = p2 and addressee_uid = p1)))
$$;

-- Momen (sekali per jenis+nilai per pasangan).
create or replace function public._aff_moment(p1 text, p2 text, p_kind text, p_value text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  insert into affinity_moments (user_a, user_b, kind, value)
  values (least(p1, p2), greatest(p1, p2), p_kind, p_value)
  on conflict do nothing;
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- ---------------------------------------------------------------------
-- Inti poin: dipanggil trigger. Tidak ada afinitas aktif = tidak terjadi apa-apa.
-- ---------------------------------------------------------------------
create or replace function public._aff_add(p1 text, p2 text, p_source text, p_qty int default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg jsonb := public._aff_cfg();
  a text := least(p1, p2);
  b text := greatest(p1, p2);
  r affinities;
  v_day date := public._aff_today();
  v_base int;
  v_cap int;
  v_got int;
  v_add int;
  v_new int;
  v_total int;
begin
  if p1 is null or p2 is null or p1 = p2 or coalesce(p_qty, 0) < 1 then return; end if;
  select * into r from affinities where user_a = a and user_b = b for update;
  if not found then return; end if;

  v_base := coalesce((cfg->'points'->>p_source)::int, 0) * p_qty;
  v_cap  := coalesce((cfg->'caps'->>p_source)::int, 0);
  if cfg->'bonus'->>r.type = p_source then
    v_base := ceil(v_base * 1.5);
    v_cap  := ceil(v_cap * 1.5);
  end if;

  select points into v_got from affinity_points_log
   where user_a = a and user_b = b and day = v_day and source = p_source;
  v_add := greatest(0, least(v_base, v_cap - coalesce(v_got, 0)));

  insert into affinity_points_log as l (user_a, user_b, day, source, points, count)
  values (a, b, v_day, p_source, v_add, p_qty)
  on conflict (user_a, user_b, day, source)
  do update set points = l.points + excluded.points, count = l.count + excluded.count;

  v_new := greatest(r.level, public._aff_level(r.points + v_add));
  update affinities
     set points = points + v_add, level = v_new, last_interaction_at = now()
   where id = r.id;

  if v_new > r.level then
    perform public._aff_moment(a, b, 'level', v_new::text);
    perform public._aff_notify(a, b, 'affinity_level',
      'Afinitas naik ke Lv ' || v_new || ' ✨',
      public._aff_type_name(r.type) || ' bersama ' || public._aff_name(b) || ' kini ' || public._aff_level_name(v_new),
      jsonb_build_object('affinity_id', r.id, 'level', v_new));
    perform public._aff_notify(b, a, 'affinity_level',
      'Afinitas naik ke Lv ' || v_new || ' ✨',
      public._aff_type_name(r.type) || ' bersama ' || public._aff_name(a) || ' kini ' || public._aff_level_name(v_new),
      jsonb_build_object('affinity_id', r.id, 'level', v_new));
  end if;

  if p_source in ('chess', 'nobar') then
    select coalesce(sum(count), 0) into v_total from affinity_points_log
     where user_a = a and user_b = b and source = p_source;
    if p_source = 'chess' and v_total >= 100 then perform public._aff_moment(a, b, 'chess', '100'); end if;
    if p_source = 'nobar' and v_total >= 50  then perform public._aff_moment(a, b, 'nobar', '50');  end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Baca: daftar afinitas user (dipakai halaman Afinitas sendiri & publik)
-- ---------------------------------------------------------------------
create or replace function public.affinity_list(p_viewer text, p_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_items jsonb;
  v_in int := 0;
  v_out int := 0;
begin
  perform public._aff_expire();
  perform public._aff_decay(p_uid);

  select coalesce(jsonb_agg(x order by x.points desc, x.since), '[]'::jsonb) into v_items from (
    select f.id,
           f.type,
           case when f.user_a = p_uid then f.user_b else f.user_a end as other_uid,
           case when f.user_a = p_uid then f.role_a else f.role_b end as my_role,
           case when f.user_a = p_uid then f.role_b else f.role_a end as other_role,
           f.points, f.level, f.created_at as since, f.last_interaction_at,
           p.username, p.avatar_url, p.user_number
      from affinities f
      left join chat_profiles p
        on p.firebase_uid = case when f.user_a = p_uid then f.user_b else f.user_a end
     where f.user_a = p_uid or f.user_b = p_uid
  ) x;

  if p_viewer = p_uid then
    select count(*) into v_in  from affinity_requests where to_uid   = p_uid and status = 'pending';
    select count(*) into v_out from affinity_requests where from_uid = p_uid and status = 'pending';
  end if;

  return jsonb_build_object(
    'items', v_items,
    'incoming', v_in,
    'outgoing', v_out,
    'slots', public._aff_cfg()->'slots',
    'levels', public._aff_cfg()->'levels'
  );
end;
$$;

-- Detail satu ikatan: data + statistik bareng + momen.
create or replace function public.affinity_detail(p_viewer text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  f affinities;
  v_days int;
  v_stats jsonb;
  v_moments jsonb;
  v_pa jsonb;
  v_pb jsonb;
begin
  select * into f from affinities where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  perform public._aff_decay(f.user_a);
  select * into f from affinities where id = p_id;

  v_days := floor(extract(epoch from now() - f.created_at) / 86400)::int;
  if v_days >= 30  then perform public._aff_moment(f.user_a, f.user_b, 'days', '30');  end if;
  if v_days >= 100 then perform public._aff_moment(f.user_a, f.user_b, 'days', '100'); end if;
  if v_days >= 365 then perform public._aff_moment(f.user_a, f.user_b, 'days', '365'); end if;

  select coalesce(jsonb_object_agg(source, total), '{}'::jsonb) into v_stats from (
    select source, sum(count)::int as total from affinity_points_log
     where user_a = f.user_a and user_b = f.user_b group by source) s;

  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'value', value, 'created_at', created_at)
                            order by created_at desc), '[]'::jsonb)
    into v_moments
    from (select * from affinity_moments
           where user_a = f.user_a and user_b = f.user_b
           order by created_at desc limit 30) m;

  select jsonb_build_object('uid', firebase_uid, 'username', username, 'avatar_url', avatar_url, 'user_number', user_number)
    into v_pa from chat_profiles where firebase_uid = f.user_a;
  select jsonb_build_object('uid', firebase_uid, 'username', username, 'avatar_url', avatar_url, 'user_number', user_number)
    into v_pb from chat_profiles where firebase_uid = f.user_b;

  return jsonb_build_object(
    'ok', true,
    'id', f.id, 'type', f.type, 'points', f.points, 'level', f.level,
    'since', f.created_at, 'type_since', f.type_since, 'last_interaction_at', f.last_interaction_at,
    'user_a', coalesce(v_pa, jsonb_build_object('uid', f.user_a)), 'role_a', f.role_a,
    'user_b', coalesce(v_pb, jsonb_build_object('uid', f.user_b)), 'role_b', f.role_b,
    'stats', v_stats,
    'moments', v_moments,
    'levels', public._aff_cfg()->'levels',
    'viewer_in', p_viewer in (f.user_a, f.user_b)
  );
end;
$$;

-- Permintaan masuk (to = saya) atau keluar (from = saya) yang masih pending.
create or replace function public.affinity_requests_list(p_uid text, p_incoming boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  perform public._aff_expire();
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into v from (
    select r.id, r.from_uid, r.to_uid, r.type, r.from_role, r.to_role, r.message, r.created_at,
           r.created_at + make_interval(days => (public._aff_cfg()->>'expire_days')::int) as expires_at,
           p.username, p.avatar_url, p.user_number,
           (select f.type from affinities f
             where f.user_a = least(r.from_uid, r.to_uid) and f.user_b = greatest(r.from_uid, r.to_uid)) as current_type
      from affinity_requests r
      left join chat_profiles p
        on p.firebase_uid = case when p_incoming then r.from_uid else r.to_uid end
     where r.status = 'pending'
       and ((p_incoming and r.to_uid = p_uid) or (not p_incoming and r.from_uid = p_uid))
  ) x;
  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- Aksi
-- ---------------------------------------------------------------------
create or replace function public.affinity_request(
  p_uid text, p_target text, p_type text, p_role text, p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg jsonb := public._aff_cfg();
  f affinities;
  v_role text := nullif(trim(coalesce(p_role, '')), '');
  v_other_role text;
  v_msg text := nullif(left(trim(coalesce(p_message, '')), 120), '');
  v_slots int := (cfg->'slots'->>p_type)::int;
  v_id uuid;
begin
  perform public._aff_expire();

  if p_target is null or p_target = p_uid then return jsonb_build_object('ok', false, 'code', 'self'); end if;
  if not public._aff_valid_type(p_type) then return jsonb_build_object('ok', false, 'code', 'bad_type'); end if;
  if p_type in ('kin', 'senpai') then
    v_other_role := public._aff_other_role(p_type, v_role);
    if v_other_role is null then return jsonb_build_object('ok', false, 'code', 'bad_role'); end if;
  else
    v_role := null;
  end if;
  if not exists (select 1 from chat_profiles where firebase_uid = p_uid) then
    return jsonb_build_object('ok', false, 'code', 'no_profile');
  end if;
  if exists (select 1 from banned_accounts where firebase_uid in (p_uid, p_target)) then
    return jsonb_build_object('ok', false, 'code', 'banned');
  end if;
  if not public._aff_are_friends(p_uid, p_target) then
    return jsonb_build_object('ok', false, 'code', 'not_friends');
  end if;

  select * into f from affinities where user_a = least(p_uid, p_target) and user_b = greatest(p_uid, p_target);
  if found and f.type = p_type then
    -- Jenis sama: hanya boleh kalau peran ditukar (mis. Kakak <-> Adik).
    if p_type not in ('kin', 'senpai')
       or (case when f.user_a = p_uid then f.role_a else f.role_b end) = v_role then
      return jsonb_build_object('ok', false, 'code', 'same_type');
    end if;
  end if;

  if exists (select 1 from affinity_requests
              where status = 'pending'
                and least(from_uid, to_uid) = least(p_uid, p_target)
                and greatest(from_uid, to_uid) = greatest(p_uid, p_target)) then
    return jsonb_build_object('ok', false, 'code', 'pending_exists');
  end if;
  if (select count(*) from affinity_requests where from_uid = p_uid and status = 'pending')
     >= (cfg->>'max_pending')::int then
    return jsonb_build_object('ok', false, 'code', 'too_many_pending');
  end if;
  if exists (select 1 from affinity_requests
              where from_uid = p_uid and to_uid = p_target and status = 'declined'
                and responded_at > now() - make_interval(days => (cfg->>'decline_cooldown_days')::int)) then
    return jsonb_build_object('ok', false, 'code', 'cooldown');
  end if;
  if public._aff_slot_used(p_uid, p_type, f.id) >= v_slots then
    return jsonb_build_object('ok', false, 'code', 'my_slot_full');
  end if;
  if public._aff_slot_used(p_target, p_type, f.id) >= v_slots then
    return jsonb_build_object('ok', false, 'code', 'their_slot_full');
  end if;

  insert into affinity_requests (from_uid, to_uid, type, from_role, to_role, message)
  values (p_uid, p_target, p_type, v_role, v_other_role, v_msg)
  returning id into v_id;

  perform public._aff_notify(p_target, p_uid, 'affinity_request',
    public._aff_name(p_uid) || ' mengajak afinitas',
    'Ingin menjadi ' || case
      when p_type = 'kin' then (case v_role when 'kakak' then 'Kakak' else 'Adik' end) || '-mu (Kin)'
      when p_type = 'senpai' then (case v_role when 'senpai' then 'Senpai' else 'Kouhai' end) || '-mu'
      else public._aff_type_name(p_type) || '-mu' end
      || coalesce(' · "' || v_msg || '"', ''),
    jsonb_build_object('request_id', v_id, 'type', p_type));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function public.affinity_cancel(p_uid text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update affinity_requests set status = 'cancelled', responded_at = now()
   where id = p_id and from_uid = p_uid and status = 'pending';
  if not found then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  perform public._aff_close_notif(p_id, true);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.affinity_respond(p_uid text, p_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg jsonb := public._aff_cfg();
  q affinity_requests;
  f affinities;
  a text;
  b text;
  v_slots int;
  v_id uuid;
  v_change boolean := false;
begin
  perform public._aff_expire();
  select * into q from affinity_requests where id = p_id and to_uid = p_uid for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  if q.status <> 'pending' then return jsonb_build_object('ok', false, 'code', 'not_pending'); end if;

  if not p_accept then
    update affinity_requests set status = 'declined', responded_at = now() where id = p_id;
    perform public._aff_close_notif(p_id, false);
    return jsonb_build_object('ok', true, 'accepted', false);
  end if;

  if not public._aff_are_friends(q.from_uid, q.to_uid) then
    update affinity_requests set status = 'cancelled', responded_at = now() where id = p_id;
    perform public._aff_close_notif(p_id, true);
    return jsonb_build_object('ok', false, 'code', 'not_friends');
  end if;

  a := least(q.from_uid, q.to_uid);
  b := greatest(q.from_uid, q.to_uid);
  select * into f from affinities where user_a = a and user_b = b for update;
  v_change := found;
  v_slots := (cfg->'slots'->>q.type)::int;
  if public._aff_slot_used(q.to_uid, q.type, f.id) >= v_slots then
    return jsonb_build_object('ok', false, 'code', 'my_slot_full');
  end if;
  if public._aff_slot_used(q.from_uid, q.type, f.id) >= v_slots then
    return jsonb_build_object('ok', false, 'code', 'their_slot_full');
  end if;

  if v_change then
    update affinities
       set type = q.type,
           role_a = case when a = q.from_uid then q.from_role else q.to_role end,
           role_b = case when b = q.from_uid then q.from_role else q.to_role end,
           type_since = now(),
           last_interaction_at = now()
     where id = f.id
    returning id into v_id;
    perform public._aff_moment(a, b, 'type', q.type || ':' || extract(epoch from now())::bigint);
  else
    insert into affinities (user_a, user_b, type, role_a, role_b)
    values (a, b, q.type,
            case when a = q.from_uid then q.from_role else q.to_role end,
            case when b = q.from_uid then q.from_role else q.to_role end)
    returning id into v_id;
    perform public._aff_moment(a, b, 'start', '');
  end if;

  update affinity_requests set status = 'accepted', responded_at = now() where id = p_id;
  perform public._aff_close_notif(p_id, false);
  perform public._aff_notify(q.from_uid, q.to_uid, 'affinity_accepted',
    public._aff_name(q.to_uid) || ' menerima afinitas 💞',
    'Kalian sekarang ' || public._aff_type_name(q.type),
    jsonb_build_object('affinity_id', v_id, 'type', q.type));

  return jsonb_build_object('ok', true, 'accepted', true, 'id', v_id, 'changed', v_change);
end;
$$;

create or replace function public.affinity_break(p_uid text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  f affinities;
  v_other text;
begin
  select * into f from affinities where id = p_id and (user_a = p_uid or user_b = p_uid);
  if not found then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  v_other := case when f.user_a = p_uid then f.user_b else f.user_a end;
  delete from affinities where id = f.id;
  delete from affinity_moments    where user_a = f.user_a and user_b = f.user_b;
  delete from affinity_points_log where user_a = f.user_a and user_b = f.user_b;
  perform public._aff_notify(v_other, p_uid, 'affinity_broken',
    'Afinitas berakhir',
    public._aff_name(p_uid) || ' memutuskan ikatan ' || public._aff_type_name(f.type),
    jsonb_build_object('type', f.type));
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------
-- Trigger sumber poin (semua aman: error di sini tidak menggagalkan aksi asli)
-- ---------------------------------------------------------------------
create or replace function private.trg_aff_private_message()
returns trigger language plpgsql security definer set search_path = public, private
as $$
begin
  begin
    perform public._aff_add(new.sender_uid, new.recipient_uid, 'chat');
  exception when others then raise warning 'affinity chat gagal: %', sqlerrm;
  end;
  return null;
end;
$$;

create or replace function private.trg_aff_chess()
returns trigger language plpgsql security definer set search_path = public, private
as $$
begin
  if new.status = 'finished' and coalesce(old.status, '') <> 'finished'
     and new.white_uid is not null and new.black_uid is not null
     and coalesce(new.ply, 0) >= (public._aff_cfg()->>'chess_min_ply')::int then
    begin
      perform public._aff_add(new.white_uid, new.black_uid, 'chess');
    exception when others then raise warning 'affinity chess gagal: %', sqlerrm;
    end;
  end if;
  return null;
end;
$$;

create or replace function private.trg_aff_nobar()
returns trigger language plpgsql security definer set search_path = public, private
as $$
declare
  m record;
begin
  begin
    for m in
      select firebase_uid from nobar_members
       where room_id = new.room_id and firebase_uid <> new.firebase_uid
         and last_seen > now() - interval '3 minutes'
    loop
      perform public._aff_add(new.firebase_uid, m.firebase_uid, 'nobar');
    end loop;
  exception when others then raise warning 'affinity nobar gagal: %', sqlerrm;
  end;
  return null;
end;
$$;

create or replace function private.trg_aff_gift()
returns trigger language plpgsql security definer set search_path = public, private
as $$
begin
  if new.gift_recipient_uid is not null and coalesce(new.gift_days, 0) > 0 then
    begin
      perform public._aff_add(new.firebase_uid, new.gift_recipient_uid, 'gift', new.gift_days);
    exception when others then raise warning 'affinity gift gagal: %', sqlerrm;
    end;
  end if;
  return null;
end;
$$;

-- Aktif pertama kali hari ini -> +poin dengan pasangan afinitas yang juga aktif hari ini.
create or replace function private.trg_aff_online()
returns trigger language plpgsql security definer set search_path = public, private
as $$
declare
  v_today date := public._aff_today();
  f record;
begin
  if tg_op = 'UPDATE' and (old.last_seen at time zone 'Asia/Jakarta')::date >= v_today then
    return null;  -- sudah aktif hari ini sebelumnya
  end if;
  begin
    for f in
      select case when a.user_a = new.firebase_uid then a.user_b else a.user_a end as other
        from affinities a
       where a.user_a = new.firebase_uid or a.user_b = new.firebase_uid
    loop
      if exists (select 1 from user_last_seen s
                  where s.firebase_uid = f.other
                    and (s.last_seen at time zone 'Asia/Jakarta')::date = v_today) then
        perform public._aff_add(new.firebase_uid, f.other, 'online');
      end if;
    end loop;
  exception when others then raise warning 'affinity online gagal: %', sqlerrm;
  end;
  return null;
end;
$$;

-- Putus teman -> semua afinitas & permintaan pasangan itu ikut hilang.
create or replace function private.trg_aff_friendship_end()
returns trigger language plpgsql security definer set search_path = public, private
as $$
declare
  a text := least(old.requester_uid, old.addressee_uid);
  b text := greatest(old.requester_uid, old.addressee_uid);
begin
  if tg_op = 'UPDATE' and (old.status <> 'accepted' or new.status = 'accepted') then
    return null;
  end if;
  if tg_op = 'DELETE' and old.status <> 'accepted' then
    return null;
  end if;
  begin
    delete from affinities          where user_a = a and user_b = b;
    delete from affinity_moments    where user_a = a and user_b = b;
    delete from affinity_points_log where user_a = a and user_b = b;
    update affinity_requests set status = 'cancelled', responded_at = now()
     where status = 'pending' and least(from_uid, to_uid) = a and greatest(from_uid, to_uid) = b;
  exception when others then raise warning 'affinity friendship gagal: %', sqlerrm;
  end;
  return null;
end;
$$;

-- Pasang trigger hanya kalau tabelnya ada (aman dijalankan ulang).
do $$
begin
  if to_regclass('public.private_messages') is not null then
    drop trigger if exists trg_aff_private_message on public.private_messages;
    create trigger trg_aff_private_message after insert on public.private_messages
      for each row execute function private.trg_aff_private_message();
  else raise notice 'Lewati: public.private_messages tidak ada'; end if;

  if to_regclass('public.chess_games') is not null then
    drop trigger if exists trg_aff_chess on public.chess_games;
    create trigger trg_aff_chess after update of status on public.chess_games
      for each row execute function private.trg_aff_chess();
  else raise notice 'Lewati: public.chess_games tidak ada'; end if;

  if to_regclass('public.nobar_members') is not null then
    drop trigger if exists trg_aff_nobar on public.nobar_members;
    create trigger trg_aff_nobar after insert on public.nobar_members
      for each row execute function private.trg_aff_nobar();
  else raise notice 'Lewati: public.nobar_members tidak ada'; end if;

  if to_regclass('public.global_chat_messages') is not null then
    drop trigger if exists trg_aff_gift on public.global_chat_messages;
    create trigger trg_aff_gift after insert on public.global_chat_messages
      for each row execute function private.trg_aff_gift();
  else raise notice 'Lewati: public.global_chat_messages tidak ada'; end if;

  if to_regclass('public.user_last_seen') is not null then
    drop trigger if exists trg_aff_online on public.user_last_seen;
    create trigger trg_aff_online after insert or update of last_seen on public.user_last_seen
      for each row execute function private.trg_aff_online();
  else raise notice 'Lewati: public.user_last_seen tidak ada'; end if;

  if to_regclass('public.friendships') is not null then
    drop trigger if exists trg_aff_friendship_end on public.friendships;
    create trigger trg_aff_friendship_end after update or delete on public.friendships
      for each row execute function private.trg_aff_friendship_end();
  else raise notice 'Lewati: public.friendships tidak ada'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Hak akses: hanya service_role
-- ---------------------------------------------------------------------
revoke all on function public.affinity_list(text, text)                      from public, anon, authenticated;
revoke all on function public.affinity_detail(text, uuid)                    from public, anon, authenticated;
revoke all on function public.affinity_requests_list(text, boolean)          from public, anon, authenticated;
revoke all on function public.affinity_request(text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.affinity_cancel(text, uuid)                    from public, anon, authenticated;
revoke all on function public.affinity_respond(text, uuid, boolean)          from public, anon, authenticated;
revoke all on function public.affinity_break(text, uuid)                     from public, anon, authenticated;
revoke all on function public._aff_add(text, text, text, int)                from public, anon, authenticated;
revoke all on function public._aff_notify(text, text, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public._aff_close_notif(uuid, boolean)                from public, anon, authenticated;
revoke all on function public._aff_expire()                                  from public, anon, authenticated;
revoke all on function public._aff_decay(text)                               from public, anon, authenticated;
revoke all on function public._aff_moment(text, text, text, text)            from public, anon, authenticated;
revoke all on function public._aff_slot_used(text, text, uuid)               from public, anon, authenticated;
revoke all on function public._aff_are_friends(text, text)                   from public, anon, authenticated;
revoke all on function public._aff_name(text)                                from public, anon, authenticated;

grant execute on function public.affinity_list(text, text)                      to service_role;
grant execute on function public.affinity_detail(text, uuid)                    to service_role;
grant execute on function public.affinity_requests_list(text, boolean)          to service_role;
grant execute on function public.affinity_request(text, text, text, text, text) to service_role;
grant execute on function public.affinity_cancel(text, uuid)                    to service_role;
grant execute on function public.affinity_respond(text, uuid, boolean)          to service_role;
grant execute on function public.affinity_break(text, uuid)                     to service_role;

commit;
