// Edge Function `clan-daily`: absen harian clan (ZCoin naik sesuai streak) +
// bonus bareng. Semua aturan & angka ada di SQL (clan_daily.sql); function ini
// cuma memverifikasi login, cek email terverifikasi, lalu memanggil RPC.
//
// Body JSON: { "action": "state" | "checkin" | "bonus" }
// UID selalu dari Firebase ID Token (header Authorization), BUKAN dari body.

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

/** Isi token yang SUDAH diverifikasi verifyUser (cuma dibaca, tidak dipercaya mentah). */
function tokenClaims(token: string): Record<string, unknown> {
  try {
    const part = token.split(".")[1];
    const b64 = part.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((part.length + 3) % 4);
    return JSON.parse(atob(b64));
  } catch {
    return {};
  }
}

const MESSAGES: Record<string, [number, string]> = {
  not_member: [403, "Kamu belum bergabung ke clan"],
  joined_today: [403, "Baru gabung clan hari ini. Absen bisa mulai besok ya"],
  account_new: [403, "Akun baru bisa absen setelah berumur 3 hari"],
  no_profile: [403, "Buka Chat sekali dulu untuk membuat profil, lalu coba lagi"],
  banned: [403, "Akun ini diblokir"],
  already: [409, "Kamu sudah melakukannya hari ini"],
  not_checked: [400, "Absen dulu sebelum klaim bonus"],
  clan_changed: [403, "Kamu sudah pindah clan sejak absen hari ini"],
  clan_small: [400, "Bonus bareng butuh clan minimal 3 anggota"],
  not_enough: [400, "Anggota yang absen hari ini belum cukup untuk bonus"],
};

async function rpc(name: string, uid: string) {
  const { data, error } = await db.rpc(name, { p_uid: uid });
  if (error) {
    console.error("clan-daily", name, error.message);
    throw new HttpError(500, "Server bermasalah, coba lagi");
  }
  return data as Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  let uid: string;
  let token: string;
  try {
    ({ uid, token } = await verifyUser(req));
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
    const action = body?.action;

    if (action === "state") {
      return json({ state: await rpc("clan_daily_state", uid) });
    }

    if (action !== "checkin" && action !== "bonus") throw new HttpError(400, "Aksi tidak dikenal");

    // Anti akun bot: email wajib sudah terverifikasi (klaim dari token resmi).
    const claims = tokenClaims(token);
    if (claims.email_verified !== true) {
      throw new HttpError(403, "Verifikasi email akunmu dulu untuk mendapat ZCoin");
    }

    const res = await rpc(action === "checkin" ? "clan_daily_checkin" : "clan_daily_bonus", uid);
    if (res.ok !== true) {
      const [status, msg] = MESSAGES[String(res.code)] ?? [400, "Tidak bisa diproses"];
      return json({ error: msg, code: res.code }, status);
    }
    return json({ result: res, state: await rpc("clan_daily_state", uid) });
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("clan-daily", e);
    return json({ error: "Server bermasalah, coba lagi" }, 500);
  }
});
