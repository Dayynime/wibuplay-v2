// Edge Function `nobar-room`: room nonton bareng + voice chat (maks 5 orang).
//
// Semua aksi butuh Firebase ID Token di header Authorization. UID diambil dari
// token (bukan dari body). Sinkron video & sinyal suara TIDAK lewat function
// ini, tapi lewat Realtime Broadcast di topik `nobar-<room id>`; function ini
// cuma mengurus siapa yang boleh ada di room, siapa host, dan kredensial TURN.
//
// Aksi (body JSON, field `action`):
//   create  {movie_id, episode_id, movie_title?, poster_url?, position_ms?}
//   join    {code} atau {id}  (id cuma untuk kembali ke room yang aku ikuti)
//   get     {id}           -> sekaligus heartbeat (panggil tiap ~30 dtk)
//   leave   {id}
//   kick    {id, uid}      -> host saja, user tidak bisa masuk lagi
//   state   {id, episode_id, position_ms, playing}  -> host saja
//   ice     {id}           -> server STUN/TURN untuk voice
//   list                   -> room aktif yang aku ikuti
//   public_list            -> semua room yang sedang nobar (TANPA id & kode;
//                             masuk tetap wajib pakai kode dari host)
//   invite        {id, uid}           -> undang teman (notif + push)
//   invite_respond {invite_id, accept} -> terima (masuk room) / tolak
//   my_invites                        -> undangan yang masih menunggu jawabanku
//   chat      {id, message}           -> kirim chat ke room (anggota saja)
//   chat_list {id, after?}            -> pesan setelah id `after` (0 = 50 terakhir)
//
// Login & database memakai helper bersama `_shared/wp.ts` (db service role,
// verifyUser lewat tabel firebase_jwks). Kredensial TURN memakai `turn.ts`
// yang SAMA dengan chess-game (disalin ke folder ini saat deploy), membaca
// env TURN_SECRET & TURN_URLS dari .env.

import { db, verifyUser } from "../_shared/wp.ts";
import { turnConfigFromEnv, turnCredentials } from "./turn.ts";

const MAX_MEMBERS = 5;
const ACTIVE_MS = 90_000;

const SB_URL = (Deno.env.get("SUPABASE_URL") ?? "http://kong:8000").replace(/\/$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const turn = turnConfigFromEnv((k: string) => Deno.env.get(k));
if (!turn) console.warn("nobar-room: TURN_SECRET/TURN_URLS belum diatur, voice di data seluler bisa gagal");

// ------------------------------------------------------------------ util

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function str(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const s = v.trim();
  if (!s || s.length > max) return null;
  return s;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function roomId(v: unknown): string {
  if (typeof v !== "string" || !UUID_RE.test(v)) throw new HttpError(400, "Room tidak valid");
  return v.toLowerCase();
}

// ------------------------------------------------------------------ realtime

/** Kabari semua anggota supaya memuat ulang data room (isi ping tidak dipercaya app). */
async function ping(id: string, reason: string) {
  try {
    const res = await fetch(`${SB_URL}/realtime/v1/api/broadcast`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
      },
      body: JSON.stringify({
        messages: [{ topic: `nobar-${id}`, event: "ping", payload: { reason, at: Date.now() } }],
      }),
    });
    if (!res.ok) console.error("nobar-room broadcast", res.status, (await res.text()).slice(0, 200));
  } catch (_) {
    // App tetap heartbeat tiap 30 dtk, jadi ping yang gagal tidak fatal.
  }
}

/** Kabari anggota ada chat baru. Isinya cuma id; app mengambil pesan lewat
 *  `chat_list`, jadi broadcast palsu dari luar tidak bisa memalsukan isi chat. */
async function chatPing(id: string, lastId: number) {
  try {
    await fetch(`${SB_URL}/realtime/v1/api/broadcast`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
      },
      body: JSON.stringify({
        messages: [{ topic: `nobar-${id}`, event: "chat", payload: { last_id: lastId, at: Date.now() } }],
      }),
    });
  } catch (_) {
    // App juga menarik chat tiap heartbeat, jadi ping yang gagal tidak fatal.
  }
}

// ------------------------------------------------------------------ chat

const CHAT_MAX = 300;
const CHAT_BURST = 5;        // maks pesan per 10 detik per orang
const CHAT_PER_MINUTE = 20;  // maks pesan per menit per orang

function cleanChat(v: unknown): string | null {
  if (typeof v !== "string") return null;
  // Buang karakter kontrol (kecuali baris baru), rapikan spasi berlebih.
  const s = v.replace(/[\u0000-\u0009\u000B-\u001F\u007F]/g, "").replace(/\n{3,}/g, "\n\n").trim();
  if (!s || s.length > CHAT_MAX) return null;
  return s;
}

async function chatRows(id: string, after: number) {
  let q = db.from("nobar_messages").select("id, firebase_uid, message, created_at").eq("room_id", id);
  q = after > 0
    ? q.gt("id", after).order("id", { ascending: true }).limit(100)
    : q.order("id", { ascending: false }).limit(50);
  const { data, error } = await q;
  if (error) throw new HttpError(500, "Gagal memuat chat");
  const rows = (data ?? []).slice();
  if (after <= 0) rows.reverse();
  const uids = [...new Set(rows.map((r) => r.firebase_uid))];
  const profiles = new Map<string, Record<string, unknown>>();
  if (uids.length) {
    const { data: ps } = await db
      .from("chat_profiles")
      .select("firebase_uid, username, avatar_url, username_color")
      .in("firebase_uid", uids);
    for (const p of ps ?? []) profiles.set(p.firebase_uid, p);
  }
  return rows.map((r) => {
    const p = profiles.get(r.firebase_uid) ?? {};
    return {
      id: r.id,
      uid: r.firebase_uid,
      username: (p.username as string | undefined)?.trim() || "Pengguna",
      avatar_url: p.avatar_url ?? null,
      username_color: p.username_color ?? null,
      message: r.message,
      created_at: r.created_at,
    };
  });
}

// ------------------------------------------------------------------ data

async function loadRoom(id: string) {
  const { data: room, error } = await db.from("nobar_rooms").select("*").eq("id", id).maybeSingle();
  if (error) throw new HttpError(500, "Gagal memuat room");
  if (!room || room.closed_at) throw new HttpError(404, "Room sudah ditutup");

  const { data: members } = await db
    .from("nobar_members")
    .select("firebase_uid, joined_at, last_seen")
    .eq("room_id", id)
    .order("joined_at", { ascending: true });
  const list = members ?? [];
  const uids = list.map((m) => m.firebase_uid);
  const profiles = new Map<string, Record<string, unknown>>();
  if (uids.length) {
    const { data: rows } = await db
      .from("chat_profiles")
      .select("firebase_uid, username, avatar_url, username_color")
      .in("firebase_uid", uids);
    for (const r of rows ?? []) profiles.set(r.firebase_uid, r);
  }
  const now = Date.now();
  return {
    id: room.id,
    code: room.code,
    host_uid: room.host_uid,
    movie_id: room.movie_id,
    movie_title: room.movie_title,
    poster_url: room.poster_url,
    episode_id: room.episode_id,
    position_ms: room.position_ms,
    playing: room.playing,
    state_at: room.state_at,
    server_now: new Date().toISOString(),
    max_members: MAX_MEMBERS,
    members: list.map((m) => {
      const p = profiles.get(m.firebase_uid) ?? {};
      return {
        uid: m.firebase_uid,
        username: p.username ?? null,
        avatar_url: p.avatar_url ?? null,
        username_color: p.username_color ?? null,
        joined_at: m.joined_at,
        active: now - new Date(m.last_seen).getTime() < ACTIVE_MS,
      };
    }),
  };
}

async function isMember(id: string, uid: string) {
  const { data } = await db
    .from("nobar_members")
    .select("firebase_uid")
    .eq("room_id", id)
    .eq("firebase_uid", uid)
    .maybeSingle();
  return !!data;
}

async function requireHost(id: string, uid: string) {
  const { data } = await db.from("nobar_rooms").select("host_uid, closed_at").eq("id", id).maybeSingle();
  if (!data || data.closed_at) throw new HttpError(404, "Room sudah ditutup");
  if (data.host_uid !== uid) throw new HttpError(403, "Cuma host yang bisa melakukan ini");
}

/** Satu user cuma boleh ada di satu room: keluar dari room lain. */
async function leaveOthers(uid: string, keep: string) {
  const { data } = await db.from("nobar_members").select("room_id").eq("firebase_uid", uid);
  for (const r of data ?? []) {
    if (r.room_id === keep) continue;
    await db.rpc("nobar_leave", { p_room: r.room_id, p_uid: uid });
    await ping(r.room_id, "leave");
  }
}

const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function newCode() {
  const b = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(b, (x) => CODE_CHARS[x % CODE_CHARS.length]).join("");
}

async function iceServers(uid: string) {
  if (!turn) return { ice_servers: [], turn_ready: false };
  return { ice_servers: [await turnCredentials(uid, turn)], turn_ready: true };
}


const INVITE_TTL_MS = 3 * 3600_000;
const INVITE_COOLDOWN_MS = 2 * 60_000;

async function isFriend(a: string, b: string) {
  const { data } = await db
    .from("friendships")
    .select("id")
    .eq("status", "accepted")
    .or(`and(requester_uid.eq.${a},addressee_uid.eq.${b}),and(requester_uid.eq.${b},addressee_uid.eq.${a})`)
    .limit(1);
  return (data ?? []).length > 0;
}

async function displayName(uid: string) {
  const { data } = await db.from("chat_profiles").select("username").eq("firebase_uid", uid).maybeSingle();
  const n = (data?.username ?? "").trim();
  return n || "Temanmu";
}

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;

// ------------------------------------------------------------------ aksi

async function handle(uid: string, body: Record<string, unknown>) {
  const action = body.action;

  switch (action) {
    case "create": {
      const movieId = str(body.movie_id, 200);
      const episodeId = str(body.episode_id, 300);
      if (!movieId || !episodeId) throw new HttpError(400, "Anime / episode tidak valid");
      const pos = Math.max(0, Math.min(Number(body.position_ms) || 0, 6 * 3600_000));

      // Bersih-bersih room lama yang sudah tutup > 1 hari.
      await db.from("nobar_rooms").delete().lt("closed_at", new Date(Date.now() - 86400_000).toISOString());

      let created: { id: string } | null = null;
      for (let i = 0; i < 5 && !created; i++) {
        const { data, error } = await db
          .from("nobar_rooms")
          .insert({
            code: newCode(),
            host_uid: uid,
            movie_id: movieId,
            movie_title: str(body.movie_title, 200),
            poster_url: str(body.poster_url, 500),
            episode_id: episodeId,
            position_ms: Math.round(pos),
            playing: false,
          })
          .select("id")
          .single();
        if (!error) created = data;
        else if (error.code !== "23505") throw new HttpError(500, "Gagal membuat room");
      }
      if (!created) throw new HttpError(500, "Gagal membuat room, coba lagi");
      await db.from("nobar_members").insert({ room_id: created.id, firebase_uid: uid });
      await leaveOthers(uid, created.id);
      return { room: await loadRoom(created.id) };
    }

    case "join": {
      let id: string | null = null;
      if (body.id != null) {
        id = roomId(body.id);
        // Lewat id hanya untuk kembali ke room sendiri; orang lain wajib kode.
        if (!(await isMember(id, uid))) throw new HttpError(403, "Masuk pakai kode room dari host");
      } else {
        const code = str(body.code, 12)?.toUpperCase().replace(/[^A-Z0-9]/g, "");
        if (!code || code.length !== 6) throw new HttpError(400, "Kode room harus 6 karakter");
        const { data } = await db
          .from("nobar_rooms")
          .select("id")
          .eq("code", code)
          .is("closed_at", null)
          .maybeSingle();
        if (!data) throw new HttpError(404, "Room tidak ditemukan atau sudah ditutup");
        id = data.id;
      }
      const { data: res, error } = await db.rpc("nobar_join", { p_room: id, p_uid: uid, p_max: MAX_MEMBERS });
      if (error) throw new HttpError(500, "Gagal masuk room");
      if (res === "closed") throw new HttpError(404, "Room sudah ditutup");
      if (res === "banned") throw new HttpError(403, "Kamu sudah dikeluarkan dari room ini");
      if (res === "full") throw new HttpError(409, `Room penuh (maksimal ${MAX_MEMBERS} orang)`);
      await leaveOthers(uid, id!);
      await ping(id!, "join");
      return { room: await loadRoom(id!) };
    }

    case "get": {
      const id = roomId(body.id);
      const { data: res, error } = await db.rpc("nobar_touch", { p_room: id, p_uid: uid });
      if (error) throw new HttpError(500, "Gagal memuat room");
      if (res === "closed") throw new HttpError(404, "Room sudah ditutup");
      if (res === "not_member") throw new HttpError(403, "Kamu sudah tidak ada di room ini");
      if (res === "ok_changed") await ping(id, "host");
      return { room: await loadRoom(id) };
    }

    case "leave": {
      const id = roomId(body.id);
      await db.rpc("nobar_leave", { p_room: id, p_uid: uid });
      await ping(id, "leave");
      return { ok: true };
    }

    case "kick": {
      const id = roomId(body.id);
      const target = str(body.uid, 128);
      if (!target || target === uid) throw new HttpError(400, "User tidak valid");
      await requireHost(id, uid);
      await db.from("nobar_bans").upsert({ room_id: id, firebase_uid: target });
      await db.rpc("nobar_leave", { p_room: id, p_uid: target });
      await ping(id, "kick");
      return { room: await loadRoom(id) };
    }

    case "state": {
      const id = roomId(body.id);
      const episodeId = str(body.episode_id, 300);
      if (!episodeId) throw new HttpError(400, "Episode tidak valid");
      await requireHost(id, uid);
      const pos = Math.max(0, Math.min(Number(body.position_ms) || 0, 6 * 3600_000));
      await db
        .from("nobar_rooms")
        .update({
          episode_id: episodeId,
          position_ms: Math.round(pos),
          playing: body.playing === true,
          state_at: new Date().toISOString(),
        })
        .eq("id", id);
      await db.from("nobar_members").update({ last_seen: new Date().toISOString() })
        .eq("room_id", id).eq("firebase_uid", uid);
      return { ok: true };
    }

    case "ice": {
      const id = roomId(body.id);
      if (!(await isMember(id, uid))) throw new HttpError(403, "Kamu tidak ada di room ini");
      return await iceServers(uid);
    }

    case "invite": {
      const id = roomId(body.id);
      const target = str(body.uid, 128);
      if (!target || !UID_RE.test(target) || target === uid) throw new HttpError(400, "User tidak valid");
      if (!(await isMember(id, uid))) throw new HttpError(403, "Kamu tidak ada di room ini");
      const room = await loadRoom(id);
      if (room.members.some((m) => m.uid === target)) throw new HttpError(409, "Dia sudah ada di room");
      if (room.members.length >= MAX_MEMBERS) throw new HttpError(409, `Room penuh (maksimal ${MAX_MEMBERS} orang)`);
      if (!(await isFriend(uid, target))) throw new HttpError(403, "Cuma bisa mengundang teman");
      const { data: ban } = await db.from("nobar_bans").select("room_id").eq("room_id", id).eq("firebase_uid", target).maybeSingle();
      if (ban) throw new HttpError(403, "Dia sudah dikeluarkan dari room ini");

      const { data: last } = await db
        .from("nobar_invites")
        .select("id, created_at")
        .eq("room_id", id)
        .eq("to_uid", target)
        .eq("status", "pending")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (last && Date.now() - new Date(last.created_at).getTime() < INVITE_COOLDOWN_MS) {
        throw new HttpError(429, "Undangan sudah dikirim, tunggu sebentar");
      }
      if (last) {
        await db.from("nobar_invites").update({ status: "declined", responded_at: new Date().toISOString() }).eq("id", last.id);
        await db.rpc("nobar_close_invite_notif", { p_invite: last.id, p_expired: true });
      }

      const { data: inv, error } = await db
        .from("nobar_invites")
        .insert({ room_id: id, from_uid: uid, to_uid: target })
        .select("id")
        .single();
      if (error || !inv) throw new HttpError(500, "Gagal mengirim undangan");

      const name = await displayName(uid);
      const title = room.movie_title ? `"${room.movie_title}"` : "anime";
      const { error: nErr } = await db.rpc("nobar_notify", {
        p_to: target,
        p_from: uid,
        p_type: "nobar_invite",
        p_title: "Ajakan Nobar",
        p_body: `${name} ngajak kamu nobar ${title}`,
        p_data: {
          invite_id: inv.id,
          room_id: id,
          from_name: name,
          movie_title: room.movie_title ?? "",
          poster_url: room.poster_url ?? "",
        },
      });
      if (nErr) console.error("nobar-room notify", nErr.message);
      return { ok: true };
    }

    case "invite_respond": {
      const inviteId = roomId(body.invite_id);
      const accept = body.accept === true;
      const { data: inv } = await db.from("nobar_invites").select("*").eq("id", inviteId).maybeSingle();
      if (!inv || inv.to_uid !== uid) throw new HttpError(404, "Undangan tidak ditemukan");
      if (inv.status !== "pending") throw new HttpError(410, "Undangan ini sudah dijawab");
      const expired = Date.now() - new Date(inv.created_at).getTime() > INVITE_TTL_MS;
      const { data: room } = await db.from("nobar_rooms").select("closed_at").eq("id", inv.room_id).maybeSingle();
      if (expired || !room || room.closed_at) {
        await db.from("nobar_invites").update({ status: "declined", responded_at: new Date().toISOString() }).eq("id", inviteId);
        await db.rpc("nobar_close_invite_notif", { p_invite: inviteId, p_expired: true });
        throw new HttpError(410, "Undangan sudah tidak berlaku (room sudah ditutup)");
      }

      if (!accept) {
        await db.from("nobar_invites").update({ status: "declined", responded_at: new Date().toISOString() }).eq("id", inviteId);
        await db.rpc("nobar_close_invite_notif", { p_invite: inviteId, p_expired: false });
        const name = await displayName(uid);
        await db.rpc("nobar_notify", {
          p_to: inv.from_uid,
          p_from: uid,
          p_type: "nobar_declined",
          p_title: "Ajakan nobar ditolak",
          p_body: `${name} belum bisa ikut nobar`,
          p_data: { room_id: inv.room_id },
        });
        return { ok: true };
      }

      const { data: res, error } = await db.rpc("nobar_join", { p_room: inv.room_id, p_uid: uid, p_max: MAX_MEMBERS });
      if (error) throw new HttpError(500, "Gagal masuk room");
      if (res === "closed") throw new HttpError(410, "Room sudah ditutup");
      if (res === "banned") throw new HttpError(403, "Kamu sudah dikeluarkan dari room ini");
      if (res === "full") throw new HttpError(409, `Room penuh (maksimal ${MAX_MEMBERS} orang)`);
      await db.from("nobar_invites").update({ status: "accepted", responded_at: new Date().toISOString() }).eq("id", inviteId);
      await db.rpc("nobar_close_invite_notif", { p_invite: inviteId, p_expired: false });
      await leaveOthers(uid, inv.room_id);
      await ping(inv.room_id, "join");
      return { room: await loadRoom(inv.room_id) };
    }

    case "my_invites": {
      const since = new Date(Date.now() - INVITE_TTL_MS).toISOString();
      const { data } = await db
        .from("nobar_invites")
        .select("id, room_id, from_uid, created_at")
        .eq("to_uid", uid)
        .eq("status", "pending")
        .gte("created_at", since)
        .order("created_at", { ascending: false })
        .limit(10);
      const out = [];
      for (const inv of data ?? []) {
        const { data: room } = await db
          .from("nobar_rooms")
          .select("movie_title, poster_url, closed_at")
          .eq("id", inv.room_id)
          .maybeSingle();
        if (!room || room.closed_at) continue;
        out.push({
          invite_id: inv.id,
          room_id: inv.room_id,
          from_name: await displayName(inv.from_uid),
          movie_title: room.movie_title ?? "",
          poster_url: room.poster_url ?? "",
        });
      }
      return { invites: out };
    }

    case "chat": {
      const id = roomId(body.id);
      const message = cleanChat(body.message);
      if (!message) throw new HttpError(400, `Pesan 1-${CHAT_MAX} karakter`);
      if (!(await isMember(id, uid))) throw new HttpError(403, "Kamu tidak ada di room ini");
      const { data: banned } = await db.from("banned_accounts").select("firebase_uid").eq("firebase_uid", uid).maybeSingle();
      if (banned) throw new HttpError(403, "Akun ini diblokir");

      const since = (ms: number) => new Date(Date.now() - ms).toISOString();
      const count = async (ms: number) => {
        const { count: n } = await db.from("nobar_messages").select("id", { count: "exact", head: true })
          .eq("room_id", id).eq("firebase_uid", uid).gte("created_at", since(ms));
        return n ?? 0;
      };
      if ((await count(10_000)) >= CHAT_BURST || (await count(60_000)) >= CHAT_PER_MINUTE) {
        throw new HttpError(429, "Pelan-pelan ya, tunggu sebentar sebelum kirim lagi");
      }

      const { data: row, error } = await db.from("nobar_messages")
        .insert({ room_id: id, firebase_uid: uid, message })
        .select("id").single();
      if (error || !row) throw new HttpError(500, "Gagal mengirim pesan");
      await chatPing(id, row.id);
      return { id: row.id };
    }

    case "chat_list": {
      const id = roomId(body.id);
      if (!(await isMember(id, uid))) throw new HttpError(403, "Kamu tidak ada di room ini");
      const after = Math.max(0, Math.floor(Number(body.after) || 0));
      return { messages: await chatRows(id, after) };
    }

    case "public_list": {
      // Room yang masih ada anggota aktif (heartbeat < 90 dtk), terbaru dulu.
      const since = new Date(Date.now() - ACTIVE_MS).toISOString();
      const { data: act, error } = await db
        .from("nobar_members")
        .select("room_id, firebase_uid, joined_at")
        .gte("last_seen", since)
        .order("joined_at", { ascending: true })
        .limit(500);
      if (error) throw new HttpError(500, "Gagal memuat daftar nobar");
      const byRoom = new Map<string, string[]>();
      for (const m of act ?? []) {
        const l = byRoom.get(m.room_id) ?? [];
        l.push(m.firebase_uid);
        byRoom.set(m.room_id, l);
      }
      if (!byRoom.size) return { rooms: [] };
      const { data: rooms } = await db
        .from("nobar_rooms")
        .select("id, host_uid, movie_title, poster_url, created_at")
        .in("id", [...byRoom.keys()])
        .is("closed_at", null)
        .order("created_at", { ascending: false })
        .limit(40);
      const list = rooms ?? [];
      const uids = new Set<string>();
      for (const r of list) {
        uids.add(r.host_uid);
        for (const u of byRoom.get(r.id) ?? []) uids.add(u);
      }
      const profiles = new Map<string, Record<string, unknown>>();
      if (uids.size) {
        const { data: ps } = await db
          .from("chat_profiles")
          .select("firebase_uid, username, avatar_url, username_color")
          .in("firebase_uid", [...uids]);
        for (const p of ps ?? []) profiles.set(p.firebase_uid, p);
      }
      const person = (u: string) => {
        const p = profiles.get(u) ?? {};
        return {
          uid: u,
          username: (p.username as string | undefined)?.trim() || "Pengguna",
          avatar_url: p.avatar_url ?? null,
          username_color: p.username_color ?? null,
        };
      };
      return {
        max_members: MAX_MEMBERS,
        rooms: list.map((r) => {
          const members = byRoom.get(r.id) ?? [];
          return {
            // Sengaja tanpa id & kode room: masuk tetap lewat kode dari host.
            movie_title: r.movie_title,
            poster_url: r.poster_url,
            created_at: r.created_at,
            host: person(r.host_uid),
            members: members.map(person),
            member_count: members.length,
            is_member: members.includes(uid),
          };
        }),
      };
    }

    case "list": {
      const { data } = await db.from("nobar_members").select("room_id").eq("firebase_uid", uid);
      const rooms = [];
      for (const r of data ?? []) {
        try {
          rooms.push(await loadRoom(r.room_id));
        } catch (_) { /* room tutup */ }
      }
      return { rooms };
    }
  }
  throw new HttpError(400, "Aksi tidak dikenal");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  let uid: string;
  try {
    ({ uid } = await verifyUser(req));
  } catch (e) {
    const status = typeof (e as { status?: unknown })?.status === "number" ? (e as { status: number }).status : 401;
    const msg = e instanceof Error && e.message ? e.message : "Kamu harus login dulu";
    return json({ error: msg }, status);
  }
  try {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      throw new HttpError(400, "Body tidak valid");
    }
    return json(await handle(uid, body ?? {}));
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("nobar-room", e);
    return json({ error: "Server bermasalah, coba lagi" }, 500);
  }
});
