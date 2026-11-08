// Aturan & alur catur mabar. Tidak menyentuh jaringan langsung: database lewat
// interface `Db`, notifikasi lewat `Notify`, jam lewat `now`. Server yang
// menentukan langkah legal, giliran, jam, dan hasil; app cuma menampilkan.

import { Chess, type Square } from "./chess.ts";

export const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

/** Pilihan waktu: [menit, tambahan detik per langkah]. */
export const TIME_PRESETS: Record<string, [number, number]> = {
  "3+2": [3, 2],
  "5+0": [5, 0],
  "10+0": [10, 0],
  "15+10": [15, 10],
};

export const WAIT_MS = 15 * 60_000; // undangan / room kedaluwarsa
export const FIRST_MOVE_MS = 60_000; // batas langkah pertama tiap pemain (jam belum jalan)
export const MAX_WAITING = 3; // undangan + room yang masih menunggu, per pembuat
export const MAX_ACTIVE = 5; // permainan berjalan per pemain

export type Color = "w" | "b";
export type Status = "waiting" | "active" | "finished" | "aborted" | "cancelled" | "declined" | "expired";

export interface Game {
  id: string;
  code: string | null;
  creator_uid: string;
  invitee_uid: string | null;
  creator_color: "w" | "b" | "random";
  white_uid: string | null;
  black_uid: string | null;
  status: Status;
  result: "1-0" | "0-1" | "1/2-1/2" | null;
  end_reason: string | null;
  fen: string;
  moves: string[];
  last_san: string | null;
  ply: number;
  base_ms: number;
  inc_ms: number;
  white_ms: number;
  black_ms: number;
  turn_started_at: string | null;
  draw_offer_by: Color | null;
  rematch_of: string | null;
  created_at: string;
  started_at: string | null;
  ended_at: string | null;
  updated_at: string;
}

export interface Profile {
  username: string;
  avatar_url: string | null;
  username_color?: string | null;
  user_number?: number | null;
}

export interface Db {
  get(id: string): Promise<Game | null>;
  getByCode(code: string): Promise<Game | null>;
  /** Insert; lempar `DuplicateCode` kalau kode room bentrok. */
  insert(row: Partial<Game>): Promise<Game>;
  /** Update hanya kalau `ply` dan `status` masih sama (cegah balapan). null = sudah berubah. */
  updateIf(id: string, guard: { ply: number; status: Status }, patch: Partial<Game>): Promise<Game | null>;
  /** Semua permainan yang melibatkan uid, terbaru dulu. */
  listFor(uid: string, limit: number): Promise<Game[]>;
  /** Permainan yang sedang berjalan (untuk ditonton), terbaru dulu. */
  listLive(limit: number): Promise<Game[]>;
  /** Undangan rematch yang masih menunggu untuk permainan ini. */
  findWaitingRematch(gameId: string): Promise<Game | null>;
  isFriend(a: string, b: string): Promise<boolean>;
  profiles(uids: string[]): Promise<Record<string, Profile>>;
}

export class DuplicateCode extends Error {}

export interface Notify {
  /** Ping ke room permainan dan lobby kedua pemain. Best-effort. */
  (topics: string[], payload: Record<string, unknown>): Promise<void>;
}

export class GameError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message);
  }
}

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UCI_RE = /^[a-h][1-8][a-h][1-8][qrbn]?$/;

const iso = (ms: number) => new Date(ms).toISOString();
const ms = (s: string | null) => (s ? Date.parse(s) : 0);
const other = (c: Color): Color => (c === "w" ? "b" : "w");

export function sideToMove(fen: string): Color {
  return fen.split(" ")[1] === "b" ? "b" : "w";
}

export function colorOf(g: Game, uid: string): Color | null {
  if (g.white_uid === uid) return "w";
  if (g.black_uid === uid) return "b";
  return null;
}

function involves(g: Game, uid: string): boolean {
  return g.white_uid === uid || g.black_uid === uid || g.creator_uid === uid || g.invitee_uid === uid;
}

function opponentUid(g: Game, uid: string): string | null {
  if (g.white_uid === uid) return g.black_uid;
  if (g.black_uid === uid) return g.white_uid;
  if (g.creator_uid === uid) return g.invitee_uid;
  if (g.invitee_uid === uid) return g.creator_uid;
  return null;
}

export function randomCode(rand: () => number = Math.random): string {
  let s = "";
  for (let i = 0; i < 6; i++) s += CODE_ALPHABET[Math.floor(rand() * CODE_ALPHABET.length)];
  return s;
}

function replay(moves: string[]): Chess {
  const c = new Chess();
  for (const m of moves) {
    c.move({ from: m.slice(0, 2) as Square, to: m.slice(2, 4) as Square, promotion: m[4] });
  }
  return c;
}

export class ChessService {
  constructor(
    private readonly db: Db,
    private readonly notify: Notify,
    private readonly now: () => number = Date.now,
    private readonly rand: () => number = Math.random,
    /** Server ICE (STUN/TURN) untuk panggilan suara; null = belum diatur. */
    private readonly ice: ((uid: string) => Promise<unknown[]>) | null = null,
  ) {}

  // ------------------------------------------------------------- helpers

  private async load(id: unknown): Promise<Game> {
    if (typeof id !== "string" || !UUID_RE.test(id)) throw new GameError("Permainan tidak ditemukan", 404);
    const g = await this.db.get(id);
    if (!g) throw new GameError("Permainan tidak ditemukan", 404);
    return g;
  }

  private async ping(g: Game, extraUids: (string | null)[] = []): Promise<void> {
    const uids = new Set<string>();
    for (const u of [g.white_uid, g.black_uid, g.creator_uid, g.invitee_uid, ...extraUids]) if (u) uids.add(u);
    const topics = [`chess-game-${g.id}`, ...[...uids].map((u) => `chess-user-${u}`)];
    try {
      await this.notify(topics, { id: g.id, ply: g.ply, status: g.status });
    } catch {
      // Ping gagal tidak membatalkan aksi; app tetap memuat ulang berkala.
    }
  }

  /** Waktu habis / undangan kedaluwarsa dihitung saat dibaca (tanpa cron). */
  async settle(g: Game): Promise<Game> {
    const now = this.now();
    let patch: Partial<Game> | null = null;

    if (g.status === "waiting" && now - ms(g.created_at) > WAIT_MS) {
      patch = { status: "expired", ended_at: iso(now) };
    } else if (g.status === "active" && g.turn_started_at) {
      const elapsed = now - ms(g.turn_started_at);
      if (g.ply < 2) {
        if (elapsed > FIRST_MOVE_MS) patch = { status: "aborted", end_reason: "no_first_move", ended_at: iso(now) };
      } else {
        const turn = sideToMove(g.fen);
        const left = (turn === "w" ? g.white_ms : g.black_ms) - elapsed;
        if (left <= 0) {
          patch = {
            status: "finished",
            result: turn === "w" ? "0-1" : "1-0",
            end_reason: "timeout",
            ended_at: iso(now),
            draw_offer_by: null,
            ...(turn === "w" ? { white_ms: 0 } : { black_ms: 0 }),
          };
        }
      }
    }
    if (!patch) return g;

    const updated = await this.db.updateIf(g.id, { ply: g.ply, status: g.status }, { ...patch, updated_at: iso(now) });
    if (updated) {
      await this.ping(updated);
      return updated;
    }
    return (await this.db.get(g.id)) ?? g;
  }

  async view(g: Game, uid: string, withProfiles: Record<string, Profile> | null = null) {
    const me = colorOf(g, uid);
    const turn = sideToMove(g.fen);
    const active = g.status === "active";
    const needHistory = g.moves.length > 0;
    const chess = needHistory || active ? replay(g.moves) : null;

    const legal = active && me === turn && chess
      ? chess.moves({ verbose: true }).map((m) => m.from + m.to + (m.promotion ?? ""))
      : [];
    const last = g.moves.length ? g.moves[g.moves.length - 1] : null;

    const profiles = withProfiles ??
      await this.db.profiles([g.white_uid, g.black_uid, g.creator_uid, g.invitee_uid].filter((u): u is string => !!u));
    const person = (u: string | null) =>
      u ? { uid: u, username: profiles[u]?.username || "Pengguna Zenime", avatar_url: profiles[u]?.avatar_url ?? null, username_color: profiles[u]?.username_color ?? null } : null;

    return {
      id: g.id,
      status: g.status,
      result: g.result,
      end_reason: g.end_reason,
      code: g.status === "waiting" && g.creator_uid === uid ? g.code : null,
      is_invite: g.invitee_uid !== null,
      creator: person(g.creator_uid),
      invitee: person(g.invitee_uid),
      creator_color: g.creator_color,
      white: person(g.white_uid),
      black: person(g.black_uid),
      my_color: me,
      turn,
      fen: g.fen,
      ply: g.ply,
      history: chess ? chess.history() : [],
      last_move: last ? { from: last.slice(0, 2), to: last.slice(2, 4), san: g.last_san } : null,
      in_check: chess ? chess.inCheck() : false,
      legal,
      base_ms: g.base_ms,
      inc_ms: g.inc_ms,
      white_ms: g.white_ms,
      black_ms: g.black_ms,
      clock_running: active && g.ply >= 2 ? turn : null,
      turn_started_at: g.turn_started_at,
      first_move_deadline: active && g.ply < 2 && g.turn_started_at ? iso(ms(g.turn_started_at) + FIRST_MOVE_MS) : null,
      draw_offer_by: g.draw_offer_by,
      rematch_of: g.rematch_of,
      created_at: g.created_at,
      expires_at: g.status === "waiting" ? iso(ms(g.created_at) + WAIT_MS) : null,
      server_now: iso(this.now()),
    };
  }

  private async countOpen(uid: string) {
    const all = await this.db.listFor(uid, 60);
    let waiting = 0, active = 0;
    for (const g0 of all) {
      if (g0.status !== "waiting" && g0.status !== "active") continue;
      const g = await this.settle(g0);
      if (g.status === "waiting" && g.creator_uid === uid) waiting++;
      if (g.status === "active" && colorOf(g, uid)) active++;
    }
    return { waiting, active, all };
  }

  private async startGame(g: Game, joinerUid: string): Promise<Game> {
    const now = this.now();
    const creatorColor: Color = g.creator_color === "random" ? (this.rand() < 0.5 ? "w" : "b") : g.creator_color;
    const patch: Partial<Game> = {
      status: "active",
      white_uid: creatorColor === "w" ? g.creator_uid : joinerUid,
      black_uid: creatorColor === "w" ? joinerUid : g.creator_uid,
      invitee_uid: g.invitee_uid ?? joinerUid,
      started_at: iso(now),
      turn_started_at: iso(now),
      updated_at: iso(now),
    };
    const updated = await this.db.updateIf(g.id, { ply: 0, status: "waiting" }, patch);
    if (!updated) throw new GameError("Permainan ini sudah tidak menunggu lawan", 409);
    await this.ping(updated);
    return updated;
  }

  // ------------------------------------------------------------- actions

  async list(uid: string) {
    const rows = await this.db.listFor(uid, 40);
    const settled: Game[] = [];
    for (const g of rows) settled.push(g.status === "waiting" || g.status === "active" ? await this.settle(g) : g);

    const uids = new Set<string>();
    for (const g of settled) for (const u of [g.white_uid, g.black_uid, g.creator_uid, g.invitee_uid]) if (u) uids.add(u);
    const profiles = await this.db.profiles([...uids]);

    const incoming: unknown[] = [], waiting: unknown[] = [], active: unknown[] = [], recent: unknown[] = [];
    for (const g of settled) {
      if (g.status === "waiting" && g.invitee_uid === uid) incoming.push(await this.view(g, uid, profiles));
      else if (g.status === "waiting" && g.creator_uid === uid) waiting.push(await this.view(g, uid, profiles));
      else if (g.status === "active") active.push(await this.view(g, uid, profiles));
      else if ((g.status === "finished" || g.status === "aborted") && colorOf(g, uid) && recent.length < 10) {
        recent.push(await this.view(g, uid, profiles));
      }
    }
    return { incoming, waiting, active, recent, server_now: iso(this.now()) };
  }

  async get(uid: string, body: Record<string, unknown>) {
    const g = await this.settle(await this.load(body.id));
    // Bukan pemain = penonton: boleh lihat permainan yang sudah mulai / selesai,
    // tidak boleh lihat room/undangan yang masih menunggu.
    const spectator = !involves(g, uid);
    if (spectator && g.status !== "active" && g.status !== "finished" && g.status !== "aborted") {
      throw new GameError("Permainan tidak ditemukan", 404);
    }
    const game: Record<string, unknown> = await this.view(g, uid);
    game.spectator = spectator;
    if ((g.status === "finished" || g.status === "aborted") && colorOf(g, uid)) {
      const rm = await this.db.findWaitingRematch(g.id);
      const fresh = rm ? await this.settle(rm) : null;
      game.rematch = fresh && fresh.status === "waiting" ? { id: fresh.id, by_me: fresh.creator_uid === uid } : null;
    }
    return { game };
  }

  /** Permainan yang sedang berjalan dan bisa ditonton (bukan milikku). */
  async live(uid: string) {
    const rows = await this.db.listLive(30);
    const games: Game[] = [];
    for (const g0 of rows) {
      const g = await this.settle(g0);
      if (g.status === "active" && !colorOf(g, uid)) games.push(g);
    }
    const uids = new Set<string>();
    for (const g of games) for (const u of [g.white_uid, g.black_uid]) if (u) uids.add(u);
    const profiles = await this.db.profiles([...uids]);
    const out: unknown[] = [];
    for (const g of games) out.push(await this.view(g, uid, profiles));
    return { games: out, server_now: iso(this.now()) };
  }

  async create(uid: string, body: Record<string, unknown>) {
    const preset = TIME_PRESETS[String(body.time ?? "")];
    if (!preset) throw new GameError("Pilihan waktu tidak valid");
    const color = body.color === "w" || body.color === "b" ? body.color : "random";
    const invitee = body.invitee_uid == null || body.invitee_uid === "" ? null : String(body.invitee_uid);

    if (invitee !== null) {
      if (!UID_RE.test(invitee) || invitee === uid) throw new GameError("Lawan tidak valid");
      if (!(await this.db.isFriend(uid, invitee))) throw new GameError("Kamu cuma bisa menantang teman");
    }

    const { waiting, all } = await this.countOpen(uid);
    if (invitee !== null) {
      const dup = all.find((g) => g.status === "waiting" && g.creator_uid === uid && g.invitee_uid === invitee);
      if (dup) {
        const fresh = await this.settle(dup);
        if (fresh.status === "waiting") return { game: await this.view(fresh, uid) };
      }
    }
    if (waiting >= MAX_WAITING) {
      throw new GameError(`Maksimal ${MAX_WAITING} tantangan menunggu. Batalkan salah satu dulu.`);
    }

    const [min, inc] = preset;
    const base = {
      creator_uid: uid,
      invitee_uid: invitee,
      creator_color: color as Game["creator_color"],
      status: "waiting" as Status,
      fen: START_FEN,
      moves: [],
      ply: 0,
      base_ms: min * 60_000,
      inc_ms: inc * 1000,
      white_ms: min * 60_000,
      black_ms: min * 60_000,
      created_at: iso(this.now()),
      updated_at: iso(this.now()),
    };

    let g: Game | null = null;
    for (let i = 0; i < 5 && !g; i++) {
      try {
        g = await this.db.insert({ ...base, code: invitee === null ? randomCode(this.rand) : null });
      } catch (e) {
        if (!(e instanceof DuplicateCode)) throw e;
      }
    }
    if (!g) throw new GameError("Gagal membuat room, coba lagi");
    await this.ping(g);
    return { game: await this.view(g, uid) };
  }

  async join(uid: string, body: Record<string, unknown>) {
    const code = String(body.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
    if (code.length !== 6) throw new GameError("Kode room harus 6 karakter");
    const found = await this.db.getByCode(code);
    if (!found) throw new GameError("Kode room tidak ditemukan", 404);
    const g = await this.settle(found);
    if (g.creator_uid === uid) {
      if (g.status === "waiting") throw new GameError("Ini room milikmu sendiri. Bagikan kodenya ke temanmu.");
      return { game: await this.view(g, uid) };
    }
    if (colorOf(g, uid)) return { game: await this.view(g, uid) }; // sudah tergabung
    if (g.status !== "waiting" || g.invitee_uid !== null) throw new GameError("Room ini sudah tidak tersedia", 409);
    const { active } = await this.countOpen(uid);
    if (active >= MAX_ACTIVE) throw new GameError(`Selesaikan dulu permainanmu (maks ${MAX_ACTIVE} berjalan)`);
    return { game: await this.view(await this.startGame(g, uid), uid) };
  }

  async accept(uid: string, body: Record<string, unknown>) {
    const g = await this.settle(await this.load(body.id));
    if (g.invitee_uid !== uid || g.creator_uid === uid) throw new GameError("Tantangan tidak ditemukan", 404);
    if (g.status !== "waiting") throw new GameError("Tantangan ini sudah tidak berlaku", 409);
    const { active } = await this.countOpen(uid);
    if (active >= MAX_ACTIVE) throw new GameError(`Selesaikan dulu permainanmu (maks ${MAX_ACTIVE} berjalan)`);
    return { game: await this.view(await this.startGame(g, uid), uid) };
  }

  async decline(uid: string, body: Record<string, unknown>) {
    const g = await this.settle(await this.load(body.id));
    if (g.invitee_uid !== uid) throw new GameError("Tantangan tidak ditemukan", 404);
    if (g.status !== "waiting") return { game: await this.view(g, uid) };
    const now = iso(this.now());
    const u = await this.db.updateIf(g.id, { ply: 0, status: "waiting" }, { status: "declined", ended_at: now, updated_at: now });
    const res = u ?? (await this.load(g.id));
    if (u) await this.ping(u);
    return { game: await this.view(res, uid) };
  }

  async cancel(uid: string, body: Record<string, unknown>) {
    const g = await this.settle(await this.load(body.id));
    if (g.creator_uid !== uid) throw new GameError("Tantangan tidak ditemukan", 404);
    if (g.status !== "waiting") throw new GameError("Lawan sudah bergabung, tantangan tidak bisa dibatalkan", 409);
    const now = iso(this.now());
    const u = await this.db.updateIf(g.id, { ply: 0, status: "waiting" }, { status: "cancelled", ended_at: now, updated_at: now });
    if (!u) throw new GameError("Lawan sudah bergabung, tantangan tidak bisa dibatalkan", 409);
    await this.ping(u);
    return { game: await this.view(u, uid) };
  }

  async move(uid: string, body: Record<string, unknown>) {
    const g = await this.settle(await this.load(body.id));
    const me = colorOf(g, uid);
    if (!me) throw new GameError("Kamu bukan pemain di permainan ini", 403);
    if (g.status !== "active") return { game: await this.view(g, uid), rejected: "Permainan sudah selesai" };
    if (typeof body.ply === "number" && body.ply !== g.ply) {
      return { game: await this.view(g, uid), rejected: "Posisi sudah berubah" };
    }
    if (sideToMove(g.fen) !== me) return { game: await this.view(g, uid), rejected: "Bukan giliranmu" };

    const uci = String(body.move ?? "").toLowerCase();
    if (!UCI_RE.test(uci)) throw new GameError("Langkah tidak valid");

    const chess = replay(g.moves);
    let san: string;
    try {
      san = chess.move({ from: uci.slice(0, 2) as Square, to: uci.slice(2, 4) as Square, promotion: uci[4] }).san;
    } catch {
      return { game: await this.view(g, uid), rejected: "Langkah tidak sah" };
    }
    // Promosi tanpa huruf bidak: chess.js otomatis pilih ratu; simpan yang benar-benar dimainkan.
    const played = chess.history({ verbose: true }).at(-1)!;
    const playedUci = played.from + played.to + (played.promotion ?? "");

    const now = this.now();
    const elapsed = now - ms(g.turn_started_at);
    let myMs = me === "w" ? g.white_ms : g.black_ms;
    if (g.ply >= 2) myMs = Math.max(0, myMs - elapsed) + g.inc_ms;

    const patch: Partial<Game> = {
      fen: chess.fen(),
      moves: [...g.moves, playedUci],
      last_san: san,
      ply: g.ply + 1,
      turn_started_at: iso(now),
      draw_offer_by: g.draw_offer_by === me ? me : null,
      updated_at: iso(now),
      ...(me === "w" ? { white_ms: myMs } : { black_ms: myMs }),
    };

    let reason: string | null = null;
    let result: Game["result"] = null;
    if (chess.isCheckmate()) { reason = "checkmate"; result = me === "w" ? "1-0" : "0-1"; }
    else if (chess.isStalemate()) { reason = "stalemate"; result = "1/2-1/2"; }
    else if (chess.isInsufficientMaterial()) { reason = "insufficient"; result = "1/2-1/2"; }
    else if (chess.isThreefoldRepetition()) { reason = "threefold"; result = "1/2-1/2"; }
    else if (chess.isDrawByFiftyMoves()) { reason = "fifty_moves"; result = "1/2-1/2"; }
    if (result) Object.assign(patch, { status: "finished", result, end_reason: reason, ended_at: iso(now), draw_offer_by: null });

    const updated = await this.db.updateIf(g.id, { ply: g.ply, status: "active" }, patch);
    if (!updated) {
      const fresh = await this.settle(await this.load(g.id));
      return { game: await this.view(fresh, uid), rejected: "Posisi sudah berubah" };
    }
    await this.ping(updated);
    return { game: await this.view(updated, uid) };
  }

  async resign(uid: string, body: Record<string, unknown>, retried = false): Promise<{ game: unknown }> {
    const g = await this.settle(await this.load(body.id));
    const me = colorOf(g, uid);
    if (!me) throw new GameError("Kamu bukan pemain di permainan ini", 403);
    if (g.status !== "active") return { game: await this.view(g, uid) };
    const now = iso(this.now());
    // Sebelum kedua pemain melangkah: dibatalkan, bukan kalah.
    const patch: Partial<Game> = g.ply < 2
      ? { status: "aborted", end_reason: "aborted", ended_at: now, updated_at: now, draw_offer_by: null }
      : { status: "finished", result: me === "w" ? "0-1" : "1-0", end_reason: "resign", ended_at: now, updated_at: now, draw_offer_by: null };
    const u = await this.db.updateIf(g.id, { ply: g.ply, status: "active" }, patch);
    if (!u) {
      // Ada langkah masuk barusan; ulang sekali dengan posisi terbaru.
      if (!retried) return this.resign(uid, body, true);
      throw new GameError("Gagal menyerah, coba lagi", 409);
    }
    await this.ping(u);
    return { game: await this.view(u, uid) };
  }

  async draw(uid: string, body: Record<string, unknown>) {
    const g = await this.settle(await this.load(body.id));
    const me = colorOf(g, uid);
    if (!me) throw new GameError("Kamu bukan pemain di permainan ini", 403);
    if (g.status !== "active") return { game: await this.view(g, uid) };
    const op = String(body.op ?? "");
    const now = iso(this.now());
    let patch: Partial<Game>;

    if (op === "offer") {
      if (g.ply < 2) throw new GameError("Tawaran remis bisa setelah kedua pemain melangkah");
      if (g.draw_offer_by === other(me)) {
        patch = { status: "finished", result: "1/2-1/2", end_reason: "agreement", ended_at: now, draw_offer_by: null };
      } else if (g.draw_offer_by === me) {
        return { game: await this.view(g, uid) };
      } else {
        patch = { draw_offer_by: me };
      }
    } else if (op === "accept") {
      if (g.draw_offer_by !== other(me)) throw new GameError("Tidak ada tawaran remis dari lawan", 409);
      patch = { status: "finished", result: "1/2-1/2", end_reason: "agreement", ended_at: now, draw_offer_by: null };
    } else if (op === "decline") {
      if (g.draw_offer_by !== other(me)) return { game: await this.view(g, uid) };
      patch = { draw_offer_by: null };
    } else {
      throw new GameError("Aksi remis tidak valid");
    }

    const u = await this.db.updateIf(g.id, { ply: g.ply, status: "active" }, { ...patch, updated_at: now });
    const res = u ?? (await this.settle(await this.load(g.id)));
    if (u) await this.ping(u);
    return { game: await this.view(res, uid) };
  }

  async rematch(uid: string, body: Record<string, unknown>) {
    const g = await this.load(body.id);
    const me = colorOf(g, uid);
    if (!me) throw new GameError("Kamu bukan pemain di permainan ini", 403);
    if (g.status !== "finished" && g.status !== "aborted") throw new GameError("Permainan belum selesai");
    const opp = opponentUid(g, uid)!;

    const existing = await this.db.findWaitingRematch(g.id);
    if (existing) {
      const fresh = await this.settle(existing);
      if (fresh.status === "waiting") {
        // Lawan sudah minta rematch duluan: langsung mulai.
        if (fresh.invitee_uid === uid) return this.accept(uid, { id: fresh.id });
        return { game: await this.view(fresh, uid) };
      }
    }

    const { waiting } = await this.countOpen(uid);
    if (waiting >= MAX_WAITING) throw new GameError(`Maksimal ${MAX_WAITING} tantangan menunggu. Batalkan salah satu dulu.`);

    const now = iso(this.now());
    const ng = await this.db.insert({
      creator_uid: uid,
      invitee_uid: opp,
      creator_color: other(me), // tukar warna
      status: "waiting",
      fen: START_FEN,
      moves: [],
      ply: 0,
      base_ms: g.base_ms,
      inc_ms: g.inc_ms,
      white_ms: g.base_ms,
      black_ms: g.base_ms,
      rematch_of: g.id,
      code: null,
      created_at: now,
      updated_at: now,
    });
    await this.ping(ng, [opp]);
    // Lawan yang sedang membuka layar permainan lama ikut dapat ping.
    try {
      await this.notify([`chess-game-${g.id}`], { id: g.id, ply: g.ply, status: g.status, rematch: ng.id });
    } catch { /* best-effort */ }
    return { game: await this.view(ng, uid) };
  }

  /**
   * Server ICE untuk panggilan suara di permainan ini. Hanya untuk kedua
   * pemain; sinyal panggilan sendiri lewat Realtime Broadcast antar-app.
   */
  async voiceIce(uid: string, body: Record<string, unknown>) {
    const g = await this.load(body.id);
    const me = colorOf(g, uid);
    if (!me) throw new GameError("Kamu bukan pemain di permainan ini", 403);
    if (g.status !== "active" && g.status !== "finished" && g.status !== "aborted") {
      throw new GameError("Panggilan suara bisa dipakai setelah permainan dimulai", 409);
    }
    const opponent = me === "w" ? g.black_uid : g.white_uid;
    const servers = this.ice ? await this.ice(uid) : [];
    return { ice_servers: servers, opponent_uid: opponent, turn_ready: servers.length > 0 };
  }

  async handle(uid: string, body: Record<string, unknown>) {
    switch (body.action) {
      case "list": return this.list(uid);
      case "get": return this.get(uid, body);
      case "live": return this.live(uid);
      case "create": return this.create(uid, body);
      case "join": return this.join(uid, body);
      case "accept": return this.accept(uid, body);
      case "decline": return this.decline(uid, body);
      case "cancel": return this.cancel(uid, body);
      case "move": return this.move(uid, body);
      case "resign": return this.resign(uid, body);
      case "draw": return this.draw(uid, body);
      case "rematch": return this.rematch(uid, body);
      case "voice_ice": return this.voiceIce(uid, body);
      default: throw new GameError("Aksi tidak dikenal");
    }
  }
}
