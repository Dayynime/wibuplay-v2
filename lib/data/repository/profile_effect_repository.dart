import 'package:dio/dio.dart';

import '../models/profile_effect_models.dart';
import 'authed_function.dart';

class ProfileEffectException implements Exception {
  const ProfileEffectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Efek Profil: baca publik lewat view PostgREST, aksi (beli/pasang)
/// lewat Edge Function `wibuplay-profile-effect` dengan Firebase ID Token.
class ProfileEffectRepository {
  ProfileEffectRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'wibuplay-profile-effect';
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
      throw ProfileEffectException(_message(e, fallback));
    }
  }

  /// Efek yang sedang dipakai [uids] (1 request per 80 uid).
  Future<Map<String, ProfileEffect>> getEquippedForUids(List<String> uids) async {
    final distinct = uids.where(_uidRe.hasMatch).toSet().toList();
    final out = <String, ProfileEffect>{};
    for (var i = 0; i < distinct.length; i += 80) {
      final chunk = distinct.sublist(i, i + 80 > distinct.length ? distinct.length : i + 80);
      final res = await _dio.get<dynamic>(
        'rest/v1/profile_effect_equipped_view',
        queryParameters: {
          'firebase_uid': 'in.(${chunk.join(',')})',
          'select': 'firebase_uid,effect_id,layers',
        },
      );
      final data = res.data;
      if (data is! List) continue;
      for (final row in data.whereType<Map>()) {
        final uid = row['firebase_uid'];
        final id = row['effect_id'];
        if (uid is! String || id is! String || !isValidEffectId(id)) continue;
        final layers = ProfileEffectLayer.listFromJson(row['layers']);
        if (layers.isNotEmpty) out[uid] = ProfileEffect(id: id, layers: layers);
      }
    }
    return out;
  }

  Future<ProfileEffectState> getState() async =>
      ProfileEffectState.fromJson(await _call({'action': 'state'}, 'Gagal memuat efek'));

  /// Mengembalikan saldo ZCoin terbaru.
  Future<int> buy(String effectId) async {
    final d = await _call({'action': 'buy', 'effect_id': effectId}, 'Gagal membeli efek');
    return (d['balance'] as num?)?.toInt() ?? 0;
  }

  /// [effectId] null = lepas efek.
  Future<void> equip(String? effectId) async {
    await _call({'action': 'equip', 'effect_id': effectId}, 'Gagal memasang efek');
  }
}
