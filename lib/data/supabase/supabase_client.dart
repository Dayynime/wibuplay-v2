import 'package:dio/dio.dart';

import '../../core/supabase_config.dart';

/// Dio khusus Supabase Zenime (PostgREST + Edge Function).
///
/// Semua request membawa header `apikey` (anon key). Header `Authorization`
/// default-nya juga anon key, KECUALI request sudah mengisinya sendiri
/// (Edge Function yang butuh Firebase ID Token asli) - itu tidak ditimpa.
Dio createSupabaseDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: '${SupabaseConfig.url}/',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: {
        'apikey': SupabaseConfig.anonKey,
        'Content-Type': 'application/json',
      },
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers.putIfAbsent(
          'Authorization',
          () => 'Bearer ${SupabaseConfig.anonKey}',
        );
        handler.next(options);
      },
    ),
  );
  return dio;
}
