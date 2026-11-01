import 'package:dio/dio.dart';

import 'authed_function.dart';

class LevelBadgeException implements Exception {
  const LevelBadgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Satu badge level di shop (harga dari tabel `level_badge_catalog`).
class LevelBadgeOffer {
  const LevelBadgeOffer({
    required this.id,
    required this.label,
    required this.price,
    required this.owned,
    required this.active,
  });

  final String id;
  final String label;
  final int price;
  final bool owned;
  final bool active;
}

class LevelBadgeShop {
  const LevelBadgeShop({required this.offers, required this.equipped});

  final List<LevelBadgeOffer> offers;

  /// Badge yang sedang dipasang; null = badge level bawaan.
  final String? equipped;
}

/// Shop badge level: baca katalog/kepemilikan lewat PostgREST, beli & pasang
/// lewat Edge Function `zenime-level-badge` (UID diambil server dari token,
/// saldo ZCoin dipotong di server).
class LevelBadgeRepository {
  LevelBadgeRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'zenime-level-badge';
  static final RegExp _uidRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static List<Map<String, dynamic>> _rows(dynamic data) => data is List
      ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const <Map<String, dynamic>>[];

  String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String) return d['error'] as String;
      return 'Koneksi bermasalah, coba lagi.';
    }
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    return s.isEmpty || s.length > 200 ? fallback : s;
  }

  Future<LevelBadgeShop> getShop(String uid) async {
    if (!_uidRe.hasMatch(uid)) throw const LevelBadgeException('Kamu harus login dulu');
    try {
      final results = await Future.wait([
        _dio.get<dynamic>('rest/v1/level_badge_catalog', queryParameters: {
          'select': 'id,label,price,active,sort',
          'order': 'sort.asc',
        }),
        _dio.get<dynamic>('rest/v1/level_badges_owned', queryParameters: {
          'firebase_uid': 'eq.$uid',
          'select': 'badge_id',
        }),
        _dio.get<dynamic>('rest/v1/level_badge_equipped', queryParameters: {
          'firebase_uid': 'eq.$uid',
          'select': 'badge_id',
          'limit': 1,
        }),
      ]);
      final owned = {for (final r in _rows(results[1].data)) (r['badge_id'] as String?) ?? ''};
      final eq = _rows(results[2].data);
      return LevelBadgeShop(
        equipped: eq.isEmpty ? null : eq.first['badge_id'] as String?,
        offers: [
          for (final r in _rows(results[0].data))
            LevelBadgeOffer(
              id: (r['id'] as String?) ?? '',
              label: (r['label'] as String?) ?? '',
              price: (r['price'] as num?)?.toInt() ?? 0,
              active: r['active'] != false,
              owned: owned.contains(r['id']),
            ),
        ],
      );
    } catch (e) {
      throw LevelBadgeException(_msg(e, 'Gagal memuat shop badge level'));
    }
  }

  /// Beli lalu langsung pasang. Return saldo ZCoin terbaru.
  Future<int> buy(String badgeId) async {
    try {
      final d = await callAuthedFunction(_dio, _fn, {'action': 'buy', 'badge_id': badgeId});
      return d is Map ? (d['balance'] as num?)?.toInt() ?? 0 : 0;
    } catch (e) {
      throw LevelBadgeException(_msg(e, 'Gagal membeli badge'));
    }
  }

  /// Pasang badge milik sendiri; [badgeId] null = kembali ke bawaan.
  Future<void> equip(String? badgeId) async {
    try {
      await callAuthedFunction(_dio, _fn, {'action': 'equip', 'badge_id': badgeId});
    } catch (e) {
      throw LevelBadgeException(_msg(e, 'Gagal memasang badge'));
    }
  }
}
