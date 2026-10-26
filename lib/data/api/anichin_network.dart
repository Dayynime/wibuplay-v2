import 'dart:async';

import 'package:dio/dio.dart';

import 'premium_token_manager.dart';

/// Klien HTTP donghua. Sumbernya langsung situs v1.anichin.space (sama dengan
/// web anichin-web): halaman SvelteKit `.../__data.json` dan `/api/*`.
///
/// TESTING: base URL ditulis langsung di [baseUrl], TIDAK dari Remote Config,
/// supaya `anichin_base_url` milik app versi publik tidak tersentuh.
/// Token Premium tetap ditempel ke request episode (`watch/...`), seperti
/// versi lama yang menempel ke `episode/` dan `video-source/`.
class AnichinNetwork {
  AnichinNetwork._();

  /// Base URL sumber donghua (harus diakhiri "/").
  static const String baseUrl = 'https://v1.anichin.space/';

  // Link video OK.ru menolak (HTTP 400) kalau User-Agent bukan browser,
  // termasuk User-Agent bawaan player. Referer juga dibutuhkan.
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36';
  static const String videoReferer = 'https://ok.ru/';

  /// Host gambar relatif (kalau ada). Thumbnail dari sumber umumnya sudah
  /// berupa URL absolut.
  static String sourceBase = 'https://v1.anichin.space';

  static void updateSourceBase(String? source) {
    if (source == null) return;
    final uri = Uri.tryParse(source);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return;
    sourceBase = '${uri.scheme}://${uri.host}';
  }

  /// Ubah path relatif jadi URL absolut yang bisa dimuat image loader.
  static String? imageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('//')) return 'https:$path';
    if (path.startsWith('/')) return sourceBase + path;
    return '$sourceBase/$path';
  }

  /// Header gambar dari situs sumber (kalau tidak, sering diblok).
  static Map<String, String> get imageHeaders => {
        'User-Agent': userAgent,
        'Referer': '$sourceBase/',
      };

  /// Header buat pemutar video (link OK.ru).
  static Map<String, String> get videoHeaders => {
        'User-Agent': userAgent,
        'Referer': videoReferer,
      };
}

/// Donghua khusus Premium. Request halaman episode (`watch/<slug>/...`) diberi
/// token premium bertanda tangan server (edge function `zenime-premium-token`).
/// Hanya dikirim ke host [AnichinNetwork.baseUrl], tidak ke OK.ru / host lain.
class _PremiumTokenInterceptor extends Interceptor {
  _PremiumTokenInterceptor(this._dio, this._tokens);

  final Dio _dio;
  final PremiumTokenManager _tokens;
  static const String _retriedKey = 'anichin_token_retried';
  static bool _guarded(RequestOptions o) {
    final host = Uri.tryParse(o.baseUrl)?.host;
    if (host == null || host.isEmpty || o.uri.host != host) return false;
    final segs = o.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segs.length >= 2 && segs.first == 'watch';
  }

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_guarded(options)) {
      final token = await _tokens.get();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    final hadToken = o.headers['Authorization'] != null;
    if (err.response?.statusCode != 401 ||
        !_guarded(o) ||
        !hadToken ||
        o.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }
    // Token ditolak (kadaluarsa / secret diputar) -> buang, ambil baru, coba sekali lagi.
    _tokens.invalidate();
    final fresh = await _tokens.get();
    if (fresh == null) {
      handler.next(err);
      return;
    }
    o.extra[_retriedKey] = true;
    o.headers['Authorization'] = 'Bearer $fresh';
    try {
      handler.resolve(await _dio.fetch<dynamic>(o));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// GET aman diulang sekali kalau koneksi putus (timeout sengaja tidak diulang).
class _AnichinRetryInterceptor extends Interceptor {
  _AnichinRetryInterceptor(this._dio);

  final Dio _dio;
  static const String _retriedKey = 'anichin_retried';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    final retryable = o.method.toUpperCase() == 'GET' &&
        (err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.connectionTimeout) &&
        o.extra[_retriedKey] != true;
    if (!retryable) {
      handler.next(err);
      return;
    }
    o.extra[_retriedKey] = true;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    try {
      handler.resolve(await _dio.fetch<dynamic>(o));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

Dio createAnichinDio(PremiumTokenManager tokens) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AnichinNetwork.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': AnichinNetwork.userAgent,
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );
  dio.interceptors.addAll([
    _PremiumTokenInterceptor(dio, tokens),
    _AnichinRetryInterceptor(dio),
  ]);
  return dio;
}
