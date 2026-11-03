import 'package:dio/dio.dart';

import '../models/nobar_models.dart';
import 'authed_function.dart';

class NobarException implements Exception {
  const NobarException(this.message, {this.status});
  final String message;

  /// Status HTTP dari server (403 = sudah bukan anggota, 404 = room tutup).
  final int? status;

  bool get roomGone => status == 403 || status == 404;

  @override
  String toString() => message;
}

/// Nobar lewat Edge Function `nobar-room`. UID diambil server dari Firebase
/// ID Token; kapasitas (maks 5), host, dan kick ditentukan server.
class NobarRepository {
  NobarRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'nobar-room';

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, _fn, body);
      if (d is Map) return Map<String, dynamic>.from(d);
      throw NobarException(fallback);
    } on NobarException {
      rethrow;
    } on DioException catch (e) {
      final d = e.response?.data;
      final msg = d is Map && d['error'] is String ? d['error'] as String : 'Koneksi bermasalah, coba lagi.';
      throw NobarException(msg, status: e.response?.statusCode);
    } catch (e) {
      final s = e.toString().replaceFirst('Exception: ', '').trim();
      // callAuthedFunction mengubah error server jadi Exception(pesan); status
      // tidak ikut, jadi kenali dari isi pesannya.
      final gone = s.contains('sudah ditutup') || s.contains('tidak ada di room') || s.contains('dikeluarkan');
      throw NobarException(s.isEmpty || s.length > 200 ? fallback : s, status: gone ? 404 : null);
    }
  }

  NobarRoom _room(Map<String, dynamic> d, String fallback) {
    final r = d['room'];
    if (r is! Map) throw NobarException(fallback);
    return NobarRoom.fromJson(Map<String, dynamic>.from(r));
  }

  Future<NobarRoom> create({
    required String movieId,
    required String episodeId,
    String? movieTitle,
    String? posterUrl,
    int positionMs = 0,
  }) async {
    const f = 'Gagal membuat room nobar';
    return _room(
      await _call({
        'action': 'create',
        'movie_id': movieId,
        'episode_id': episodeId,
        if (movieTitle != null) 'movie_title': movieTitle,
        if (posterUrl != null) 'poster_url': posterUrl,
        'position_ms': positionMs,
      }, f),
      f,
    );
  }

  Future<NobarRoom> joinByCode(String code) async {
    const f = 'Gagal masuk room';
    return _room(await _call({'action': 'join', 'code': code}, f), f);
  }

  Future<NobarRoom> joinById(String id) async {
    const f = 'Gagal masuk room';
    return _room(await _call({'action': 'join', 'id': id}, f), f);
  }

  /// Ambil data room terbaru, sekaligus heartbeat "aku masih di sini".
  Future<NobarRoom> get(String id) async {
    const f = 'Gagal memuat room';
    return _room(await _call({'action': 'get', 'id': id}, f), f);
  }

  Future<void> leave(String id) async {
    await _call({'action': 'leave', 'id': id}, 'Gagal keluar room');
  }

  Future<NobarRoom> kick(String id, String uid) async {
    const f = 'Gagal mengeluarkan anggota';
    return _room(await _call({'action': 'kick', 'id': id, 'uid': uid}, f), f);
  }

  /// Host menyimpan status video (untuk anggota yang baru masuk).
  Future<void> saveState(String id, {required String episodeId, required int positionMs, required bool playing}) async {
    await _call({
      'action': 'state',
      'id': id,
      'episode_id': episodeId,
      'position_ms': positionMs,
      'playing': playing,
    }, 'Gagal menyimpan status');
  }

  Future<NobarIce> ice(String id) async {
    final d = await _call({'action': 'ice', 'id': id}, 'Gagal menyiapkan voice chat');
    return NobarIce.fromJson(d);
  }

  Future<List<NobarRoom>> myRooms() async {
    final d = await _call({'action': 'list'}, 'Gagal memuat room');
    final list = d['rooms'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => NobarRoom.fromJson(Map<String, dynamic>.from(e))).toList();
  }
}
