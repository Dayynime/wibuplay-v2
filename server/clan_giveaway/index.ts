import { createClient } from "npm:@supabase/supabase-js@2";
import { jwtVerify, createRemoteJWKSet, createLocalJWKSet } from "npm:jose@5";
import { guardAppCheck } from "../_shared/appcheck.ts";

const PID = Deno.env.get("FIREBASE_PROJECT_ID")!;
const remote = createRemoteJWKSet(new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"), { timeoutDuration: 8000, cacheMaxAge: 3600000 });
const sb = createClient(Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const json = (b: unknown, s = 200) => Response.json(b, { status: s });

// JWKS Firebase disimpan di tabel public.firebase_jwks (di-sync cron dari host),
// karena container functions tidak bisa akses googleapis.com lewat IPv4.
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
  for (let i = 0; i < 2; i++) {
    const set = await loadSet(i > 0);
    if (!set) break;
    try { return await jwtVerify(tok, set, opts); }
    catch (e) { if ((e as Error)?.name !== "JWKSNoMatchingKey") throw e; }
  }
  return await jwtVerify(tok, remote, opts);
}
const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const GLOBAL_COLS = "id,firebase_uid,username,avatar_url,message,created_at,reply_to_id," +
  "reply_to_username,reply_to_message,message_type,audio_url,duration_seconds," +
  "gift_days,gift_recipient_uid,gift_recipient_username,giveaway_id";
const PRIVATE_COLS = "id,sender_uid,recipient_uid,message,created_at,read_at," +
  "reply_to_id,reply_to_sender_uid,reply_to_message,message_type,gift_days";

// Guard request paralel dari uid yang sama.
const inflight = new Set<string>();

// Error dari SQL dengan errcode P0001 = pesan aman untuk user.
function rpcFail(error: { code?: string; message?: string }) {
  if (error.code === "P0001" && error.message) return json({ error: error.message.slice(0, 200) }, 400);
  console.error("GIFT-RPC", error.code, error.message);
  return json({ error: "Terjadi kesalahan server, coba lagi" }, 500);
}

// POST { action: "top_givers", limit? }   (PUBLIK, tanpa login)
// POST { action: "status" }
//   -> kuota gift milik pemanggil
// POST { action: "giveaway_create", days, slots, message?, channel?: "global" | "clan" }
//   -> buat giveaway + kartu di chat global / chat clan (clan: khusus anggota)
// POST { action: "giveaway_claim", giveaway_id }
// POST { action: "giveaway_states", ids: [..] }   (maks 50)
// POST { action: "send", recipient_uid, days: 1..3, channel: "global" | "private" }
//   -> proses gift + taruh bubble gift di chat
Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const b = await req.json().catch(() => ({}));

  // Publik (tanpa login): peringkat Top Giver untuk carousel Beranda.
  if (b.action === "top_givers") {
    const limit = Number.isInteger(b.limit) ? Math.min(Math.max(b.limit, 1), 100) : 50;
    const { data, error } = await sb.rpc("gift_top_givers", { p_limit: limit });
    if (error) return rpcFail(error);
    return new Response(JSON.stringify(data ?? []), {
      headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=60" },
    });
  }

  let uid: string;
  try {
    const tok = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { payload } = await verifyToken(tok);
    uid = payload.sub!;

    // Anti-bot: hanya akun Google atau email yang SUDAH diverifikasi.
    {
      const pv = payload as { email_verified?: boolean; firebase?: { sign_in_provider?: string } };
      if (!(pv.email_verified === true || pv.firebase?.sign_in_provider === "google.com"))
        return json({ error: "Verifikasi email dulu untuk memakai fitur ini" }, 403);
    }
    if (!UID_RE.test(uid)) throw new Error("uid");
  } catch (e) { console.error("AUTH-FAIL", (e as Error)?.name, (e as Error)?.message); return json({ error: "unauthorized" }, 401); }

  // Giveaway lewat waktu -> kembalikan slot tak terklaim (best-effort, tanpa cron).
  if (typeof b.action === "string" && (b.action === "status" || b.action.startsWith("giveaway_"))) {
    const { error: expErr } = await sb.rpc("giveaway_expire_due");
    if (expErr) console.error("GIVEAWAY-EXPIRE", expErr.message);
  }

  if (b.action === "giveaway_states") {
    const ids = Array.isArray(b.ids)
      ? [...new Set(b.ids.map(Number).filter((n: number) => Number.isInteger(n) && n > 0))].slice(0, 50)
      : [];
    if (!ids.length) return json([]);
    const { data, error } = await sb.rpc("giveaway_states", { p_uid: uid, p_ids: ids });
    if (error) return rpcFail(error);
    return json(data);
  }

  if (b.action === "giveaway_claim") {
    const gid = Number(b.giveaway_id);
    if (!Number.isInteger(gid) || gid <= 0) return json({ error: "Giveaway tidak valid" }, 400);
    // App Check: mode "log" cuma dicatat; mode "enforce" menolak claim dari script.
    if (!(await guardAppCheck(req, sb, uid, "giveaway_claim")))
      return json({ error: "Perbarui aplikasi ke versi terbaru untuk ikut giveaway" }, 403);
    if (inflight.has(uid)) return json({ error: "Tunggu sebentar" }, 429);
    inflight.add(uid);
    try {
      // Giveaway clan cuma bisa diklaim anggota clan itu.
      const { error: cErr } = await sb.rpc("clan_giveaway_check_claim", { p_uid: uid, p_id: gid });
      if (cErr) return rpcFail(cErr);
      const { data, error } = await sb.rpc("giveaway_claim", { p_uid: uid, p_id: gid });
      if (error) return rpcFail(error);
      return json({ success: true, claim: data });
    } finally {
      inflight.delete(uid);
    }
  }

  if (b.action === "giveaway_create") {
    const days = Number(b.days);
    const slots = Number(b.slots);
    if (!Number.isInteger(days) || !Number.isInteger(slots)) return json({ error: "Angka tidak valid" }, 400);
    const note = typeof b.message === "string" ? b.message.slice(0, 150) : "";
    const toClan = b.channel === "clan";
    if (inflight.has(uid)) return json({ error: "Tunggu sebentar" }, 429);
    inflight.add(uid);
    try {
      // Giveaway clan: cek anggota clan & tidak di-mute SEBELUM saldo dipotong.
      let clanId: string | null = null;
      if (toClan) {
        const { data: c, error: cErr } = await sb.rpc("clan_giveaway_prepare", { p_uid: uid });
        if (cErr) return rpcFail(cErr);
        clanId = c as string;
      }

      const { data: g, error: gErr } = await sb.rpc("giveaway_create", {
        p_uid: uid, p_days: days, p_slots: slots, p_message: note,
      });
      if (gErr) return rpcFail(gErr);

      if (toClan) {
        const { data: cm, error: pErr } = await sb.rpc("clan_giveaway_post", {
          p_uid: uid, p_id: g.id, p_clan: clanId,
        });
        if (pErr) console.error("GIVEAWAY-CLAN-POST", pErr.code, pErr.message);
        return json({ success: true, giveaway: g, message: null, clan_message: cm ?? null });
      }

      const { data: me } = await sb.from("chat_profiles")
        .select("username,avatar_url").eq("firebase_uid", uid).maybeSingle();
      const text = (g?.message as string | null) || `🎁 Giveaway Premium ${days} hari x ${slots}`;
      const { data: msg, error: mErr } = await sb.from("global_chat_messages").insert({
        firebase_uid: uid, username: me?.username || "Seseorang", avatar_url: me?.avatar_url ?? null,
        message: text, message_type: "giveaway", gift_days: days, giveaway_id: g.id,
      }).select(GLOBAL_COLS).single();
      if (mErr) console.error("GIVEAWAY-BUBBLE", mErr.message);
      else await sb.rpc("giveaway_attach_message", { p_id: g.id, p_msg_id: msg.id });

      return json({ success: true, giveaway: g, message: msg ?? null });
    } finally {
      inflight.delete(uid);
    }
  }

  if (b.action === "status") {
    const { data, error } = await sb.rpc("gift_quota_status", { p_uid: uid });
    if (error) return rpcFail(error);
    return json(data);
  }

  if (b.action !== "send") return json({ error: "action tidak dikenal" }, 400);

  const other = String(b.recipient_uid ?? "");
  const days = Number(b.days);
  const channel = b.channel === "private" ? "private" : b.channel === "global" ? "global" : "";
  if (!UID_RE.test(other) || other === uid) return json({ error: "Penerima tidak valid" }, 400);
  if (!Number.isInteger(days)) return json({ error: "Jumlah hari tidak valid" }, 400);
  if (!channel) return json({ error: "Channel tidak valid" }, 400);

  if (inflight.has(uid)) return json({ error: "Tunggu sebentar" }, 429);
  inflight.add(uid);
  try {
    // Chat pribadi tetap khusus teman (sama dengan private-chat).
    if (channel === "private") {
      const { data: f } = await sb.from("friendships").select("id")
        .eq("status", "accepted")
        .or(`and(requester_uid.eq.${uid},addressee_uid.eq.${other}),and(requester_uid.eq.${other},addressee_uid.eq.${uid})`)
        .limit(1);
      if (!f?.length) return json({ error: "Kalian belum berteman" }, 403);
    }

    // 1) Proses gift (semua aturan dicek di SQL, atomik)
    const { data: g, error: gErr } = await sb.rpc("gift_premium", {
      p_sender: uid, p_recipient: other, p_days: days, p_channel: channel,
    });
    if (gErr) return rpcFail(gErr);

    // 2) Bubble gift. Gagal di sini TIDAK membatalkan gift (sudah tercatat).
    const { data: profs } = await sb.from("chat_profiles")
      .select("firebase_uid,username,avatar_url").in("firebase_uid", [uid, other]);
    const me = profs?.find((p) => p.firebase_uid === uid);
    const them = profs?.find((p) => p.firebase_uid === other);
    const myName = me?.username || "Seseorang";
    const theirName = them?.username || "pengguna";

    let message: unknown = null;
    if (channel === "global") {
      const { data, error } = await sb.from("global_chat_messages").insert({
        firebase_uid: uid, username: myName, avatar_url: me?.avatar_url ?? null,
        message: `🎁 memberi Premium ${days} hari ke ${theirName}`,
        message_type: "gift", gift_days: days,
        gift_recipient_uid: other, gift_recipient_username: theirName,
      }).select(GLOBAL_COLS).single();
      if (error) console.error("GIFT-BUBBLE-GLOBAL", error.message); else message = data;
    } else {
      const { data, error } = await sb.from("private_messages").insert({
        sender_uid: uid, recipient_uid: other,
        message: `🎁 Memberi Premium ${days} hari`,
        message_type: "gift", gift_days: days,
      }).select(PRIVATE_COLS).single();
      if (error) console.error("GIFT-BUBBLE-PRIVATE", error.message); else message = data;
    }

    return json({ success: true, gift: g, message });
  } finally {
    inflight.delete(uid);
  }
});
