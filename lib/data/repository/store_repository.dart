import 'package:dio/dio.dart';

import '../models/store_models.dart';

/// Daftar paket Premium & ZCoin (Supabase Edge Function, sama dengan Zenime).
/// Kode akun dan saldo diambil lewat AccountRepository. Melempar kalau gagal,
/// supaya UI bisa menampilkan error + tombol coba lagi.
class StoreRepository {
  StoreRepository(this._dio);

  final Dio _dio;

  Future<List<T>> _list<T>(
    String function,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final res = await _dio.get<dynamic>('functions/v1/$function');
    final data = res.data;
    final raw = data is Map ? data['packages'] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => parse(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<PremiumPackage>> getPremiumPackages() =>
      _list('zenime-list-packages', PremiumPackage.fromJson);

  Future<List<CoinPackage>> getCoinPackages() =>
      _list('zenime-list-coin-packages', CoinPackage.fromJson);
}
