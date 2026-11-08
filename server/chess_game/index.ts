// Edge Function `chess-game`: catur mabar Zenime.
// Body: { action, ... } dengan Firebase ID Token di header Authorization.
// Aksi: list, live, get, create, join, accept, decline, cancel, move, resign, draw, rematch, voice_ice.
// `live` & `get` oleh bukan-pemain = mode penonton (hanya permainan yang sudah mulai).
//
// Data di tabel public.chess_games (lihat chess_setup.sql), diakses dengan
// service_role. Setelah tiap perubahan, server mengirim ping lewat Realtime
// Broadcast ke topik `chess-game-<id>` dan `chess-user-<uid>`; app lalu memuat
// ulang posisi resmi dari function ini (isi ping tidak pernah dipercaya).

import { AuthError, FirebaseVerifier } from "./auth.ts";
import { ChessService, type Db, DuplicateCode, type Game, GameError, type Notify, type Profile } from "./game.ts";
import { turnConfigFromEnv, turnCredentials } from "./turn.ts";

const SB_URL = (Deno.env.get("SUPABASE_URL") ?? "http://kong:8000").replace(/\/$/, "");
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;

const baseHeaders = {
  apikey: SB_KEY,
  Authorization: `Bearer ${SB_KEY}`,
  "Content-Type": "application/json",
};

async function rest(path: string, init: RequestInit = {}): Promise<Response> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 10_000);
  try {
    return await fetch(`${SB_URL}/rest/v1/${path}`, {
      ...init,
      headers: { ...baseHeaders, ...(init.headers ?? {}) },
      signal: ctrl.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

async function rows<T>(res: Response): Promise<T[]> {
  if (!res.ok) throw new Error(`PostgREST ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const data = await res.json();
  return Array.isArray(data) ? data as T[] : [];
}

const T = "chess_games";

const db: Db = {
  async get(id) {
    return (await rows<Game>(await rest(`${T}?id=eq.${id}&select=*&limit=1`)))[0] ?? null;
  },
  async getByCode(code) {
    return (await rows<Game>(await rest(`${T}?code=eq.${code}&select=*&limit=1`)))[0] ?? null;
  },
  async insert(row) {
    const res = await rest(T, { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(row) });
    if (res.status === 409) {
      const t = await res.text();
      if (t.includes("23505")) throw new DuplicateCode();
      throw new Error(`PostgREST 409: ${t.slice(0, 300)}`);
    }
    const out = await rows<Game>(res);
    if (!out[0]) throw new Error("Insert tidak mengembalikan baris");
    return out[0];
  },
  async updateIf(id, guard, patch) {
    const res = await rest(`${T}?id=eq.${id}&ply=eq.${guard.ply}&status=eq.${guard.status}`, {
      method: "PATCH",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify(patch),
    });
    return (await rows<Game>(res))[0] ?? null;
  },
  async listFor(uid, limit) {
    if (!UID_RE.test(uid)) return [];
    const or = `(white_uid.eq.${uid},black_uid.eq.${uid},creator_uid.eq.${uid},invitee_uid.eq.${uid})`;
    return rows<Game>(await rest(`${T}?or=${encodeURIComponent(or)}&select=*&order=updated_at.desc&limit=${limit}`));
  },
  async listLive(limit) {
    return rows<Game>(await rest(`${T}?status=eq.active&select=*&order=updated_at.desc&limit=${limit}`));
  },
  async findWaitingRematch(gameId) {
    return (await rows<Game>(await rest(`${T}?rematch_of=eq.${gameId}&status=eq.waiting&select=*&limit=1`)))[0] ?? null;
  },
  async isFriend(a, b) {
    if (!UID_RE.test(a) || !UID_RE.test(b)) return false;
    const or = `(and(requester_uid.eq.${a},addressee_uid.eq.${b}),and(requester_uid.eq.${b},addressee_uid.eq.${a}))`;
    const r = await rows<{ id: unknown }>(
      await rest(`friendships?or=${encodeURIComponent(or)}&status=eq.accepted&select=id&limit=1`),
    );
    return r.length > 0;
  },
  async profiles(uids) {
    const list = [...new Set(uids.filter((u) => UID_RE.test(u)))];
    if (list.length === 0) return {};
    try {
      const r = await rows<Profile & { firebase_uid: string }>(await rest(
        `chat_profiles?firebase_uid=in.(${list.join(",")})&select=firebase_uid,username,avatar_url,username_color,user_number`,
      ));
      const out: Record<string, Profile> = {};
      for (const p of r) out[p.firebase_uid] = p;
      return out;
    } catch (e) {
      console.error("chess-game profiles", e);
      return {}; // nama gagal dimuat tidak menggagalkan permainan
    }
  },
};

const notify: Notify = async (topics, payload) => {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 3_000);
  try {
    const res = await fetch(`${SB_URL}/realtime/v1/api/broadcast`, {
      method: "POST",
      headers: baseHeaders,
      body: JSON.stringify({ messages: topics.map((topic) => ({ topic, event: "ping", payload })) }),
      signal: ctrl.signal,
    });
    if (!res.ok) console.error("chess-game broadcast", res.status, (await res.text()).slice(0, 200));
  } catch (e) {
    console.error("chess-game broadcast", e);
  } finally {
    clearTimeout(timer);
  }
};

const verifier = new FirebaseVerifier(async () => {
  const r = await rows<{ jwks: unknown }>(await rest("firebase_jwks?id=eq.1&select=jwks&limit=1"));
  return r[0]?.jwks ?? null;
});

const turn = turnConfigFromEnv((k) => Deno.env.get(k));
if (!turn) console.warn("chess-game: TURN_SECRET/TURN_URLS belum diatur, panggilan suara di data seluler bisa gagal");

const service = new ChessService(db, notify, Date.now, Math.random, async (uid) => {
  if (!turn) return [];
  return [await turnCredentials(uid, turn)];
});

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-firebase-appcheck",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method tidak didukung" }, 405);

  let uid: string;
  try {
    uid = await verifier.verify(req.headers.get("Authorization"));
  } catch (e) {
    if (e instanceof AuthError) return json({ error: e.message }, 401);
    console.error("chess-game auth", e);
    return json({ error: "Login tidak bisa diperiksa, coba lagi" }, 503);
  }

  let body: Record<string, unknown>;
  try {
    const b = await req.json();
    body = b && typeof b === "object" && !Array.isArray(b) ? b : {};
  } catch {
    return json({ error: "Body harus JSON" }, 400);
  }

  try {
    return json(await service.handle(uid, body));
  } catch (e) {
    if (e instanceof GameError) return json({ error: e.message }, e.status);
    console.error("chess-game", body.action, e);
    return json({ error: "Server catur sedang bermasalah, coba lagi" }, 500);
  }
});
