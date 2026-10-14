import 'package:dio/dio.dart';

import '../models/avatar_frame_models.dart';
import 'authed_function.dart';

class AvatarFrameException implements Exception {
  const AvatarFrameException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Border Avatar: baca publik lewat view PostgREST, aksi (beli/pasang)
/// lewat Edge Function `wibuplay-avatar-frame` dengan Firebase ID Token.
class AvatarFrameRepository {
  AvatarFrameRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'wibuplay-avatar-frame';
  static final RegExp _uidRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  String _message(Object e, String fallback) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return 'Koneksi bermasalah, coba lagi.';
        default:
          return fallback;
      }
    }
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    return s.isEmpty || s.length > 200 ? fallback : s;
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, _fn, body);
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } catch (e) {
      throw AvatarFrameException(_message(e, fallback));
    }
  }

  /// Border yang sedang dipakai [uids] (1 request per 80 uid).
  Future<Map<String, String>> getEquippedForUids(List<String> uids) async {
    final distinct = uids.where(_uidRe.hasMatch).toSet().toList();
    final out = <String, String>{};
    for (var i = 0; i < distinct.length; i += 80) {
      final chunk = distinct.sublist(i, i + 80 > distinct.length ? distinct.length : i + 80);
      final res = await _dio.get<dynamic>(
        'rest/v1/avatar_frame_equipped_view',
        queryParameters: {
          'firebase_uid': 'in.(${chunk.join(',')})',
          'select': 'firebase_uid,frame_id',
        },
      );
      final data = res.data;
      if (data is! List) continue;
      for (final row in data.whereType<Map>()) {
        final uid = row['firebase_uid'];
        final id = row['frame_id'];
        if (uid is String && id is String && kAvatarFrameAssets.containsKey(id)) out[uid] = id;
      }
    }
    return out;
  }

  Future<AvatarFrameState> getState() async =>
      AvatarFrameState.fromJson(await _call({'action': 'state'}, 'Gagal memuat border'));

  /// Mengembalikan saldo ZCoin terbaru.
  Future<int> buy(String frameId) async {
    final d = await _call({'action': 'buy', 'frame_id': frameId}, 'Gagal membeli border');
    return (d['balance'] as num?)?.toInt() ?? 0;
  }

  /// [frameId] null = lepas border.
  Future<void> equip(String? frameId) async {
    await _call({'action': 'equip', 'frame_id': frameId}, 'Gagal memasang border');
  }
}
