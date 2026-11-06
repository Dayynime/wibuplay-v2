// Edge Function `chat-mute`: mute chat (Global, Clan, Komentar).
// Aturan (role, durasi, siapa boleh mute siapa) ada di SQL (chat_mute.sql);
// pengecekan saat kirim pesan dilakukan trigger database.
//
// Body JSON:
//   { action: "status" }                         -> status mute diriku
//   { action: "check", uid }                     -> status mute user lain (pemegang role)
//   { action: "mute", uid, duration, reason? }   -> duration: 1h | 1d | 1w | perm
//   { action: "unmute", uid }
//
// UID pelaku selalu dari Firebase ID Token.

import { db, HttpError, json, readJson, rpcFail, serve, verifyUser } from "../_shared/wp.ts";

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;

function target(v: unknown): string {
  if (typeof v !== "string" || !UID_RE.test(v)) throw new HttpError(400, "User tidak valid");
  return v;
}

async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(name, args);
  if (error) rpcFail(error);
  return data ?? { muted: false };
}

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);

  switch (body.action) {
    case "status":
      return json(await rpc("chat_mute_status", { p_uid: uid }));
    case "check":
      return json(await rpc("chat_mute_check", { p_actor: uid, p_target: target(body.uid) }));
    case "mute": {
      const duration = typeof body.duration === "string" ? body.duration : "";
      const reason = typeof body.reason === "string" ? body.reason.slice(0, 120) : null;
      return json(await rpc("chat_mute_set", {
        p_actor: uid,
        p_target: target(body.uid),
        p_duration: duration,
        p_reason: reason,
      }));
    }
    case "unmute":
      return json(await rpc("chat_mute_clear", { p_actor: uid, p_target: target(body.uid) }));
    default:
      throw new HttpError(400, "Aksi tidak dikenal");
  }
});
