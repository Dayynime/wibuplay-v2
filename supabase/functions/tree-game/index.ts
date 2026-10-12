// Edge Function: tree-game (Pohon ZCoin)
//
// UID SELALU diambil dari Firebase ID Token yang diverifikasi di sini.
// Jumlah buah, ZCoin, kuota harian, dan siram dihitung di database (RPC tree_*),
// app cuma mengirim "aksi".
//
// Body: { action: "get" | "harvest" | "upgrade" | "water" | "water_status", ... }
//   harvest -> { count: 1..50 }
//   water   -> { friend_uid: "<uid teman>" }
//   shop | buy { item_id } | equip { item_id, on } | visit { friend_uid }

import { createClient } from "npm:@supabase/supabase-js@2";
import { jwtVerify, decodeProtectedHeader, createRemoteJWKSet, createLocalJWKSet } from "npm:jose@5";

const PID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "zenime-609d0";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const remote = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
  { timeoutDuration: 8000, cacheMaxAge: 3600000 },
);

// ---------- Verifikasi Firebase ID Token (sama dengan zenime-check-premium) ----------
// JWKS dibaca dari tabel public.firebase_jwks (di-sync cron dari host), karena
// container functions tidak bisa akses googleapis.com lewat IPv4.
let cached: { set: ReturnType<typeof createLocalJWKSet>; at: number } | null = null;
async function loadSet(force = false) {
  if (!force && cached && Date.now() - cached.at < 300000) return cached.set;
  const { data } = await sb.from("firebase_jwks").select("jwks").eq("id", 1).maybeSingle();
  const k = (data as { jwks?: { keys?: unknown[] } } | null)?.jwks;
  if (k?.keys?.length) {
    cached = { set: createLocalJWKSet(k as Parameters<typeof createLocalJWKSet>[0]), at: Date.now() };
    return cached.set;
  }
  return cached?.set ?? null;
}
async function verifyToken(tok: string) {
  const opts = { issuer: `https://securetoken.google.com/${PID}`, audience: PID };
  let hadSet = false;
  for (let i = 0; i < 2; i++) {
    const set = await loadSet(i > 0);
    if (!set) break;
    hadSet = true;
    try { return await jwtVerify(tok, set, opts); }
    catch (e) { if ((e as Error)?.name !== "JWKSNoMatchingKey") throw e; }
  }
  if (hadSet) throw new Error("JWKSNoMatchingKey");
  return await jwtVerify(tok, remote, opts);
}

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const ITEM_RE = /^[a-z0-9_]{1,40}$/;

async function tokenUid(req: Request): Promise<string | null> {
  const tok = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (tok.split(".").length !== 3) return null;
  try {
    // anon key Supabase (HS256) dan token asing langsung ditolak
    if (decodeProtectedHeader(tok).alg !== "RS256") return null;
    const { payload } = await verifyToken(tok);
    const uid = typeof payload.sub === "string" ? payload.sub : "";
    return UID_RE.test(uid) ? uid : null;
  } catch {
    return null;
  }
}

// ---------- Premium: baca langsung premium_status (aturan sama dgn zenime-check-premium) ----------
const premiumCache = new Map<string, { value: boolean; exp: number }>();

async function isPremium(uid: string): Promise<boolean> {
  const hit = premiumCache.get(uid);
  if (hit && hit.exp > Date.now()) return hit.value;
  let value = false;
  const { data, error } = await sb.from("premium_status")
    .select("is_premium, expires_at").eq("firebase_uid", uid).maybeSingle();
  if (error) {
    console.error("tree-game premium", error.message);
  } else if (data) {
    const d = data as { is_premium?: boolean; expires_at?: string | null };
    value = d.is_premium === true && (d.expires_at == null || new Date(d.expires_at) > new Date());
  }
  premiumCache.set(uid, { value, exp: Date.now() + 60_000 });
  if (premiumCache.size > 5000) premiumCache.clear();
  return value;
}

// ---------- Rate limit sederhana per UID (per instance) ----------
const hits = new Map<string, { n: number; reset: number }>();
function limited(uid: string): boolean {
  const now = Date.now();
  const h = hits.get(uid);
  if (!h || h.reset < now) {
    hits.set(uid, { n: 1, reset: now + 60_000 });
    if (hits.size > 10000) hits.clear();
    return false;
  }
  h.n++;
  return h.n > 40; // maks 40 request / menit / user
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

async function rpc(fn: string, args: Record<string, unknown>): Promise<Response> {
  const { data, error } = await sb.rpc(fn, args);
  if (error) {
    // P0001 = pesan dari RAISE EXCEPTION kita sendiri -> aman ditampilkan ke user.
    if (error.code === "P0001") return json({ error: error.message }, 400);
    console.error("tree-game", fn, error.message);
    return json({ error: "Server sedang bermasalah, coba lagi nanti." }, 500);
  }
  return json(data);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const uid = await tokenUid(req);
    if (!uid) return json({ error: "Sesi login tidak valid, coba login ulang." }, 401);
    if (limited(uid)) return json({ error: "Pelan-pelan ya, coba lagi sebentar lagi." }, 429);

    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const action = typeof body.action === "string" ? body.action : "get";

    switch (action) {
      case "get":
        return await rpc("tree_get", { p_uid: uid, p_premium: await isPremium(uid) });

      case "harvest": {
        const raw = Number(body.count ?? 1);
        const count = Number.isFinite(raw) ? Math.min(50, Math.max(1, Math.floor(raw))) : 1;
        return await rpc("tree_harvest", { p_uid: uid, p_premium: await isPremium(uid), p_count: count });
      }

      case "upgrade":
        return await rpc("tree_upgrade", { p_uid: uid, p_premium: await isPremium(uid) });

      case "water": {
        const friend = typeof body.friend_uid === "string" ? body.friend_uid.trim() : "";
        if (!UID_RE.test(friend)) return json({ error: "Teman tidak valid" }, 400);
        if (friend === uid) return json({ error: "Nggak bisa nyiram pohon sendiri" }, 400);
        return await rpc("tree_water", {
          p_giver: uid,
          p_receiver: friend,
          p_receiver_premium: await isPremium(friend),
        });
      }

      case "water_status":
        return await rpc("tree_water_status", { p_uid: uid });

      // ---------- Toko dekorasi ----------
      case "shop":
        return await rpc("tree_shop", { p_uid: uid });

      case "buy": {
        const item = typeof body.item_id === "string" ? body.item_id.trim() : "";
        if (!ITEM_RE.test(item)) return json({ error: "Item tidak valid" }, 400);
        return await rpc("tree_buy", { p_uid: uid, p_premium: await isPremium(uid), p_item: item });
      }

      case "equip": {
        const item = typeof body.item_id === "string" ? body.item_id.trim() : "";
        if (!ITEM_RE.test(item)) return json({ error: "Item tidak valid" }, 400);
        return await rpc("tree_equip", { p_uid: uid, p_item: item, p_on: body.on !== false });
      }

      // ---------- Kunjungi pohon teman ----------
      case "visit": {
        const friend = typeof body.friend_uid === "string" ? body.friend_uid.trim() : "";
        if (!UID_RE.test(friend)) return json({ error: "Teman tidak valid" }, 400);
        return await rpc("tree_visit", {
          p_viewer: uid,
          p_owner: friend,
          p_owner_premium: await isPremium(friend),
        });
      }

      default:
        return json({ error: "Aksi tidak dikenal" }, 400);
    }
  } catch (err) {
    console.error("tree-game", (err as Error)?.message);
    return json({ error: "Server sedang bermasalah, coba lagi nanti." }, 500);
  }
});
