/// Model catur mabar. Semua nilai berasal dari Edge Function `chess-game`;
/// app tidak menghitung aturan catur sendiri (langkah legal dikirim server).
library;

class ChessPlayer {
  const ChessPlayer({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.usernameColor,
  });

  final String uid;
  final String username;
  final String? avatarUrl;
  final String? usernameColor;

  static ChessPlayer? fromJson(dynamic v) {
    if (v is! Map) return null;
    final uid = v['uid'];
    if (uid is! String || uid.isEmpty) return null;
    final name = (v['username'] as String?)?.trim() ?? '';
    final avatar = v['avatar_url'] as String?;
    return ChessPlayer(
      uid: uid,
      username: name.isEmpty ? 'Pengguna Zenime' : name,
      avatarUrl: (avatar == null || avatar.isEmpty) ? null : avatar,
      usernameColor: v['username_color'] as String?,
    );
  }
}

class ChessStatus {
  ChessStatus._();
  static const String waiting = 'waiting';
  static const String active = 'active';
  static const String finished = 'finished';
  static const String aborted = 'aborted';
  static const String cancelled = 'cancelled';
  static const String declined = 'declined';
  static const String expired = 'expired';
}

/// Pilihan waktu (sama dengan TIME_PRESETS di server).
class ChessTimePreset {
  const ChessTimePreset(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;

  static const List<ChessTimePreset> all = [
    ChessTimePreset('3+2', '3 + 2', 'Kilat'),
    ChessTimePreset('5+0', '5 menit', 'Cepat'),
    ChessTimePreset('10+0', '10 menit', 'Santai'),
    ChessTimePreset('15+10', '15 + 10', 'Panjang'),
  ];
}

class ChessLastMove {
  const ChessLastMove(this.from, this.to, this.san);
  final String from;
  final String to;
  final String? san;
}

class ChessRematch {
  const ChessRematch(this.id, this.byMe);
  final String id;
  final bool byMe;
}

class ChessGame {
  const ChessGame({
    required this.id,
    required this.status,
    required this.fen,
    required this.ply,
    required this.turn,
    required this.isInvite,
    required this.creatorColor,
    required this.history,
    required this.legal,
    required this.inCheck,
    required this.baseMs,
    required this.incMs,
    required this.whiteMs,
    required this.blackMs,
    required this.serverNow,
    required this.receivedAt,
    this.result,
    this.endReason,
    this.code,
    this.creator,
    this.invitee,
    this.white,
    this.black,
    this.myColor,
    this.lastMove,
    this.clockRunning,
    this.turnStartedAt,
    this.firstMoveDeadline,
    this.drawOfferBy,
    this.expiresAt,
    this.rematch,
  });

  final String id;
  final String status;
  final String? result; // '1-0', '0-1', '1/2-1/2'
  final String? endReason;
  final String? code; // hanya untuk pembuat room yang masih menunggu
  final bool isInvite;
  final String creatorColor; // 'w', 'b', 'random'
  final ChessPlayer? creator;
  final ChessPlayer? invitee;
  final ChessPlayer? white;
  final ChessPlayer? black;
  final String? myColor; // 'w', 'b', null = belum mulai / penonton
  final String turn; // 'w' / 'b'
  final String fen;
  final int ply;
  final List<String> history; // SAN
  final ChessLastMove? lastMove;
  final bool inCheck;

  /// Langkah legal (UCI, mis. e2e4 / e7e8q). Kosong kalau bukan giliranku.
  final List<String> legal;
  final int baseMs;
  final int incMs;
  final int whiteMs;
  final int blackMs;
  final String? clockRunning; // 'w' / 'b' / null
  final DateTime? turnStartedAt;
  final DateTime? firstMoveDeadline;
  final String? drawOfferBy;
  final DateTime? expiresAt;
  final ChessRematch? rematch;

  /// Jam server saat respons dibuat, dan jam HP saat respons diterima.
  /// Selisihnya dipakai supaya jam catur tidak terpengaruh jam HP yang salah.
  final DateTime serverNow;
  final DateTime receivedAt;

  bool get isWaiting => status == ChessStatus.waiting;
  bool get isActive => status == ChessStatus.active;
  bool get isOver => status == ChessStatus.finished || status == ChessStatus.aborted;
  bool get isClosed =>
      status == ChessStatus.cancelled || status == ChessStatus.declined || status == ChessStatus.expired;
  bool get isMyTurn => isActive && myColor != null && myColor == turn;

  ChessPlayer? get me => myColor == 'w' ? white : (myColor == 'b' ? black : null);

  ChessPlayer? opponentOf(String myUid) {
    if (white?.uid == myUid) return black;
    if (black?.uid == myUid) return white;
    if (creator?.uid == myUid) return invitee;
    if (invitee?.uid == myUid) return creator;
    return null;
  }

  /// Sisa waktu (ms) untuk [color] saat ini, dihitung dari data server.
  int remainingMs(String color, {DateTime? nowLocal}) {
    final base = color == 'w' ? whiteMs : blackMs;
    if (clockRunning != color || turnStartedAt == null) return base;
    final serverNowEst = serverNow.add((nowLocal ?? DateTime.now()).difference(receivedAt));
    final left = base - serverNowEst.difference(turnStartedAt!).inMilliseconds;
    return left < 0 ? 0 : left;
  }

  /// Sisa waktu langkah pertama (sebelum jam berjalan), null kalau tidak berlaku.
  int? firstMoveLeftMs({DateTime? nowLocal}) {
    final d = firstMoveDeadline;
    if (d == null) return null;
    final serverNowEst = serverNow.add((nowLocal ?? DateTime.now()).difference(receivedAt));
    final left = d.difference(serverNowEst).inMilliseconds;
    return left < 0 ? 0 : left;
  }

  /// Hasil dari sudut pandang [color]: 'win', 'loss', 'draw', atau null.
  String? outcomeFor(String? color) {
    if (status != ChessStatus.finished || color == null || result == null) return null;
    if (result == '1/2-1/2') return 'draw';
    final whiteWon = result == '1-0';
    return (whiteWon == (color == 'w')) ? 'win' : 'loss';
  }

  static DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;

  static List<String> _strings(dynamic v) =>
      v is List ? v.whereType<String>().toList(growable: false) : const <String>[];

  factory ChessGame.fromJson(Map<String, dynamic> j) {
    final lm = j['last_move'];
    final rm = j['rematch'];
    return ChessGame(
      id: j['id'] as String? ?? '',
      status: j['status'] as String? ?? ChessStatus.expired,
      result: j['result'] as String?,
      endReason: j['end_reason'] as String?,
      code: j['code'] as String?,
      isInvite: j['is_invite'] == true,
      creatorColor: j['creator_color'] as String? ?? 'random',
      creator: ChessPlayer.fromJson(j['creator']),
      invitee: ChessPlayer.fromJson(j['invitee']),
      white: ChessPlayer.fromJson(j['white']),
      black: ChessPlayer.fromJson(j['black']),
      myColor: j['my_color'] as String?,
      turn: j['turn'] == 'b' ? 'b' : 'w',
      fen: j['fen'] as String? ?? '',
      ply: (j['ply'] as num?)?.toInt() ?? 0,
      history: _strings(j['history']),
      lastMove: lm is Map && lm['from'] is String && lm['to'] is String
          ? ChessLastMove(lm['from'] as String, lm['to'] as String, lm['san'] as String?)
          : null,
      inCheck: j['in_check'] == true,
      legal: _strings(j['legal']),
      baseMs: (j['base_ms'] as num?)?.toInt() ?? 0,
      incMs: (j['inc_ms'] as num?)?.toInt() ?? 0,
      whiteMs: (j['white_ms'] as num?)?.toInt() ?? 0,
      blackMs: (j['black_ms'] as num?)?.toInt() ?? 0,
      clockRunning: j['clock_running'] as String?,
      turnStartedAt: _date(j['turn_started_at']),
      firstMoveDeadline: _date(j['first_move_deadline']),
      drawOfferBy: j['draw_offer_by'] as String?,
      expiresAt: _date(j['expires_at']),
      rematch: rm is Map && rm['id'] is String ? ChessRematch(rm['id'] as String, rm['by_me'] == true) : null,
      serverNow: _date(j['server_now']) ?? DateTime.now().toUtc(),
      receivedAt: DateTime.now(),
    );
  }
}

/// Isi lobby: tantangan masuk, yang sedang menunggu lawan, yang berjalan, dan riwayat.
class ChessLobby {
  const ChessLobby({
    required this.incoming,
    required this.waiting,
    required this.active,
    required this.recent,
  });

  final List<ChessGame> incoming;
  final List<ChessGame> waiting;
  final List<ChessGame> active;
  final List<ChessGame> recent;

  bool get isEmpty => incoming.isEmpty && waiting.isEmpty && active.isEmpty && recent.isEmpty;

  static List<ChessGame> _games(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => ChessGame.fromJson(Map<String, dynamic>.from(e))).toList()
      : const <ChessGame>[];

  factory ChessLobby.fromJson(Map<String, dynamic> j) => ChessLobby(
        incoming: _games(j['incoming']),
        waiting: _games(j['waiting']),
        active: _games(j['active']),
        recent: _games(j['recent']),
      );
}

/// Hasil kirim langkah: posisi terbaru + alasan kalau langkah ditolak server.
class ChessMoveResult {
  const ChessMoveResult(this.game, this.rejected);
  final ChessGame game;
  final String? rejected;
}

/// Teks akhir permainan untuk ditampilkan.
String chessEndText(ChessGame g) {
  switch (g.endReason) {
    case 'checkmate':
      return 'Skakmat';
    case 'resign':
      return 'Menyerah';
    case 'timeout':
      return 'Waktu habis';
    case 'stalemate':
      return 'Remis: pat, tidak ada langkah';
    case 'insufficient':
      return 'Remis: bidak tidak cukup untuk skakmat';
    case 'threefold':
      return 'Remis: posisi sama terulang 3 kali';
    case 'fifty_moves':
      return 'Remis: 50 langkah tanpa makan atau gerak pion';
    case 'agreement':
      return 'Remis disepakati';
    case 'no_first_move':
      return 'Dibatalkan: langkah pertama tidak dimainkan';
    case 'aborted':
      return 'Dibatalkan sebelum kedua pemain melangkah';
  }
  return g.status == ChessStatus.aborted ? 'Dibatalkan' : '';
}
