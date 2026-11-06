// Edge Function `chat-react`: reaksi emoji di Chat Global & Chat Clan.
// Body JSON:
//   { action: "counts", channel: "global" | "clan", ids: [..] }   (maks 150)
//      -> { items: [{id, counts: {emoji: n}, mine}] }
//   { action: "react", channel, id, emoji | null }   (null = hapus reaksiku)
//      -> { item: {id, counts, mine} }
// Aturan (emoji yang boleh, anggota clan, mute, batas kecepatan) di SQL
// (chat_react.sql). UID dari Firebase ID Token.

import { db, HttpError, json, readJson, rpcFail, serve, verifyUser } from "../_shared/wp.ts";

function channelOf(v: unknown): "global" | "clan" {
  if (v === "global" || v === "clan") return v;
  throw new HttpError(400, "Channel tidak valid");
}

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);
  const channel = channelOf(body.channel);

  if (body.action === "counts") {
    const ids = Array.isArray(body.ids)
      ? [...new Set(body.ids.map(Number).filter((n: number) => Number.isInteger(n) && n > 0))].slice(0, 150)
      : [];
    if (!ids.length) return json({ items: [] });
    const { data, error } = await db.rpc("chat_react_counts", { p_uid: uid, p_channel: channel, p_ids: ids });
    if (error) rpcFail(error);
    return json({ items: data ?? [] });
  }

  if (body.action === "react") {
    const id = Number(body.id);
    if (!Number.isInteger(id) || id <= 0) throw new HttpError(400, "Pesan tidak valid");
    const emoji = typeof body.emoji === "string" && body.emoji.length <= 16 ? body.emoji : null;
    const { data, error } = await db.rpc("chat_react_set", {
      p_uid: uid, p_channel: channel, p_id: id, p_emoji: emoji,
    });
    if (error) rpcFail(error);
    return json({ item: data });
  }

  throw new HttpError(400, "Aksi tidak dikenal");
});
