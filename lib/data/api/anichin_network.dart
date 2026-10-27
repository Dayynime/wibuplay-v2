import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:dio/dio.dart';
import 'package:flutter/scheduler.dart';

import 'premium_token_manager.dart';

/// Klien HTTP donghua. Data dari server cache sendiri (api.zenime.biz.id/app-api/)
/// yang mencerminkan v1.anichin.space: halaman SvelteKit `.../__data.json` dan `/api/*`.
///
/// TESTING: base URL ditulis langsung di [baseUrl], TIDAK dari Remote Config,
/// supaya `anichin_base_url` milik app versi publik tidak tersentuh.
/// Token Premium tetap ditempel ke request episode (`watch/...`), seperti
/// versi lama yang menempel ke `episode/` dan `video-source/`.
class AnichinNetwork {
  AnichinNetwork._();

  /// Base URL donghua (harus diakhiri "/"). Server cache sendiri di VPS
  /// (anichin-web/app_api.py) yang mencerminkan JSON v1.anichin.space dengan
  /// path yang sama. Ganti ke 'https://v1.anichin.space/' untuk langsung ke sumber.
  static const String baseUrl = 'https://api.zenime.biz.id/app-api/';

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

  /// Header pemutar sesuai host link: OK.ru butuh Referer ok.ru, Dailymotion
  /// Referer dailymotion, lainnya Referer situs sumber.
  static Map<String, String> headersFor(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.contains('ok.ru') || host.contains('okcdn')) return videoHeaders;
    if (host == 'rmb.anichin.bio' || host.endsWith('rumble.cloud') || host.endsWith('rumble.com')) {
      return {'User-Agent': userAgent, 'Referer': 'https://rmb.anichin.bio/'};
    }
    if (host.contains('dailymotion') || host.contains('dmcdn')) {
      return {'User-Agent': userAgent, 'Referer': 'https://www.dailymotion.com/'};
    }
    return {'User-Agent': userAgent, 'Referer': '$sourceBase/'};
  }

  /// Header buat pemutar video (link OK.ru).
  static Map<String, String> get videoHeaders => {
        'User-Agent': userAgent,
        'Referer': videoReferer,
      };
}

/// DIAGNOSA SEMENTARA: catat lama tiap langkah donghua di HP, lalu kirim ke
/// VPS lewat header `X-App-Timing` pada request `health` (terbaca di log
/// Caddy). Tidak berisi data pribadi: cuma path, durasi (ms), dan ukuran.
class AnichinTiming {
  AnichinTiming._();

  static final List<String> _queue = [];
  static Dio? _dio;
  static Timer? _flush;
  static final Stopwatch _clock = Stopwatch()..start();
  static bool _framesHooked = false;
  static int _slowFrames = 0;
  static int _worstBuild = 0;
  static int _worstRaster = 0;

  /// Detik sejak app dibuka, supaya urutan & jeda antar langkah kelihatan.
  static String get _t => '+${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(2)}s';

  static void add(String entry) {
    _queue.add('$_t ${entry.replaceAll(RegExp(r'[^\x20-\x7E]'), '?')}');
    if (_queue.length > 20) _queue.removeAt(0);
    _schedule();
  }

  static void _schedule() {
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 3), _send);
  }

  /// Catat frame yang lambat (> 100 ms build atau raster) = app terasa macet.
  static void hookFrames() {
    if (_framesHooked) return;
    _framesHooked = true;
    try {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    } catch (_) {
      // belum ada binding (mis. unit test) -> lewati
    }
  }

  static void _onTimings(List<FrameTiming> timings) {
      for (final f in timings) {
        final b = f.buildDuration.inMilliseconds;
        final r = f.rasterDuration.inMilliseconds;
        if (b > 100 || r > 100) {
          _slowFrames++;
          if (b > _worstBuild) _worstBuild = b;
          if (r > _worstRaster) _worstRaster = r;
          if (_slowFrames <= 3 || b > 500 || r > 500) {
            _queue.add('$_t FRAME build=${b}ms raster=${r}ms');
            if (_queue.length > 20) _queue.removeAt(0);
          }
          _schedule();
        }
      }
  }

  static Future<void> _send() async {
    final dio = _dio;
    if (dio == null) return;
    if (_slowFrames > 0) {
      _queue.add('$_t FRAMES lambat=$_slowFrames terburuk build=${_worstBuild}ms raster=${_worstRaster}ms');
      _slowFrames = 0;
      _worstBuild = 0;
      _worstRaster = 0;
    }
    if (_queue.isEmpty) return;
    var value = _queue.join(' | ');
    _queue.clear();
    if (value.length > 1500) value = value.substring(value.length - 1500);
    try {
      await dio.get<dynamic>('health', options: Options(headers: {'X-App-Timing': value}));
    } catch (_) {}
  }
}

class _TimingInterceptor extends Interceptor {
  static bool _skip(RequestOptions o) => o.path.startsWith('health');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['t0'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  int _ms(RequestOptions o) =>
      DateTime.now().millisecondsSinceEpoch - ((o.extra['t0'] as int?) ?? 0);

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    if (!_skip(o)) {
      final d = response.data;
      final size = d is String ? d.length : 0;
      AnichinTiming.add('net ${o.uri.path.replaceFirst('/app-api/', '')} ${_ms(o)}ms ${size}B');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    if (!_skip(o)) {
      AnichinTiming.add('ERR ${o.uri.path.replaceFirst('/app-api/', '')} ${_ms(o)}ms ${err.type.name}');
    }
    handler.next(err);
  }
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
      final sw = Stopwatch()..start();
      final token = await _tokens.get();
      AnichinTiming.add('token ${sw.elapsedMilliseconds}ms ${token == null ? "none" : "ok"}');
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
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': AnichinNetwork.userAgent,
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );
  dio.interceptors.addAll([
    _PremiumTokenInterceptor(dio, tokens),
    _TimingInterceptor(),
    _AnichinRetryInterceptor(dio),
  ]);
  AnichinTiming._dio = dio;
  AnichinTiming.hookFrames();
  return dio;
}
