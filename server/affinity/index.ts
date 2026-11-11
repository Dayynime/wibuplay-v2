// Edge Function `affinity`: fitur Afinitas (ikatan dua user).
// Semua aturan ada di SQL (affinity.sql). Function ini cuma memverifikasi
// login lalu memanggil RPC. UID selalu dari Firebase ID Token, BUKAN dari body.
//
// Body JSON: { action, ... }
//   list      { uid }                          -> daftar afinitas user (sendiri / orang lain)
//   detail    { id }                           -> detail satu ikatan
//   incoming  {}                               -> permintaan masuk (pending)
//   outgoing  {}                               -> permintaan keluar (pending)
//   request   { target, type, role?, message? }
//   cancel    { id }                           -> batalkan permintaan keluar
//   respond   { id, accept }                   -> terima / tolak permintaan masuk
//   break     { id }                           -> putuskan ikatan

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

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TYPES = new Set(["soulmate", "crush", "partner", "twin", "nakama", "kin", "senpai", "rival"]);

const MESSAGES: Record<string, [number, string]> = {
  self: [400, "Tidak bisa membuat afinitas dengan diri sendiri"],
  bad_type: [400, "Jenis afinitas tidak dikenal"],
  bad_role: [400, "Pilih peranmu dulu"],
  no_profile: [403, "Buka Chat sekali dulu untuk membuat profil, lalu coba lagi"],
  banned: [403, "Akun ini tidak bisa membuat afinitas"],
  not_friends: [403, "Kalian harus berteman dulu"],
  same_type: [409, "Kalian sudah punya afinitas jenis ini"],
  pending_exists: [409, "Masih ada permintaan afinitas yang menunggu di antara kalian"],
  too_many_pending: [429, "Maksimal 3 permintaan yang menunggu jawaban. Tunggu dijawab atau batalkan salah satu"],
  cooldown: [429, "Permintaanmu baru ditolak. Coba lagi 3 hari lagi"],
  my_slot_full: [409, "Slot afinitas jenis ini milikmu sudah penuh"],
  their_slot_full: [409, "Slot afinitas jenis ini miliknya sudah penuh"],
  not_found: [404, "Data tidak ditemukan atau sudah tidak berlaku"],
  not_pending: [409, "Permintaan ini sudah tidak berlaku"],
};

async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(name, args);
  if (error) {
    console.error("affinity", name, error.message);
    throw new HttpError(500, "Server bermasalah, coba lagi");
  }
  return data;
}

function checked(res: unknown) {
  const r = res as Record<string, unknown>;
  if (r && r.ok === false) {
    const [status, msg] = MESSAGES[String(r.code)] ?? [400, "Tidak bisa diproses"];
    throw new HttpError(status, msg);
  }
  return r;
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function needUuid(v: unknown): string {
  const s = str(v);
  if (!UUID_RE.test(s)) throw new HttpError(400, "ID tidak valid");
  return s;
}

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

    switch (body?.action) {
      case "list": {
        const target = str(body.uid) || uid;
        if (!UID_RE.test(target)) throw new HttpError(400, "UID tidak valid");
        return json({ data: await rpc("affinity_list", { p_viewer: uid, p_uid: target }) });
      }
      case "detail": {
        const res = checked(await rpc("affinity_detail", { p_viewer: uid, p_id: needUuid(body.id) }));
        return json({ data: res });
      }
      case "incoming":
      case "outgoing": {
        const data = await rpc("affinity_requests_list", { p_uid: uid, p_incoming: body.action === "incoming" });
        return json({ data });
      }
      case "request": {
        const target = str(body.target);
        const type = str(body.type);
        if (!UID_RE.test(target)) throw new HttpError(400, "UID tidak valid");
        if (!TYPES.has(type)) throw new HttpError(400, "Jenis afinitas tidak dikenal");
        const res = checked(await rpc("affinity_request", {
          p_uid: uid,
          p_target: target,
          p_type: type,
          p_role: str(body.role) || null,
          p_message: str(body.message).slice(0, 120) || null,
        }));
        return json({ data: res });
      }
      case "cancel": {
        const res = checked(await rpc("affinity_cancel", { p_uid: uid, p_id: needUuid(body.id) }));
        return json({ data: res });
      }
      case "respond": {
        const res = checked(await rpc("affinity_respond", {
          p_uid: uid,
          p_id: needUuid(body.id),
          p_accept: body.accept === true,
        }));
        return json({ data: res });
      }
      case "break": {
        const res = checked(await rpc("affinity_break", { p_uid: uid, p_id: needUuid(body.id) }));
        return json({ data: res });
      }
      default:
        throw new HttpError(400, "Aksi tidak dikenal");
    }
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("affinity", e);
    return json({ error: "Server bermasalah, coba lagi" }, 500);
  }
});
