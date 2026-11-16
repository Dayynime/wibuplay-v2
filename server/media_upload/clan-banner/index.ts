// Edge Function `clan-banner`: ganti / hapus banner clan (khusus leader).
// Aturan leader ada di SQL (clan_banner.sql); function ini memverifikasi
// login, memvalidasi URL, lalu memanggil RPC.
//
// Body JSON:
//   { clan_id, banner_url }   banner_url "" = hapus banner
// UID pemanggil selalu dari Firebase ID Token, BUKAN dari body.

import { db, verifyUser } from "../_shared/wp.ts";

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

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Hanya gambar dari akun Cloudinary app sendiri (sama dengan foto/banner profil).
const CLOUDINARY = /^https:\/\/res\.cloudinary\.com\/xguzml1n\/image\/upload\/[A-Za-z0-9_\-./,]+\.(jpg|jpeg|png|webp|gif)$/i;
// Supabase Storage (pengganti Cloudinary): banner hanya dari folder clan ini sendiri.
const STORAGE = /^https:\/\/supabase\.zenime\.biz\.id\/storage\/v1\/object\/public\/clan-media\/banners\/([0-9a-f-]{36})-\d{10,14}\.(jpg|jpeg|png|webp|gif)$/i;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  let uid: string;
  try {
    ({ uid } = await verifyUser(req));
  } catch (e) {
    const status = typeof (e as { status?: unknown })?.status === "number" ? (e as { status: number }).status : 401;
    return json({ error: e instanceof Error && e.message ? e.message : "Kamu harus login dulu" }, status);
  }

  try {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      throw new HttpError(400, "Body tidak valid");
    }
    const clanId = typeof body.clan_id === "string" && UUID.test(body.clan_id) ? body.clan_id : null;
    if (!clanId) throw new HttpError(400, "Clan tidak valid");
    const url = typeof body.banner_url === "string" ? body.banner_url.trim() : "";
    if (url) {
      const st = STORAGE.exec(url);
      const okStorage = !!st && st[1].toLowerCase() === clanId.toLowerCase();
      if (url.length > 500 || !(okStorage || CLOUDINARY.test(url))) {
        throw new HttpError(400, "Link banner tidak valid");
      }
    }

    const { data, error } = await db.rpc("update_clan_banner", {
      p_actor_uid: uid,
      p_clan_id: clanId,
      p_banner_url: url,
    });
    if (error) {
      if (error.code === "P0001" && error.message) throw new HttpError(400, error.message);
      console.error("clan-banner", error.code, error.message);
      throw new HttpError(500, "Server bermasalah, coba lagi");
    }
    return json({ clan: data });
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("clan-banner", e);
    return json({ error: "Server bermasalah, coba lagi" }, 500);
  }
});
