import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/dio_client.dart';
import '../../core/remote_config_manager.dart';
import 'premium_token_manager.dart';

/// Klien HTTP khusus API Anichin (donghua). Port AnichinNetwork.kt.
///
/// Terpisah dari [createDio] karena backend-nya lain: base URL dari parameter
/// Remote Config `anichin_base_url`.
class AnichinNetwork {
  AnichinNetwork._();

  // Link video OK.ru menolak (HTTP 400) kalau User-Agent bukan browser,
  // termasuk User-Agent bawaan player. Referer juga dibutuhkan.
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36';
  static const String videoReferer = 'https://ok.ru/';

  /// Thumbnail dari API berbentuk path relatif ("/wp-content/uploads/...") dan
  /// host-nya ikut situs sumber. Default di bawah, lalu otomatis diperbarui
  /// dari field `source` di tiap response.
  static String sourceBase = 'https://anichin.moe';

  static void updateSourceBase(String? source) {
    if (source == null) return;
    final uri = Uri.tryParse(source);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return;
    sourceBase = '${uri.scheme}://${uri.host}';
  }

  /// Ubah path relatif dari API jadi URL absolut yang bisa dimuat image loader.
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

/// Ganti host di TIAP request dengan `anichin_base_url` terbaru. Kalau kosong,
/// request digagalkan dengan pesan jelas (kill-switch), tanpa fallback.
class _AnichinBaseUrlInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final base = RemoteConfigManager.anichinBaseUrl;
    if (base == null) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          message: DynamicBaseUrlInterceptor.unavailableMessage,
        ),
        true,
      );
      return;
    }
    options.baseUrl = base;
    handler.next(options);
  }
}

/// Donghua khusus Premium. Endpoint `episode/` dan `video-source/` dijaga di
/// SERVER; app cuma menempelkan token premium bertanda tangan server. Kalau
/// tidak ada / ditolak, server yang menolak.
class _PremiumTokenInterceptor extends Interceptor {
  _PremiumTokenInterceptor(this._dio, this._tokens);

  final Dio _dio;
  final PremiumTokenManager _tokens;
  static const String _retriedKey = 'anichin_token_retried';

  static bool _guarded(RequestOptions o) {
    final segs = o.path.split('?').first.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.length < 2) return false;
    final parent = segs[segs.length - 2];
    return parent == 'episode' || parent == 'video-source';
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
        err.type == DioExceptionType.connectionError &&
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
      // Placeholder; host sebenarnya diisi _AnichinBaseUrlInterceptor tiap request.
      baseUrl: 'https://placeholder.invalid/',
      connectTimeout: const Duration(seconds: 20),
      // Endpoint scraping bisa 5-8 detik, kasih napas panjang.
      receiveTimeout: const Duration(seconds: 45),
      responseType: ResponseType.plain,
    ),
  );
  dio.interceptors.addAll([
    _AnichinBaseUrlInterceptor(),
    _PremiumTokenInterceptor(dio, tokens),
    _AnichinRetryInterceptor(dio),
  ]);
  return dio;
}
