import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_config.dart';

/// Panggil Edge Function Supabase dengan Firebase ID Token asli di header
/// Authorization. UID user diambil SERVER dari token, jadi jangan kirim
/// `firebase_uid` di body. Pesan `error` dari server dilempar sebagai Exception.
Future<dynamic> callAuthedFunction(
  Dio dio,
  String function,
  Map<String, dynamic> body,
) async {
  if (!FirebaseConfig.ready) {
    throw Exception('Login belum tersedia di perangkat ini.');
  }
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null || token.isEmpty) {
    throw Exception('Kamu harus login dulu');
  }
  try {
    final res = await dio.post<dynamic>(
      'functions/v1/$function',
      data: body,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return res.data;
  } catch (e) {
    if (e is DioException) {
      final d = e.response?.data;
      final msg = d is Map ? d['error'] : null;
      if (msg is String && msg.trim().isNotEmpty) throw Exception(msg.trim());
    }
    rethrow;
  }
}
