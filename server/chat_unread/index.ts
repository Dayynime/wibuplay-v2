// Edge Function `chat-unread`: jumlah chat belum dibaca (tab Teman & Clan).
// Body JSON: { action: "counts" } -> { private, clan }
//            { action: "clan_read" } -> tandai chat clan sudah dibaca, lalu counts
// UID dari Firebase ID Token. Aturan di SQL (chat_unread.sql).

import { db, HttpError, json, readJson, rpcFail, serve, verifyUser } from "../_shared/wp.ts";

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);

  if (body.action === "clan_read") {
    const { error } = await db.rpc("clan_chat_mark_read", { p_uid: uid });
    if (error) rpcFail(error);
  } else if (body.action !== "counts") {
    throw new HttpError(400, "Aksi tidak dikenal");
  }

  const { data, error } = await db.rpc("chat_unread_counts", { p_uid: uid });
  if (error) rpcFail(error);
  const d = (data ?? {}) as { private?: number; clan?: number };
  return json({ private: d.private ?? 0, clan: d.clan ?? 0 });
});
