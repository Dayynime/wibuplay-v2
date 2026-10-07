import 'dart:convert';

import 'package:dio/dio.dart';

/// Klien HTTP komik (port ComicApi.kt + comicOkHttpClient di NetworkModule.kt).
///
/// Memanggil LANGSUNG API komik Sanka. Publik, tanpa apikey, base URL fixed
/// (bukan dari Remote Config seperti API anime/donghua). Satu base URL dipakai
/// semua sumber: .../comic/{bacakomik|westmanga}/...
class ComicNetwork {
  ComicNetwork._();

  static const String baseUrl = 'https://www.sankavollerei.web.id/comic/';

  /// Gambar komik (cover + halaman chapter): UA browser, TANPA Referer.
  static const String imageUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static Map<String, String> get imageHeaders => const {
        'User-Agent': imageUserAgent,
      };

  /// "//x" -> "https://x", "http://x" -> "https://x" (cleartext diblok Android).
  static String? normalizeImageUrl(String? url) {
    final u = url?.trim();
    if (u == null || u.isEmpty) return null;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('http://')) return 'https://${u.substring(7)}';
    return u;
  }
}

/// GET aman diulang sekali kalau koneksi putus (setara retryOnConnectionFailure OkHttp).
class _ComicRetryInterceptor extends Interceptor {
  _ComicRetryInterceptor(this._dio);

  final Dio _dio;
  static const String _retriedKey = 'comic_retried';

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

Dio createComicDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: ComicNetwork.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
    ),
  );
  dio.interceptors.add(_ComicRetryInterceptor(dio));
  return dio;
}

/// GET lalu decode JSON object. Melempar exception kalau bukan object.
Future<Map<String, dynamic>> comicGetMap(
  Dio dio,
  String path, {
  Map<String, dynamic>? query,
}) async {
  final res = await dio.get<dynamic>(path, queryParameters: query);
  var data = res.data;
  if (data is String) data = data.trim().isEmpty ? null : jsonDecode(data);
  if (data is Map) return Map<String, dynamic>.from(data);
  throw Exception('Respons server tidak dikenali.');
}

String comicEnc(String s) => Uri.encodeComponent(s);
