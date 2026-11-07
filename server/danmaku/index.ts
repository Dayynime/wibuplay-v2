// Edge Function `danmaku`: komentar melayang di video.
// Body JSON:
//   { action: "list",   key }                        -> { items: [[id, t_ms, body, color, uid], ...] }
//   { action: "send",   key, t_ms, body, color? }    -> { item: [id, t_ms, body, color, uid] }
//   { action: "delete", id }                         -> { success }
// key: 'a:<episodeId>' (anime) / 'd:<slug>' (donghua).
// Aturan (panjang, warna, mute/blokir, batas kecepatan, hak hapus) di SQL
// (danmaku.sql). UID dari Firebase ID Token.

import { db, HttpError, json, readJson, rpcFail, serve, verifyUser } from "../_shared/wp.ts";

const KEY_RE = /^[ad]:\S{1,158}$/;

function keyOf(v: unknown): string {
  if (typeof v !== "string" || !KEY_RE.test(v)) throw new HttpError(400, "Episode tidak valid");
  return v;
}

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);

  switch (body.action) {
    case "list": {
      const { data, error } = await db.rpc("danmaku_list", { p_key: keyOf(body.key) });
      if (error) rpcFail(error);
      return json({ items: data ?? [] });
    }
    case "send": {
      const t = Number(body.t_ms);
      if (!Number.isInteger(t)) throw new HttpError(400, "Waktu tidak valid");
      const { data, error } = await db.rpc("danmaku_send", {
        p_uid: uid,
        p_key: keyOf(body.key),
        p_t: t,
        p_body: typeof body.body === "string" ? body.body.slice(0, 200) : "",
        p_color: typeof body.color === "string" ? body.color : null,
      });
      if (error) rpcFail(error);
      return json({ item: data });
    }
    case "delete": {
      const id = Number(body.id);
      if (!Number.isInteger(id) || id <= 0) throw new HttpError(400, "Danmaku tidak valid");
      const { error } = await db.rpc("danmaku_delete", { p_uid: uid, p_id: id });
      if (error) rpcFail(error);
      return json({ success: true });
    }
    default:
      throw new HttpError(400, "Aksi tidak dikenal");
  }
});
