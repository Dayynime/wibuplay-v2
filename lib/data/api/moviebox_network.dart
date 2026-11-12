import 'package:dio/dio.dart';

import '../../core/dio_client.dart';
import '../../core/remote_config_manager.dart';

/// Klien HTTP film (MovieBox). Data dari server sendiri di VPS Zenime
/// (moviebox-flask, service `moviebox-api`) yang membungkus API MovieBox:
/// signature, token guest, buang video "trap", ambil link asli dari
/// resourceDetectors. App cukup memanggil JSON yang sudah rapi.
///
/// Base URL dari Firebase Remote Config parameter `moviebox_base_url`
/// (mis. https://moviebox.zenime.biz.id/). TIDAK ada fallback hardcode:
/// parameter kosong = fitur Film mati (bisa dipakai sebagai kill-switch).
class MovieBoxNetwork {
  MovieBoxNetwork._();

  /// Pesan sama dengan API anime supaya errorMessage() menampilkannya apa adanya.
  static const String unavailableMessage = DynamicBaseUrlInterceptor.unavailableMessage;

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Header gambar poster (pbcdn.aoneroom.com). Tanpa Referer.
  static const Map<String, String> imageHeaders = {'User-Agent': userAgent};

  static Dio createDio() {
    final dio = Dio(
      BaseOptions(
        // Diganti tiap request oleh _MovieBoxBaseUrlInterceptor.
        baseUrl: 'https://placeholder.invalid/',
        connectTimeout: const Duration(seconds: 10),
        // /api/stream memanggil beberapa sumber MovieBox sekaligus, bisa lama.
        receiveTimeout: const Duration(seconds: 45),
        responseType: ResponseType.json,
        headers: const {'User-Agent': userAgent},
      ),
    );
    dio.interceptors.add(_MovieBoxBaseUrlInterceptor());
    return dio;
  }

  /// Header CDN per link video (Cookie bertanda tangan / Referer), diisi
  /// repository saat mengambil stream. Dipakai pemutar yang hanya tahu
  /// link-nya (Nobar, mini player).
  static final Map<String, Map<String, String>> _videoHeaders = {};

  static void rememberHeaders(String url, Map<String, String> headers) {
    if (_videoHeaders.length > 200) _videoHeaders.clear();
    _videoHeaders[url] = headers;
  }

  /// null = bukan link film MovieBox (pakai header bawaan pemutar).
  static Map<String, String>? headersFor(String url) => _videoHeaders[url];

  /// Dio terpisah untuk file subtitle di CDN (bukan server sendiri).
  static Dio createSubtitleDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.bytes,
          headers: const {'User-Agent': userAgent},
        ),
      );
}

/// Host diganti di TIAP request dengan nilai terbaru Remote Config (sama
/// seperti DynamicBaseUrlInterceptor API anime). Belum ada nilai = request
/// digagalkan dengan pesan jelas.
class _MovieBoxBaseUrlInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final base = RemoteConfigManager.movieBoxBaseUrl;
    if (base == null) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          message: MovieBoxNetwork.unavailableMessage,
        ),
        true,
      );
      return;
    }
    options.baseUrl = base;
    handler.next(options);
  }
}
