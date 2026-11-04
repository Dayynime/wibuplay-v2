// Edge Function `sticker`: upload stiker (Premium) + review developer/admin.
// Semua aturan (premium, kuota, status) ada di SQL (sticker.sql).
//
// Body JSON:
//   { action: "sign", name, mime }            -> { id, path, token, max_bytes }
//   { action: "register", id }                -> { success }   (file dicek server)
//   { action: "mine" }                        -> { items }
//   { action: "admin_list", status, offset }  -> { items }     (developer/admin)
//   { action: "admin_review", id, op, reason }-> { success }   (op: approve|reject|remove)
//
// UID selalu dari Firebase ID Token; client tidak pernah memilih bucket/path.

import {
  db,
  HttpError,
  json,
  readJson,
  relativeUrl,
  requireRole,
  rpcFail,
  serve,
  UUID_RE,
  verifyUser,
} from "../_shared/wp.ts";

const STAGING = "sticker-staging";
const PUBLIC = "stickers";
const MAX_BYTES = 1024 * 1024;
const MIMES: Record<string, string> = {
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
  "image/jpeg": "jpg",
};

/** Cek isi file (magic bytes) cocok dengan mime yang didaftarkan. */
function magicOk(b: Uint8Array, mime: string): boolean {
  const s = (from: number, to: number) => String.fromCharCode(...b.subarray(from, to));
  switch (mime) {
    case "image/png":
      return b.length > 8 && b[0] === 0x89 && s(1, 4) === "PNG";
    case "image/jpeg":
      return b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
    case "image/gif":
      return b.length > 6 && (s(0, 6) === "GIF87a" || s(0, 6) === "GIF89a");
    case "image/webp":
      return b.length > 12 && s(0, 4) === "RIFF" && s(8, 12) === "WEBP";
  }
  return false;
}

function uuid(v: unknown): string {
  if (typeof v !== "string" || !UUID_RE.test(v)) throw new HttpError(400, "ID tidak valid");
  return v;
}

async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(name, args);
  if (error) rpcFail(error);
  return data;
}

async function removeQuiet(bucket: string, path: string | null | undefined) {
  if (!path) return;
  const { error } = await db.storage.from(bucket).remove([path]);
  if (error) console.error("sticker remove", bucket, error.message);
}

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);

  switch (body.action) {
    // ------------------------------------------------------------ user
    case "sign": {
      const mime = String(body.mime ?? "");
      if (!MIMES[mime]) throw new HttpError(400, "Format harus PNG, JPG, WebP, atau GIF");
      const row = await rpc("sticker_create_upload", {
        p_uid: uid,
        p_name: typeof body.name === "string" ? body.name : "",
        p_mime: mime,
      }) as { id?: string; path?: string } | null;
      if (!row?.id || !row?.path) throw new HttpError(500, "Gagal membuat upload");

      const { data: up, error } = await db.storage.from(STAGING).createSignedUploadUrl(row.path);
      if (error || !up?.token) {
        console.error("sticker sign url", error?.message);
        throw new HttpError(500, "Gagal menyiapkan upload, coba lagi");
      }
      return json({ success: true, id: row.id, path: row.path, token: up.token, max_bytes: MAX_BYTES });
    }

    case "register": {
      const id = uuid(body.id);
      const { data: row, error } = await db.from("stickers")
        .select("id,mime,staging_path,status")
        .eq("id", id).eq("uploader_uid", uid).maybeSingle();
      if (error) rpcFail(error);
      if (!row || row.status !== "uploading") throw new HttpError(404, "Upload tidak ditemukan");

      const { data: blob, error: dlErr } = await db.storage.from(STAGING).download(row.staging_path);
      if (dlErr || !blob) throw new HttpError(400, "File belum terupload, coba lagi");
      const bytes = new Uint8Array(await blob.arrayBuffer());
      if (bytes.length < 1 || bytes.length > MAX_BYTES || !magicOk(bytes, row.mime)) {
        await removeQuiet(STAGING, row.staging_path);
        await rpc("sticker_discard", { p_uid: uid, p_id: id });
        throw new HttpError(400, "File tidak valid. Pakai gambar PNG, JPG, WebP, atau GIF maks 1 MB");
      }
      await rpc("sticker_mark_uploaded", { p_uid: uid, p_id: id, p_size: bytes.length });
      return json({ success: true });
    }

    case "mine":
      return json({ items: (await rpc("sticker_my", { p_uid: uid })) ?? [] });

    // ------------------------------------------------------------ admin
    case "admin_list": {
      await requireRole(uid, ["developer", "admin"]);
      const status = String(body.status ?? "pending");
      const offset = Number.isInteger(body.offset) ? Number(body.offset) : 0;
      const items = ((await rpc("sticker_admin_list", {
        p_actor: uid,
        p_status: status,
        p_offset: offset,
      })) ?? []) as Record<string, unknown>[];

      // Pratinjau file staging (privat) lewat signed URL 1 jam.
      const staged = items.filter((i) => i.status === "pending");
      if (staged.length) {
        const { data } = await db.storage.from(STAGING)
          .createSignedUrls(staged.map((i) => String(i.staging_path)), 3600);
        const byPath = new Map((data ?? []).map((d) => [d.path, d.signedUrl]));
        for (const i of staged) {
          const u = byPath.get(String(i.staging_path));
          if (u) i.preview_url = relativeUrl(u);
        }
      }
      for (const i of items) delete i.staging_path;
      return json({ items });
    }

    case "admin_review": {
      await requireRole(uid, ["developer", "admin"]);
      const id = uuid(body.id);
      const op = String(body.op ?? "");
      const reason = typeof body.reason === "string" ? body.reason : null;

      if (op === "approve") {
        const { data: row, error } = await db.from("stickers")
          .select("code,mime,staging_path,status").eq("id", id).maybeSingle();
        if (error) rpcFail(error);
        if (!row) throw new HttpError(404, "Stiker tidak ditemukan");
        if (row.status !== "pending") throw new HttpError(400, "Stiker ini sudah diproses");

        const { data: blob, error: dlErr } = await db.storage.from(STAGING).download(row.staging_path);
        if (dlErr || !blob) throw new HttpError(400, "File stiker tidak ditemukan");
        const publicPath = `${row.code}.${MIMES[row.mime]}`;
        const { error: upErr } = await db.storage.from(PUBLIC).upload(publicPath, blob, {
          contentType: row.mime,
          upsert: true,
          cacheControl: "31536000",
        });
        if (upErr) {
          console.error("sticker publish", upErr.message);
          throw new HttpError(500, "Gagal menerbitkan stiker, coba lagi");
        }
        const { error: rvErr } = await db.rpc("sticker_admin_review", {
          p_actor: uid, p_id: id, p_action: "approve", p_reason: null, p_public_path: publicPath,
        });
        if (rvErr) {
          await removeQuiet(PUBLIC, publicPath);
          rpcFail(rvErr);
        }
        await removeQuiet(STAGING, row.staging_path);
        return json({ success: true, code: row.code });
      }

      if (op === "reject" || op === "remove") {
        const prev = await rpc("sticker_admin_review", {
          p_actor: uid, p_id: id, p_action: op, p_reason: reason, p_public_path: null,
        }) as { staging_path?: string; public_path?: string } | null;
        if (op === "reject") await removeQuiet(STAGING, prev?.staging_path);
        else await removeQuiet(PUBLIC, prev?.public_path);
        return json({ success: true });
      }
      throw new HttpError(400, "Aksi tidak dikenal");
    }

    default:
      throw new HttpError(400, "Aksi tidak dikenal");
  }
});
