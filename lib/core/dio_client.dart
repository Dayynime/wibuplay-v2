import 'package:dio/dio.dart';

import 'constants.dart';
import 'remote_config_manager.dart';

/// Port dynamicBaseUrlInterceptor (NetworkModule.kt): host API diganti di TIAP
/// request dengan nilai terbaru dari Remote Config. Kalau belum ada base URL
/// (parameter kosong / belum pernah fetch sukses), request digagalkan dengan
/// pesan jelas, TIDAK jatuh ke URL manapun.
class DynamicBaseUrlInterceptor extends Interceptor {
  static const String unavailableMessage = 'Server sedang tidak tersedia. Coba lagi nanti.';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final base = RemoteConfigManager.baseUrl;
    if (base == null) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          message: unavailableMessage,
        ),
        true,
      );
      return;
    }
    options.baseUrl = base;
    handler.next(options);
  }
}

/// Port HeaderInterceptor: Referer + User-Agent di setiap request.
class HeaderInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Referer'] = Constants.referer;
    options.headers['User-Agent'] = Constants.userAgent;
    handler.next(options);
  }
}

/// Port RetryInterceptor: GET yang gagal karena error koneksi diulang 1x.
/// Timeout (connect/receive/send) tidak diulang, sama seperti versi Kotlin
/// yang mengecualikan SocketTimeoutException.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio);

  final Dio _dio;
  static const String _retriedKey = 'wibuplay_retried';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final isGet = options.method.toUpperCase() == 'GET';
    final alreadyRetried = options.extra[_retriedKey] == true;
    final isConnectionError = err.type == DioExceptionType.connectionError;

    if (isGet && isConnectionError && !alreadyRetried) {
      options.extra[_retriedKey] = true;
      try {
        final response = await _dio.fetch<dynamic>(options);
        handler.resolve(response);
      } on DioException catch (e) {
        handler.next(e);
      }
      return;
    }
    handler.next(err);
  }
}

/// Dio dengan konfigurasi sama seperti NetworkClient.kt.
///
/// responseType = plain: body dikembalikan sebagai String, lalu didecode
/// lewat `JsonHelper.decodeEnvelope`. Ini menghindari ketergantungan pada
/// Content-Type server yang tidak konsisten.
Dio createDio() {
  final dio = Dio(
    BaseOptions(
      // Placeholder; host sebenarnya diisi DynamicBaseUrlInterceptor tiap request.
      baseUrl: 'https://placeholder.invalid/',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.plain,
    ),
  );
  dio.interceptors.addAll([
    DynamicBaseUrlInterceptor(),
    HeaderInterceptor(),
    RetryInterceptor(dio),
  ]);
  return dio;
}
