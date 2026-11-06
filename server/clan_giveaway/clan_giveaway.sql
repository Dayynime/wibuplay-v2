-- =====================================================================
-- Giveaway Premium di chat clan.
-- Aturan biaya / kuota / pajak / slot TETAP dari giveaway_create yang sudah
-- ada (tidak diubah). Tambahan di sini:
--   * premium_giveaways.clan_id: null = giveaway global, terisi = khusus clan.
--   * kartu di chat clan = pesan berisi token [giveaway:<id>:<hari>] yang
--     hanya bisa ditulis lewat clan_giveaway_post (trigger menolak token
--     palsu dari user).
--   * klaim giveaway clan hanya untuk anggota clan tsb (dicek Edge Function
--     premium-gift lewat clan_giveaway_check_claim sebelum giveaway_claim).
-- Jalankan:  docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < clan_giveaway.sql
-- =====================================================================
begin;

alter table public.premium_giveaways add column if not exists clan_id text;

-- Dipanggil SEBELUM giveaway_create: pastikan pembuat anggota clan dan tidak
-- di-mute (supaya kartu pasti bisa dikirim). Return clan_id.
create or replace function public.clan_giveaway_prepare(p_uid text)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_clan text;
  m jsonb;
begin
  select clan_id into v_clan from clan_members where firebase_uid = p_uid;
  if v_clan is null then
    raise exception 'Kamu belum gabung clan' using errcode = 'P0001';
  end if;
  if to_regprocedure('public.chat_mute_status(text)') is not null then
    m := chat_mute_status(p_uid);
    if coalesce((m ->> 'muted')::boolean, false) then
      raise exception '%', coalesce(m ->> 'message', 'Kamu sedang di-mute dari chat') using errcode = 'P0001';
    end if;
  end if;
  return v_clan;
end;
$$;

-- Tandai giveaway sebagai milik clan + kirim kartunya ke chat clan.
create or replace function public.clan_giveaway_post(p_uid text, p_id bigint, p_clan text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  g premium_giveaways;
  r clan_messages;
begin
  update premium_giveaways set clan_id = p_clan
   where id = p_id and creator_uid = p_uid
   returning * into g;
  if g.id is null then
    raise exception 'Giveaway tidak ditemukan' using errcode = 'P0001';
  end if;
  perform set_config('zenime.giveaway_post', '1', true);
  insert into clan_messages (clan_id, firebase_uid, message)
  values (p_clan, p_uid, format('[giveaway:%s:%s]', g.id, g.days))
  returning * into r;
  perform set_config('zenime.giveaway_post', '', true);
  return to_jsonb(r);
end;
$$;

-- Klaim giveaway clan: hanya anggota clan itu. Giveaway global lolos.
create or replace function public.clan_giveaway_check_claim(p_uid text, p_id bigint)
returns void language plpgsql stable security definer set search_path = public as $$
declare
  v_clan text;
begin
  select clan_id into v_clan from premium_giveaways where id = p_id;
  if v_clan is null then return; end if;
  if not exists (select 1 from clan_members where firebase_uid = p_uid and clan_id = v_clan) then
    raise exception 'Giveaway ini khusus anggota clan' using errcode = 'P0001';
  end if;
end;
$$;

-- Token kartu giveaway tidak boleh diketik user biasa.
create or replace function private.trg_clan_giveaway_token()
returns trigger language plpgsql as $$
begin
  if new.message ~* '^\s*\[giveaway:' and coalesce(current_setting('zenime.giveaway_post', true), '') <> '1' then
    raise exception 'Pesan tidak valid' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_clan_giveaway_token on public.clan_messages;
create trigger trg_clan_giveaway_token before insert or update of message on public.clan_messages
  for each row execute function private.trg_clan_giveaway_token();

revoke all on function public.clan_giveaway_prepare(text) from public, anon, authenticated;
revoke all on function public.clan_giveaway_post(text, bigint, text) from public, anon, authenticated;
revoke all on function public.clan_giveaway_check_claim(text, bigint) from public, anon, authenticated;
grant execute on function public.clan_giveaway_prepare(text) to service_role;
grant execute on function public.clan_giveaway_post(text, bigint, text) to service_role;
grant execute on function public.clan_giveaway_check_claim(text, bigint) to service_role;

commit;
