// Edge Function `profile-bio`: simpan bio profil sendiri.
// Body JSON: { bio: string }  -> { bio: string | null }
// Bio kosong = hapus. Aturan panjang/baris dicek di SQL (profile_bio.sql).
// UID selalu dari Firebase ID Token, bukan dari body.

import { db, HttpError, json, readJson, rpcFail, serve, verifyUser } from "../_shared/wp.ts";

serve(async (req) => {
  const { uid } = await verifyUser(req);
  const body = await readJson(req);
  const bio = body.bio ?? "";
  if (typeof bio !== "string") throw new HttpError(400, "Bio tidak valid");
  if (bio.length > 1000) throw new HttpError(400, "Bio maksimal 150 karakter");

  const { data, error } = await db.rpc("profile_bio_set", { p_uid: uid, p_bio: bio });
  if (error) rpcFail(error);
  return json({ bio: data ?? null });
});
