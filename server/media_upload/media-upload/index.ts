// Edge Function `media-upload`: link upload sekali pakai ke Supabase Storage
// (pengganti Cloudinary yang dinonaktifkan karena kuota free habis).
//
// Body JSON:
//   { action: "sign", kind, mime, size, clan_id? }
//     kind: avatar | banner | clan_photo | clan_banner
//   -> { bucket, path, token }
// App lalu PUT file ke /storage/v1/object/upload/sign/<bucket>/<path>?token=
// dan memakai URL publik /storage/v1/object/public/<bucket>/<path>.
//
// UID SELALU dari Firebase ID Token. Client tidak memilih bucket/path:
//   avatar      -> chat-avatars/<uid>/<uid>-<ms>.<ext>
//   banner      -> chat-banners/<uid>/<uid>-<ms>.<ext>
//   clan_photo  -> clan-media/photos/<clan_id>-<ms>.<ext>  (leader)
//                  clan-media/photos/new-<uid>-<ms>.<ext>  (buat clan baru)
//   clan_banner -> clan-media/banners/<clan_id>-<ms>.<ext> (leader)
// Aturan Premium / GIF tetap dicek saat URL disimpan (chat-save-profile,
// RPC clan), bukan di sini.

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
const EXT: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
};
const MAX_BYTES = 10 * 1024 * 1024;

async function requireLeader(uid: string, clanId: string) {
  const { data, error } = await db.from("clans").select("leader_uid").eq("id", clanId).maybeSingle();
  if (error) {
    console.error("media-upload clan", error.message);
    throw new HttpError(500, "Server bermasalah, coba lagi");
  }
  if (!data) throw new HttpError(404, "Clan tidak ditemukan");
  if ((data as { leader_uid?: string }).leader_uid !== uid) {
    throw new HttpError(403, "Hanya leader yang bisa mengganti gambar clan");
  }
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
    let b: Record<string, unknown> = {};
    try {
      b = await req.json();
    } catch {
      throw new HttpError(400, "Body tidak valid");
    }
    if (b.action !== "sign") throw new HttpError(400, "Aksi tidak dikenal");

    const mime = typeof b.mime === "string" ? b.mime : "";
    const ext = EXT[mime];
    if (!ext) throw new HttpError(400, "File harus JPG, PNG, WebP, atau GIF");
    const size = typeof b.size === "number" ? b.size : 0;
    if (!(size > 0) || size > MAX_BYTES) throw new HttpError(400, "Ukuran file maksimal 10 MB");
    if (!/^[A-Za-z0-9_]{1,128}$/.test(uid)) throw new HttpError(400, "Akun tidak valid");

    const ms = Date.now();
    const clanId = typeof b.clan_id === "string" && UUID.test(b.clan_id) ? b.clan_id.toLowerCase() : null;
    let bucket: string;
    let path: string;
    switch (b.kind) {
      case "avatar":
        bucket = "chat-avatars";
        path = `${uid}/${uid}-${ms}.${ext}`;
        break;
      case "banner":
        bucket = "chat-banners";
        path = `${uid}/${uid}-${ms}.${ext}`;
        break;
      case "clan_photo":
        bucket = "clan-media";
        if (clanId) {
          await requireLeader(uid, clanId);
          path = `photos/${clanId}-${ms}.${ext}`;
        } else {
          path = `photos/new-${uid}-${ms}.${ext}`;
        }
        break;
      case "clan_banner":
        if (!clanId) throw new HttpError(400, "Clan tidak valid");
        await requireLeader(uid, clanId);
        bucket = "clan-media";
        path = `banners/${clanId}-${ms}.${ext}`;
        break;
      default:
        throw new HttpError(400, "Jenis gambar tidak dikenal");
    }

    const { data, error } = await db.storage.from(bucket).createSignedUploadUrl(path);
    if (error || !data?.token) {
      console.error("media-upload sign", bucket, error?.message);
      throw new HttpError(500, "Gagal menyiapkan upload, coba lagi");
    }
    return json({ bucket, path: data.path ?? path, token: data.token });
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("media-upload", e);
    return json({ error: "Server bermasalah, coba lagi" }, 500);
  }
});
