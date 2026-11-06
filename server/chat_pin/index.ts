// Edge Function `chat-pin`: pesan disematkan di Chat Global.
// Body JSON:
//   { action: "list" }               -> { pins: [...] }
//   { action: "pin",   id }          -> { pins }   (developer/admin/moderator)
//   { action: "unpin", id }          -> { pins }   (developer/admin/moderator)
// Role dicek di SQL (chat_pin.sql). UID dari Firebase ID Token.

import { db, HttpError, json, readJson, rpcFail, serve, verifyUser } from "../_shared/wp.ts";

function msgId(v: unknown): number {
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) throw new HttpError(400, "Pesan tidak valid");
  return n;
}

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);

  if (body.action === "list") {
    const { data, error } = await db.rpc("chat_pin_list");
    if (error) rpcFail(error);
    return json({ pins: data ?? [] });
  }
  if (body.action === "pin" || body.action === "unpin") {
    const { data, error } = await db.rpc("chat_pin_set", {
      p_actor: uid,
      p_id: msgId(body.id),
      p_pin: body.action === "pin",
    });
    if (error) rpcFail(error);
    return json({ pins: data ?? [] });
  }
  throw new HttpError(400, "Aksi tidak dikenal");
});
