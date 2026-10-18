import 'package:dio/dio.dart';

import 'authed_function.dart';

/// Data satu layar dalam satu request (Edge Function `screen-data`).
class ScreenDataRepository {
  ScreenDataRepository(this._dio);

  final Dio _dio;

  /// Data Profil publik [uid]. Mentah (Map); dipecah jadi titipan di layar.
  Future<Map<String, dynamic>> profile(String uid) async {
    final d = await callAuthedFunction(_dio, 'screen-data', {'screen': 'profile', 'uid': uid});
    if (d is! Map) throw Exception('Respons screen-data tidak valid');
    return Map<String, dynamic>.from(d);
  }

  /// Data Halaman Clan [clanId]. [since] = awal "hari ini" menurut jam HP
  /// (buat ranking Donasi Hari Ini).
  Future<Map<String, dynamic>> clan(String clanId, String since) async {
    final d = await callAuthedFunction(
        _dio, 'screen-data', {'screen': 'clan', 'clan_id': clanId, 'since': since});
    if (d is! Map) throw Exception('Respons screen-data tidak valid');
    return Map<String, dynamic>.from(d);
  }
}
