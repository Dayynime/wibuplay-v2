import 'package:dio/dio.dart';

import '../models/chess_models.dart';
import 'authed_function.dart';

class ChessException implements Exception {
  const ChessException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Catur mabar lewat Edge Function `chess-game`. UID diambil server dari
/// Firebase ID Token; langkah legal, giliran, jam, dan hasil ditentukan server.
class ChessRepository {
  ChessRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'chess-game';

  String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String) return d['error'] as String;
      return 'Koneksi bermasalah, coba lagi.';
    }
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    return s.isEmpty || s.length > 200 ? fallback : s;
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, _fn, body);
      if (d is Map) return Map<String, dynamic>.from(d);
      throw ChessException(fallback);
    } on ChessException {
      rethrow;
    } catch (e) {
      throw ChessException(_msg(e, fallback));
    }
  }

  ChessGame _game(Map<String, dynamic> d, String fallback) {
    final g = d['game'];
    if (g is! Map) throw ChessException(fallback);
    return ChessGame.fromJson(Map<String, dynamic>.from(g));
  }

  Future<ChessLobby> lobby() async {
    final d = await _call({'action': 'list'}, 'Gagal memuat permainan catur');
    return ChessLobby.fromJson(d);
  }

  Future<ChessGame> get(String id) async {
    const f = 'Gagal memuat permainan';
    return _game(await _call({'action': 'get', 'id': id}, f), f);
  }

  /// Tantang teman ([inviteeUid] diisi) atau buat room dengan kode (null).
  Future<ChessGame> create({required String time, required String color, String? inviteeUid}) async {
    const f = 'Gagal membuat tantangan';
    return _game(
      await _call({
        'action': 'create',
        'time': time,
        'color': color,
        if (inviteeUid != null) 'invitee_uid': inviteeUid,
      }, f),
      f,
    );
  }

  Future<ChessGame> join(String code) async {
    const f = 'Gagal masuk room';
    return _game(await _call({'action': 'join', 'code': code}, f), f);
  }

  Future<ChessGame> accept(String id) async {
    const f = 'Gagal menerima tantangan';
    return _game(await _call({'action': 'accept', 'id': id}, f), f);
  }

  Future<ChessGame> decline(String id) async {
    const f = 'Gagal menolak tantangan';
    return _game(await _call({'action': 'decline', 'id': id}, f), f);
  }

  Future<ChessGame> cancel(String id) async {
    const f = 'Gagal membatalkan tantangan';
    return _game(await _call({'action': 'cancel', 'id': id}, f), f);
  }

  /// Kirim langkah UCI (e2e4, e7e8q). [ply] = jumlah langkah di posisi yang
  /// dilihat user; server menolak kalau posisinya sudah berubah.
  Future<ChessMoveResult> move(String id, String uci, int ply) async {
    const f = 'Gagal mengirim langkah';
    final d = await _call({'action': 'move', 'id': id, 'move': uci, 'ply': ply}, f);
    return ChessMoveResult(_game(d, f), d['rejected'] as String?);
  }

  Future<ChessGame> resign(String id) async {
    const f = 'Gagal menyerah';
    return _game(await _call({'action': 'resign', 'id': id}, f), f);
  }

  /// [op]: 'offer', 'accept', atau 'decline'.
  Future<ChessGame> draw(String id, String op) async {
    const f = 'Gagal memproses remis';
    return _game(await _call({'action': 'draw', 'id': id, 'op': op}, f), f);
  }

  /// Server ICE untuk panggilan suara (hanya untuk kedua pemain).
  Future<ChessVoiceIce> voiceIce(String id) async {
    final d = await _call({'action': 'voice_ice', 'id': id}, 'Gagal menyiapkan panggilan suara');
    return ChessVoiceIce.fromJson(d);
  }

  Future<ChessGame> rematch(String id) async {
    const f = 'Gagal mengajak main lagi';
    return _game(await _call({'action': 'rematch', 'id': id}, f), f);
  }
}
