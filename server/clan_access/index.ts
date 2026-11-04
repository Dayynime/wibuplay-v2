// Edge Function `clan-access`: pengaturan akses clan (mode join + level minimal)
// dan undangan clan. Semua aturan ada di SQL (clan_access.sql); function ini
// cuma memverifikasi login lalu memanggil RPC.
//
// Body JSON:
//   { action: "settings", clan_id, join_mode, min_level }   (leader)
//   { action: "invite", clan_id, uid }                      (leader & pengurus)
//   { action: "invite_respond", invite_id, accept }         (yang diundang)
//   { action: "my_invites" }
// UID pemanggil selalu dari Firebase ID Token, BUKAN dari body.

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
const MODES = new Set(["open", "approval", "invite", "closed"]);

function uuid(v: unknown, label: string): string {
  if (typeof v !== "string" || !UUID.test(v)) throw new HttpError(400, `${label} tidak valid`);
  return v;
}

async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(name, args);
  if (error) {
    // raise exception di SQL (P0001) = pesan untuk user.
    if (error.code === "P0001" && error.message) throw new HttpError(400, error.message);
    console.error("clan-access", name, error.code, error.message);
    throw new HttpError(500, "Server bermasalah, coba lagi");
  }
  return data;
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
      case "settings": {
        const mode = String(body.join_mode ?? "");
        if (!MODES.has(mode)) throw new HttpError(400, "Mode join tidak valid");
        const lvl = Number(body.min_level);
        if (!Number.isInteger(lvl) || lvl < 1 || lvl > 500) {
          throw new HttpError(400, "Level minimal harus 1 sampai 500");
        }
        const clan = await rpc("update_clan_access", {
          p_actor_uid: uid,
          p_clan_id: uuid(body.clan_id, "Clan"),
          p_join_mode: mode,
          p_min_level: lvl,
        });
        return json({ clan });
      }

      case "invite": {
        const target = typeof body.uid === "string" ? body.uid.trim() : "";
        if (!target || target.length > 128) throw new HttpError(400, "User tidak valid");
        const id = await rpc("clan_invite", {
          p_actor_uid: uid,
          p_clan_id: uuid(body.clan_id, "Clan"),
          p_target_uid: target,
        });
        return json({ invite_id: id });
      }

      case "invite_respond": {
        const accept = body.accept === true;
        const clanId = await rpc("clan_invite_respond", {
          p_uid: uid,
          p_invite_id: uuid(body.invite_id, "Undangan"),
          p_accept: accept,
        });
        if (clanId == null) {
          return json({ error: "Undangan sudah dijawab atau kedaluwarsa" }, 410);
        }
        return json({ clan_id: clanId, accepted: accept });
      }

      case "my_invites": {
        return json({ invites: (await rpc("clan_my_invites", { p_uid: uid })) ?? [] });
      }

      default:
        throw new HttpError(400, "Aksi tidak dikenal");
    }
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("clan-access", e);
    return json({ error: "Server bermasalah, coba lagi" }, 500);
  }
});
