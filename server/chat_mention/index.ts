// Edge Function `chat-mention`: kirim notif ke teman yang di-mention (@nama)
// di Chat Global / Chat Clan. Dipanggil app sesudah pesan terkirim.
// Body JSON: { action: "notify", channel: "global" | "clan", message_id, uids: [..] }
//   -> { sent }
// Semua aturan (pesan milik pengirim, wajib teman, anggota clan, nama ada di
// teks, maks 5) dicek di SQL (chat_mention.sql). UID dari Firebase ID Token.

import { db, HttpError, json, readJson, rpcFail, serve, verifyUser } from "../_shared/wp.ts";

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);
  if (body.action !== "notify") throw new HttpError(400, "Aksi tidak dikenal");

  const channel = body.channel === "clan" ? "clan" : body.channel === "global" ? "global" : null;
  if (!channel) throw new HttpError(400, "Channel tidak valid");
  const id = Number(body.message_id);
  if (!Number.isInteger(id) || id <= 0) throw new HttpError(400, "Pesan tidak valid");
  const uids = Array.isArray(body.uids)
    ? [...new Set(body.uids.filter((u: unknown) => typeof u === "string" && UID_RE.test(u)))].slice(0, 5)
    : [];
  if (!uids.length) return json({ sent: 0 });

  const { data, error } = await db.rpc("chat_mention_notify", {
    p_uid: uid, p_channel: channel, p_message_id: id, p_targets: uids,
  });
  if (error) rpcFail(error);
  return json({ sent: data ?? 0 });
});
