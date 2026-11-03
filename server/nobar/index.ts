// Edge Function `nobar-room`: room nonton bareng + voice chat (maks 5 orang).
//
// Semua aksi butuh Firebase ID Token di header Authorization. UID diambil dari
// token (bukan dari body). Sinkron video & sinyal suara TIDAK lewat function
// ini, tapi lewat Realtime Broadcast di topik `nobar-<room id>`; function ini
// cuma mengurus siapa yang boleh ada di room, siapa host, dan kredensial TURN.
//
// Aksi (body JSON, field `action`):
//   create  {movie_id, episode_id, movie_title?, poster_url?, position_ms?}
//   join    {code} atau {id}
//   get     {id}           -> sekaligus heartbeat (panggil tiap ~30 dtk)
//   leave   {id}
//   kick    {id, uid}      -> host saja, user tidak bisa masuk lagi
//   state   {id, episode_id, position_ms, playing}  -> host saja
//   ice     {id}           -> server STUN/TURN untuk voice
//   list                   -> room aktif yang aku ikuti
//
// Env yang dipakai (sudah otomatis dari .env lewat env_file):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   TURN_URLS   contoh: "turn:turn.zenime.biz.id:3478?transport=udp,turn:turn.zenime.biz.id:3478?transport=tcp"
//   TURN_SECRET static-auth-secret coturn (use-auth-secret)
//   -> SAMAKAN dengan yang dipakai `chess-game` (aksi voice_ice). Kalau nama
//      env di chess-game beda, ganti dua baris TURN_* di bawah.

import { createClient } from "npm:@supabase/supabase-js@2";
import { createLocalJWKSet, jwtVerify } from "npm:jose@5";

const FIREBASE_PROJECT = "zenime-609d0";
const MAX_MEMBERS = 5;
const ACTIVE_MS = 90_000;
const TURN_URLS = (Deno.env.get("TURN_URLS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
const TURN_SECRET = Deno.env.get("TURN_SECRET") ?? "";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

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

// ------------------------------------------------------------------ auth
// JWKS Firebase dibaca dari tabel public.firebase_jwks (diisi cron host,
// karena VPS tidak bisa ke googleapis lewat IPv4). Sama dengan function lain.

let jwksCache: { at: number; set: ReturnType<typeof createLocalJWKSet> } | null = null;

async function getJwks() {
  if (jwksCache && Date.now() - jwksCache.at < 10 * 60_000) return jwksCache.set;
  const { data, error } = await db.from("firebase_jwks").select("jwks").eq("id", 1).maybeSingle();
  if (error || !data?.jwks) throw new HttpError(503, "Server login belum siap, coba lagi");
  const jwks = typeof data.jwks === "string" ? JSON.parse(data.jwks) : data.jwks;
  const set = createLocalJWKSet(jwks);
  jwksCache = { at: Date.now(), set };
  return set;
}

async function verifyUser(req: Request): Promise<string> {
  const h = req.headers.get("Authorization") ?? "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : "";
  if (!token) throw new HttpError(401, "Kamu harus login dulu");
  try {
    const { payload } = await jwtVerify(token, await getJwks(), {
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT}`,
      audience: FIREBASE_PROJECT,
    });
    const uid = payload.sub;
    if (typeof uid !== "string" || !uid) throw new Error("no sub");
    return uid;
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw new HttpError(401, "Sesi login habis, buka ulang aplikasi");
  }
}

// ------------------------------------------------------------------ realtime

/** Kabari semua anggota supaya memuat ulang data room (isi ping tidak dipercaya app). */
async function ping(id: string, reason: string) {
  try {
    await fetch(`${SUPABASE_URL}/realtime/v1/api/broadcast`, {
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
  } catch (_) {
    // App tetap heartbeat tiap 30 dtk, jadi ping yang gagal tidak fatal.
  }
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

async function turnCredentials(uid: string) {
  const servers: Record<string, unknown>[] = [];
  if (TURN_URLS.length && TURN_SECRET) {
    // coturn "use-auth-secret": username = expiry:uid, password = base64(HMAC-SHA1)
    const username = `${Math.floor(Date.now() / 1000) + 6 * 3600}:${uid}`;
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(TURN_SECRET),
      { name: "HMAC", hash: "SHA-1" },
      false,
      ["sign"],
    );
    const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(username));
    const credential = btoa(String.fromCharCode(...new Uint8Array(sig)));
    servers.push({ urls: TURN_URLS, username, credential });
  }
  return { ice_servers: servers, turn_ready: servers.length > 0 };
}

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
      return await turnCredentials(uid);
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
  try {
    const uid = await verifyUser(req);
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
