import { createClient } from "npm:@supabase/supabase-js@2";
import { jwtVerify, createRemoteJWKSet, createLocalJWKSet } from "npm:jose@5";

const PID = Deno.env.get("FIREBASE_PROJECT_ID")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const remote = createRemoteJWKSet(new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"), { timeoutDuration: 8000, cacheMaxAge: 3600000 });
const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

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

// Cek premium lewat zenime-check-premium (logika premium tetap di satu tempat).
// UID diambil dari token, bukan body -> tidak bisa dipalsukan.
async function isPremium(uid: string): Promise<boolean> {
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/zenime-check-premium`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
      body: JSON.stringify({ firebase_uid: uid }),
      signal: AbortSignal.timeout(6000),
    });
    const d = await res.json().catch(() => null);
    return d?.is_premium === true;
  } catch (e) {
    console.error("csp premium check failed", (e as Error)?.message);
    return false; // kalau cek gagal, perlakukan sebagai non-premium (aman: fitur premium ditolak)
  }
}

const NAME_RE = /^[\p{L}\p{N}_. -]{3,20}$/u;
const CLOUDS = ["jbtwhnrb", "xguzml1n"];
// Supabase Storage (pengganti Cloudinary sejak Nov 2026, upload lewat media-upload).
const STORAGE_HOST = "supabase.zenime.biz.id";
const STORAGE_BUCKET = { avatars: "chat-avatars", banners: "chat-banners" } as const;
const INVISIBLE_RE = /[\u115F\u1160\u3164\uFFA0\u2800\u200B-\u200F\u2060-\u2064\uFEFF\u00AD\u034F\u180E]/u;
const RESERVED = /(admin|developer|moderator|staff|zenime|owner|dayynime)/i;

// URL foto WAJIB persis hasil upload app sendiri:
//   https://res.cloudinary.com/jbtwhnrb/image/upload/v<angka>/<folder>/<uid>-<angka>.<ext>
//   (uploader lama: .../<folder>/<uid>.<ext>)
// Tanpa transformasi (f_auto, w_..), tanpa fetch URL, tanpa query/#, dan uid
// di nama file harus uid PEMILIK TOKEN -> tidak bisa memakai foto orang lain.
const STATIC_EXT = ["jpg", "jpeg"];     // selalu statis
const GIF_EXT = ["gif"];                 // selalu animasi
const SNIFF_EXT = ["png", "webp"];       // bisa statis / animasi -> periksa isi file
const ALL_EXT = [...STATIC_EXT, ...GIF_EXT, ...SNIFF_EXT];
const GIF_PER_DAY = 2;

// Unduh potongan awal file lalu tentukan animasi atau tidak, berdasar ISI
// (bukan ekstensi). Menutup trik APNG (.png animasi) & WebP animasi
// ber-ekstensi statis. File ada di Cloudinary kita sendiri -> aman & cepat.
// Gagal unduh -> dianggap animasi (konservatif): non-Premium ditolak.
async function isAnimatedByContent(url: string): Promise<boolean> {
  let buf: Uint8Array;
  // File di Storage sendiri dibaca lewat jaringan internal (lebih cepat).
  const src = url.startsWith(`https://${STORAGE_HOST}/`)
    ? SUPABASE_URL.replace(/\/$/, "") + url.slice(`https://${STORAGE_HOST}`.length)
    : url;
  try {
    const r = await fetch(src, {
      headers: { Range: "bytes=0-65535" },
      signal: AbortSignal.timeout(6000),
    });
    if (!r.ok && r.status !== 206) return true;
    buf = new Uint8Array(await r.arrayBuffer());
  } catch {
    return true;
  }
  const n = buf.length;
  // APNG: file PNG yang punya chunk "acTL" (animation control).
  if (n > 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) {
    return indexOfAscii(buf, "acTL") !== -1;
  }
  // WebP animasi: "RIFF"...."WEBP", lalu ada chunk "ANIM".
  if (n > 16 && asc(buf, 0) === "RIFF" && asc(buf, 8) === "WEBP") {
    return indexOfAscii(buf, "ANIM") !== -1;
  }
  // Selain itu (GIF sudah ditangani ekstensi, JPEG statis) -> statis.
  return false;
}

function asc(b: Uint8Array, at: number): string {
  return String.fromCharCode(b[at], b[at + 1], b[at + 2], b[at + 3]);
}
function indexOfAscii(b: Uint8Array, s: string): number {
  const t = [...s].map((c) => c.charCodeAt(0));
  outer: for (let i = 0; i + t.length <= b.length; i++) {
    for (let j = 0; j < t.length; j++) if (b[i + j] !== t[j]) continue outer;
    return i;
  }
  return -1;
}

function checkImageUrl(
  url: string,
  folder: "avatars" | "banners",
  uid: string,
): { ok: true; ext: string; url: string } | { ok: false } {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return { ok: false };
  }
  if (u.search || u.hash || u.username || u.password || u.port) return { ok: false };
  // Supabase Storage: /storage/v1/object/public/<bucket>/<uid>/<uid>-<waktu>.<ext>
  if (u.protocol === "https:" && u.hostname === STORAGE_HOST) {
    const s = /^\/storage\/v1\/object\/public\/([a-z-]+)\/([A-Za-z0-9_]{1,128})\/([A-Za-z0-9_]{1,128})-\d{10,14}\.([a-z]{3,4})$/
      .exec(u.pathname);
    if (!s || s[1] !== STORAGE_BUCKET[folder] || s[2] !== uid || s[3] !== uid) return { ok: false };
    if (!ALL_EXT.includes(s[4])) return { ok: false };
    return { ok: true, ext: s[4], url: u.toString() };
  }
  if (u.protocol !== "https:" || u.hostname !== "res.cloudinary.com") return { ok: false };
  // Format baru: <uid>-<waktu>.<ext>; format uploader lama: <uid>.<ext>.
  const m = /^\/([a-z0-9]+)\/image\/upload\/v\d{1,12}\/(avatars|banners)\/([A-Za-z0-9_]{1,128})(?:-\d{10,14})?\.([a-z]{3,4})$/
    .exec(u.pathname);
  if (!m || !CLOUDS.includes(m[1]) || m[2] !== folder || m[3] !== uid) return { ok: false };
  const ext = m[4];
  if (!ALL_EXT.includes(ext)) return { ok: false };
  // Simpan versi URL yang sudah dinormalisasi (mis. "/../" dirapikan).
  return { ok: true, ext, url: u.toString() };
}

// Kuota ganti foto animasi (gabungan avatar + banner) per hari WIB, dicatat di
// tabel profile_media_changes. Tabel belum ada / error -> dicatat di log dan
// tidak memblokir (kuota cuma pembatas tambahan; Premium tetap wajib).
function startOfTodayWib(): string {
  const wib = new Date(Date.now() + 7 * 3600_000);
  return new Date(Date.UTC(wib.getUTCFullYear(), wib.getUTCMonth(), wib.getUTCDate()) - 7 * 3600_000).toISOString();
}

async function animatedUsedToday(uid: string): Promise<number> {
  const { count, error } = await sb.from("profile_media_changes")
    .select("id", { count: "exact", head: true })
    .eq("firebase_uid", uid).gte("created_at", startOfTodayWib());
  if (error) {
    console.error("csp quota read", error.message);
    return 0;
  }
  return count ?? 0;
}
const json = (b: unknown, s = 200) => Response.json(b, { status: s });
const esc = (s: string) => s.replace(/[\\%_]/g, "\\$&");

async function nameTaken(name: string, uid: string) {
  const { data } = await sb.from("chat_profiles").select("firebase_uid")
    .ilike("username", esc(name)).neq("firebase_uid", uid).limit(1);
  return !!data?.length;
}

// Dipakai hanya untuk menandai niat (wantsGifAvatar); keputusan akhir pakai checkImageUrl.
const isGif = (url: unknown) => typeof url === "string" && /\.(gif|webp)/i.test(url);

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let uid: string; let claims: any;
  try {
    const tok = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { payload } = await verifyToken(tok);
    uid = payload.sub!; claims = payload;
    {
      const pv = payload as { email_verified?: boolean; firebase?: { sign_in_provider?: string } };
      if (!(pv.email_verified === true || pv.firebase?.sign_in_provider === "google.com"))
        return json({ error: "Verifikasi email dulu untuk memakai fitur ini" }, 403);
    }
  } catch (e) { console.error("AUTH-FAIL", (e as Error)?.name, (e as Error)?.message); return json({ error: "unauthorized" }, 401); }

  const b = await req.json().catch(() => ({}));
  const { data: cur } = await sb.from("chat_profiles")
    .select("*").eq("firebase_uid", uid).maybeSingle();

  const ch: Record<string, unknown> = {};

  // ---- Deteksi apakah user mencoba memakai fitur KHUSUS PREMIUM ----
  // banner_url (apa pun), avatar GIF, dan username_color = fitur Premium.
  const wantsBanner = b.banner_url !== undefined && b.banner_url !== null && b.banner_url !== (cur?.banner_url ?? null);
  const wantsGifAvatar = b.avatar_url !== undefined && isGif(b.avatar_url) && b.avatar_url !== (cur?.avatar_url ?? null);
  const wantsColor = b.username_color !== undefined && b.username_color !== null && b.username_color !== (cur?.username_color ?? null);

  let premium: boolean | null = null; // cache hasil cek premium
  async function requirePremium(): Promise<boolean> {
    if (premium === null) premium = await isPremium(uid);
    return premium;
  }

  if (typeof b.username === "string" && b.username.trim() !== cur?.username) {
    const u = b.username.trim();
    if (!NAME_RE.test(u)) return json({ error: "Username 3-20 karakter (huruf, angka, _ . - spasi)" }, 400);
    // Karakter "kosong" yang dihitung huruf (Hangul filler) dipakai buat nama
    // tiruan yang kelihatan sama dengan orang lain.
    if (INVISIBLE_RE.test(u)) return json({ error: "Username mengandung karakter tidak terlihat" }, 400);
    if (RESERVED.test(u)) {
      const { data: role } = await sb.from("user_roles")
        .select("role").eq("firebase_uid", uid).maybeSingle();
      if (!["developer", "admin", "moderator"].includes(role?.role ?? "")) return json({ error: "Username tidak diizinkan" }, 400);
    }
    if (await nameTaken(u, uid)) return json({ error: "Username sudah dipakai" }, 409);
    ch.username = u;
  }

  let animatedChanges = 0;
  for (const k of ["avatar_url", "banner_url"]) {
    if (b[k] === undefined || b[k] === (cur?.[k] ?? null)) continue;
    if (b[k] === null) {
      ch[k] = null; // hapus foto/banner selalu boleh
      continue;
    }
    if (typeof b[k] !== "string") return json({ error: `${k} tidak valid` }, 400);
    const chk = checkImageUrl(b[k], k === "avatar_url" ? "avatars" : "banners", uid);
    if (!chk.ok) return json({ error: `${k} tidak valid` }, 400);

    // Animasi ditentukan dari ISI file: GIF selalu animasi; PNG/WebP di-sniff.
    const animated = GIF_EXT.includes(chk.ext) ||
      (SNIFF_EXT.includes(chk.ext) && await isAnimatedByContent(chk.url));

    // banner (apa pun) & foto animasi butuh premium
    if (k === "banner_url" && !(await requirePremium()))
      return json({ error: "Banner profil khusus member Premium" }, 403);
    if (k === "avatar_url" && animated && !(await requirePremium()))
      return json({ error: "Avatar animasi khusus member Premium" }, 403);
    if (animated) animatedChanges++;
    ch[k] = chk.url;
  }
  if (animatedChanges > 0 && (await animatedUsedToday(uid)) + animatedChanges > GIF_PER_DAY) {
    return json({ error: `Jatah ganti foto animasi hari ini habis (maks ${GIF_PER_DAY}x per hari)` }, 429);
  }

  if (b.username_color !== undefined && b.username_color !== (cur?.username_color ?? null)) {
    if (b.username_color !== null && !/^#[0-9a-fA-F]{6}$/.test(b.username_color))
      return json({ error: "Warna tidak valid" }, 400);
    // warna username butuh premium (kecuali menghapus/reset ke null)
    if (b.username_color !== null && !(await requirePremium()))
      return json({ error: "Warna username khusus member Premium" }, 403);
    ch.username_color = b.username_color;
  }

  for (const k of ["favorites_public", "history_public"])
    if (typeof b[k] === "boolean" && b[k] !== cur?.[k]) ch[k] = b[k];

  if (!cur) {
    // Profil baru: tolak field premium kalau non-premium (biar tidak bisa
    // bikin profil langsung ber-banner/GIF/warna tanpa premium).
    if ((wantsBanner || wantsGifAvatar || wantsColor) && !(await requirePremium())) {
      return json({ error: "Banner, avatar GIF, dan warna username khusus member Premium" }, 403);
    }
    let name = ch.username as string | undefined;
    if (!name) {
      const base = String(claims.name ?? "")
        .replace(/[^\p{L}\p{N}_. -]/gu, "").trim().slice(0, 16);
      name = NAME_RE.test(base) && !RESERVED.test(base) ? base : "User";
      if (await nameTaken(name, uid))
        name = `${name.slice(0, 15)}${Math.floor(1000 + Math.random() * 9000)}`;
    }
    const row = {
      firebase_uid: uid, username: name,
      avatar_url: ch.avatar_url ?? claims.picture ?? null,
      banner_url: ch.banner_url ?? null,
      username_color: ch.username_color ?? null,
      favorites_public: ch.favorites_public ?? false,
      history_public: ch.history_public ?? false,
    };
    const { data, error } = await sb.from("chat_profiles")
      .insert(row).select().single();
    if (error) return json({ error: "Gagal membuat profil" }, 500);
    await recordAnimated(uid, animatedChanges);
    return json({ success: true, profile: data });
  }

  if (!Object.keys(ch).length) return json({ success: true, profile: cur });

  if (cur.updated_at && Date.now() - new Date(cur.updated_at).getTime() < 10000)
    return json({ error: "Terlalu cepat, coba lagi sebentar" }, 429);

  const { data, error } = await sb.from("chat_profiles")
    .update({ ...ch, updated_at: new Date().toISOString() })
    .eq("firebase_uid", uid).select().single();
  if (error) return json({ error: "Gagal menyimpan" }, 500);
  await recordAnimated(uid, animatedChanges);
  return json({ success: true, profile: data });
});

async function recordAnimated(uid: string, n: number) {
  if (n <= 0) return;
  const rows = Array.from({ length: n }, () => ({ firebase_uid: uid }));
  const { error } = await sb.from("profile_media_changes").insert(rows);
  if (error) console.error("csp quota write", error.message);
}
