-- =====================================================================
-- Pesan disematkan (pin) di Chat Global. Hanya developer / admin /
-- moderator (user_roles) yang bisa sematkan & lepas. Maksimal 5 pesan.
-- Pesan yang dihapus otomatis lepas dari sematan (on delete cascade).
-- Butuh _chat_role_rank dari chat_mute.sql (sudah terpasang).
-- Jalankan:  docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < chat_pin.sql
-- =====================================================================
begin;

create table if not exists public.global_chat_pins (
  message_id bigint primary key references public.global_chat_messages(id) on delete cascade,
  pinned_by  text not null,
  pinned_at  timestamptz not null default now()
);
alter table public.global_chat_pins enable row level security;
revoke all on public.global_chat_pins from anon, authenticated;
grant all on public.global_chat_pins to service_role;

-- Daftar sematan, terbaru dulu.
create or replace function public.chat_pin_list()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.pinned_at desc), '[]'::jsonb)
  from (
    select p.message_id as id, p.pinned_at, m.firebase_uid, m.username, m.message,
           m.message_type, m.created_at
    from global_chat_pins p
    join global_chat_messages m on m.id = p.message_id
  ) x;
$$;

create or replace function public.chat_pin_set(p_actor text, p_id bigint, p_pin boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if _chat_role_rank(p_actor) < 1 then
    raise exception 'Kamu tidak punya akses' using errcode = 'P0001';
  end if;
  if p_pin then
    if not exists (select 1 from global_chat_messages where id = p_id) then
      raise exception 'Pesan tidak ditemukan' using errcode = 'P0001';
    end if;
    if exists (select 1 from global_chat_pins where message_id = p_id) then
      return chat_pin_list();
    end if;
    perform pg_advisory_xact_lock(hashtext('global_chat_pins'));
    if (select count(*) from global_chat_pins) >= 5 then
      raise exception 'Maksimal 5 pesan disematkan. Lepas salah satu dulu.' using errcode = 'P0001';
    end if;
    insert into global_chat_pins (message_id, pinned_by) values (p_id, p_actor);
  else
    delete from global_chat_pins where message_id = p_id;
  end if;
  return chat_pin_list();
end;
$$;

revoke all on function public.chat_pin_list() from public, anon, authenticated;
revoke all on function public.chat_pin_set(text, bigint, boolean) from public, anon, authenticated;
grant execute on function public.chat_pin_list() to service_role;
grant execute on function public.chat_pin_set(text, bigint, boolean) to service_role;

commit;
