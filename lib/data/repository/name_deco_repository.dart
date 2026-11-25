import 'package:dio/dio.dart';

import 'authed_function.dart';

class NameDecoException implements Exception {
  const NameDecoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Satu dekorasi nama di shop (harga dari tabel `name_deco_catalog`).
class NameDecoOffer {
  const NameDecoOffer({
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

class NameDecoShop {
  const NameDecoShop({required this.offers, required this.equipped});

  final List<NameDecoOffer> offers;

  /// Dekorasi yang sedang dipasang; null = nama biasa.
  final String? equipped;
}

/// Shop dekorasi nama: baca katalog/kepemilikan lewat PostgREST, beli & pasang
/// lewat Edge Function `zenime-name-deco` (UID diambil server dari token,
/// saldo ZCoin dipotong di server).
class NameDecoRepository {
  NameDecoRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'zenime-name-deco';
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

  Future<NameDecoShop> getShop(String uid) async {
    if (!_uidRe.hasMatch(uid)) throw const NameDecoException('Kamu harus login dulu');
    try {
      final results = await Future.wait([
        _dio.get<dynamic>('rest/v1/name_deco_catalog', queryParameters: {
          'select': 'id,label,price,active,sort',
          'order': 'sort.asc',
        }),
        _dio.get<dynamic>('rest/v1/name_decos_owned', queryParameters: {
          'firebase_uid': 'eq.$uid',
          'select': 'deco_id',
        }),
        _dio.get<dynamic>('rest/v1/name_deco_equipped', queryParameters: {
          'firebase_uid': 'eq.$uid',
          'select': 'deco_id',
          'limit': 1,
        }),
      ]);
      final owned = {for (final r in _rows(results[1].data)) (r['deco_id'] as String?) ?? ''};
      final eq = _rows(results[2].data);
      return NameDecoShop(
        equipped: eq.isEmpty ? null : eq.first['deco_id'] as String?,
        offers: [
          for (final r in _rows(results[0].data))
            NameDecoOffer(
              id: (r['id'] as String?) ?? '',
              label: (r['label'] as String?) ?? '',
              price: (r['price'] as num?)?.toInt() ?? 0,
              active: r['active'] != false,
              owned: owned.contains(r['id']),
            ),
        ],
      );
    } catch (e) {
      throw NameDecoException(_msg(e, 'Gagal memuat shop dekorasi nama'));
    }
  }

  /// Beli lalu langsung pasang. Return saldo ZCoin terbaru.
  Future<int> buy(String decoId) async {
    try {
      final d = await callAuthedFunction(_dio, _fn, {'action': 'buy', 'deco_id': decoId});
      return d is Map ? (d['balance'] as num?)?.toInt() ?? 0 : 0;
    } catch (e) {
      throw NameDecoException(_msg(e, 'Gagal membeli dekorasi'));
    }
  }

  /// Pasang dekorasi milik sendiri; [decoId] null = nama biasa.
  Future<void> equip(String? decoId) async {
    try {
      await callAuthedFunction(_dio, _fn, {'action': 'equip', 'deco_id': decoId});
    } catch (e) {
      throw NameDecoException(_msg(e, 'Gagal memasang dekorasi'));
    }
  }
}
