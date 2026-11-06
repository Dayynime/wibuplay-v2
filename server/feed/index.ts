// Edge Function `feed`: postingan user (teks + gambar), like, komentar.
// Aturan (Premium untuk posting, blokir/mute, batas, hak hapus) di SQL (feed.sql).
//
// Body JSON:
//   { action: "list", tab: "all" | "friends", before? }      -> { posts }
//   { action: "get", id }                                     -> { post }
//   { action: "upload_sign", mime }                           -> { id, path, token }
//   { action: "create", body?, upload_id?, width?, height? }  -> { post }
//   { action: "delete", id }                                  -> { success }
//   { action: "like", id, on }                                -> { liked, like_count }
//   { action: "comments", post_id, after? }                   -> { comments }
//   { action: "comment", post_id, body }                      -> { comment }
//   { action: "comment_delete", id }                          -> { success }
//
// Gambar: app upload ke bucket privat `feed-staging` lewat signed URL; saat
// "create" file dicek (ukuran + magic bytes) lalu disalin ke bucket publik `feed`.

import { db, HttpError, json, readJson, rpcFail, serve, UUID_RE, verifyUser } from "../_shared/wp.ts";

const STAGING = "feed-staging";
const PUBLIC = "feed";
const MAX_BYTES = 2 * 1024 * 1024;
const MIMES: Record<string, string> = { "image/png": "png", "image/webp": "webp", "image/jpeg": "jpg" };

function magicOk(b: Uint8Array, mime: string): boolean {
  const s = (from: number, to: number) => String.fromCharCode(...b.subarray(from, to));
  switch (mime) {
    case "image/png":
      return b.length > 8 && b[0] === 0x89 && s(1, 4) === "PNG";
    case "image/jpeg":
      return b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
    case "image/webp":
      return b.length > 12 && s(0, 4) === "RIFF" && s(8, 12) === "WEBP";
  }
  return false;
}

function posInt(v: unknown, msg: string): number {
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) throw new HttpError(400, msg);
  return n;
}

async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(name, args);
  if (error) rpcFail(error);
  return data;
}

async function removeQuiet(bucket: string, path: string | null | undefined) {
  if (!path) return;
  const { error } = await db.storage.from(bucket).remove([path]);
  if (error) console.error("feed remove", bucket, error.message);
}

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);

  switch (body.action) {
    case "list": {
      const tab = body.tab === "friends" ? "friends" : "all";
      const before = Number.isInteger(body.before) ? Number(body.before) : 0;
      return json({ posts: (await rpc("feed_list", { p_uid: uid, p_tab: tab, p_before: before, p_limit: 20 })) ?? [] });
    }

    case "get":
      return json({ post: await rpc("feed_get", { p_uid: uid, p_id: posInt(body.id, "Postingan tidak valid") }) });

    case "upload_sign": {
      const mime = String(body.mime ?? "");
      if (!MIMES[mime]) throw new HttpError(400, "Gambar harus JPG, PNG, atau WebP");
      const row = await rpc("feed_upload_begin", { p_uid: uid, p_mime: mime }) as { id?: string; path?: string } | null;
      if (!row?.id || !row?.path) throw new HttpError(500, "Gagal menyiapkan upload");
      const { data: up, error } = await db.storage.from(STAGING).createSignedUploadUrl(row.path);
      if (error || !up?.token) {
        console.error("feed sign url", error?.message);
        throw new HttpError(500, "Gagal menyiapkan upload, coba lagi");
      }
      return json({ id: row.id, path: row.path, token: up.token, max_bytes: MAX_BYTES });
    }

    case "create": {
      const text = typeof body.body === "string" ? body.body.slice(0, 1000) : "";
      let uploadId: string | null = null;
      let publicPath: string | null = null;
      let stagingPath: string | null = null;

      if (body.upload_id != null) {
        if (typeof body.upload_id !== "string" || !UUID_RE.test(body.upload_id)) {
          throw new HttpError(400, "Gambar tidak valid");
        }
        uploadId = body.upload_id;
        const { data: up, error } = await db.from("feed_uploads")
          .select("id,mime,staging_path,used").eq("id", uploadId).eq("firebase_uid", uid).maybeSingle();
        if (error) rpcFail(error);
        if (!up || up.used) throw new HttpError(404, "Gambar tidak ditemukan, upload ulang");
        stagingPath = up.staging_path;

        const { data: blob, error: dlErr } = await db.storage.from(STAGING).download(up.staging_path);
        if (dlErr || !blob) throw new HttpError(400, "Gambar belum terupload, coba lagi");
        const bytes = new Uint8Array(await blob.arrayBuffer());
        if (bytes.length < 1 || bytes.length > MAX_BYTES || !magicOk(bytes, up.mime)) {
          await removeQuiet(STAGING, up.staging_path);
          throw new HttpError(400, "Gambar tidak valid. Pakai JPG, PNG, atau WebP maks 2 MB");
        }
        publicPath = `${uploadId}.${MIMES[up.mime]}`;
        const { error: upErr } = await db.storage.from(PUBLIC).upload(publicPath, bytes, {
          contentType: up.mime,
          upsert: true,
          cacheControl: "31536000",
        });
        if (upErr) {
          console.error("feed publish", upErr.message);
          throw new HttpError(500, "Gagal menyimpan gambar, coba lagi");
        }
      }

      const w = Number.isInteger(body.width) ? Number(body.width) : null;
      const h = Number.isInteger(body.height) ? Number(body.height) : null;
      const { data, error } = await db.rpc("feed_post_create", {
        p_uid: uid, p_body: text, p_upload: uploadId, p_image_path: publicPath, p_w: w, p_h: h,
      });
      if (error) {
        await removeQuiet(PUBLIC, publicPath);
        rpcFail(error);
      }
      await removeQuiet(STAGING, stagingPath);
      return json({ post: data });
    }

    case "delete": {
      const res = await rpc("feed_post_delete", { p_uid: uid, p_id: posInt(body.id, "Postingan tidak valid") }) as
        | { image_path?: string | null }
        | null;
      await removeQuiet(PUBLIC, res?.image_path);
      return json({ success: true });
    }

    case "like":
      return json(await rpc("feed_like", { p_uid: uid, p_id: posInt(body.id, "Postingan tidak valid"), p_on: body.on === true }));

    case "comments": {
      const after = Number.isInteger(body.after) ? Number(body.after) : 0;
      return json({
        comments: (await rpc("feed_comments_list", { p_id: posInt(body.post_id, "Postingan tidak valid"), p_after: after })) ?? [],
      });
    }

    case "comment": {
      const text = typeof body.body === "string" ? body.body.slice(0, 500) : "";
      return json({
        comment: await rpc("feed_comment_add", { p_uid: uid, p_id: posInt(body.post_id, "Postingan tidak valid"), p_body: text }),
      });
    }

    case "comment_delete":
      await rpc("feed_comment_delete", { p_uid: uid, p_comment: posInt(body.id, "Komentar tidak valid") });
      return json({ success: true });

    default:
      throw new HttpError(400, "Aksi tidak dikenal");
  }
});
