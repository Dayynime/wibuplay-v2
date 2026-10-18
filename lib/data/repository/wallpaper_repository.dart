import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/supabase_config.dart';
import '../models/wallpaper_models.dart';
import 'authed_function.dart';

/// Error yang pesannya siap ditampilkan ke user.
class WallpaperException implements Exception {
  const WallpaperException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Wallpaper Komentar: baca publik lewat PostgREST (view), semua aksi lewat
/// Edge Function dengan Firebase ID Token. App TIDAK pernah memegang service
/// key, tidak menulis tabel langsung, dan tidak memilih path/bucket upload.
class WallpaperRepository {
  WallpaperRepository(this._dio);

  final Dio _dio;

  static const int maxUploadBytes = 5 * 1024 * 1024;

  static final RegExp _uidRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final RegExp _uuidRe =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static final RegExp _tokenRe = RegExp(r'^[A-Za-z0-9._-]{20,2048}$');

  String _message(Object e, String fallback) {
    if (e is WallpaperException) return e.message;
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String && (d['error'] as String).trim().isNotEmpty) {
        return (d['error'] as String).trim();
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return 'Koneksi bermasalah, coba lagi.';
        default:
          return fallback;
      }
    }
    // callAuthedFunction melempar Exception(pesan server)
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    return s.isEmpty || s.length > 200 ? fallback : s;
  }

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, fn, body);
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } catch (e) {
      throw WallpaperException(_message(e, fallback));
    }
  }

  // ------------------------------------------------------------ publik

  /// Wallpaper yang sedang dipakai [uids] (1 request per 80 uid).
  Future<Map<String, CommentWallpaper>> getEquippedForUids(List<String> uids) async {
    final distinct = uids.where(_uidRe.hasMatch).toSet().toList();
    final out = <String, CommentWallpaper>{};
    for (var i = 0; i < distinct.length; i += 80) {
      final chunk = distinct.sublist(i, i + 80 > distinct.length ? distinct.length : i + 80);
      final res = await _dio.get<dynamic>(
        'rest/v1/wp_equipped_view',
        queryParameters: {
          'firebase_uid': 'in.(${chunk.join(',')})',
          'select': 'firebase_uid,wallpaper_id,rarity,file_name',
        },
      );
      final data = res.data;
      if (data is! List) continue;
      for (final row in data.whereType<Map>()) {
        final m = Map<String, dynamic>.from(row);
        final uid = m['firebase_uid'];
        final w = CommentWallpaper.fromJson(m);
        if (uid is String && w != null) out[uid] = w;
      }
    }
    return out;
  }

  // ------------------------------------------------------------ user

  Future<WallpaperState> getState() async => WallpaperState.fromJson(
        await _call('wibuplay-wallpaper-user', {'action': 'state'}, 'Gagal memuat wallpaper'),
      );

  /// [count] 1 atau 10. Harga & hasil ditentukan server.
  Future<SpinResult> spin({int count = 1}) async {
    final d = await _call(
      'wibuplay-wallpaper-user',
      {'action': 'spin', 'count': count},
      'Spin gagal, coba lagi',
    );
    final r = SpinResult.fromJson(d);
    if (r == null) throw const WallpaperException('Spin gagal, coba lagi');
    return r;
  }

  /// [wallpaperId] null = lepas wallpaper.
  Future<void> equip(String? wallpaperId) async {
    await _call(
      'wibuplay-wallpaper-user',
      {'action': 'equip', 'wallpaper_id': wallpaperId},
      'Gagal memasang wallpaper',
    );
  }

  // ------------------------------------------------------------ admin

  /// Cek isi file (magic bytes), bukan cuma ekstensi.
  static Future<String?> detectMime(String path) async {
    final raf = await File(path).open();
    try {
      final h = await raf.read(12);
      if (h.length >= 6) {
        final sig = String.fromCharCodes(h.sublist(0, 6));
        if (sig == 'GIF87a' || sig == 'GIF89a') return 'image/gif';
      }
      if (h.length >= 12 &&
          String.fromCharCodes(h.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(h.sublist(8, 12)) == 'WEBP') {
        return 'image/webp';
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Alur: sign (server cek role + kuota, buat path) -> upload ke signed URL
  /// bucket privat -> register (server cek file di storage, masuk antrean).
  Future<void> uploadWallpaper({
    required String filePath,
    required String name,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(filePath);
    final size = await file.length();
    if (size <= 0 || size > maxUploadBytes) {
      throw const WallpaperException('Ukuran file maksimal 5 MB');
    }
    final mime = await detectMime(filePath);
    if (mime == null) throw const WallpaperException('File harus GIF atau WebP');

    final signed = await _call(
      'wibuplay-wallpaper-sign',
      {'name': name.trim(), 'mime': mime},
      'Gagal menyiapkan upload',
    );
    final jobId = signed['job_id'];
    final path = signed['path'];
    final token = signed['token'];
    if (jobId is! String ||
        !_uuidRe.hasMatch(jobId) ||
        path is! String ||
        !_uuidRe.hasMatch(path) ||
        token is! String ||
        !_tokenRe.hasMatch(token)) {
      throw const WallpaperException('Respons server tidak valid');
    }

    final uploader = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 3),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    try {
      await uploader.put<dynamic>(
        '${SupabaseConfig.url}/storage/v1/object/upload/sign/wp-staging/$path',
        queryParameters: {'token': token},
        data: file.openRead(),
        options: Options(
          headers: {
            'apikey': SupabaseConfig.anonKey,
            Headers.contentTypeHeader: mime,
            Headers.contentLengthHeader: size,
            'x-upsert': 'false',
          },
        ),
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) onProgress(sent / total);
        },
      );
    } catch (e) {
      throw WallpaperException(_message(e, 'Upload file gagal'));
    } finally {
      uploader.close();
    }

    await _call('wibuplay-wallpaper-register', {'job_id': jobId}, 'Gagal mendaftarkan upload');
  }

  Future<AdminWallpaperPage> adminList(String filter, {int offset = 0}) async {
    final d = await _call(
      'wibuplay-wallpaper-admin',
      {'action': 'list', 'filter': filter, 'offset': offset},
      'Gagal memuat daftar wallpaper',
    );
    List<Map<String, dynamic>> rows(Object? v) =>
        v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
    return AdminWallpaperPage(
      items: rows(d['items']).map(AdminWallpaper.fromJson).toList(),
      jobs: rows(d['jobs']).map(AdminUploadJob.fromJson).toList(),
      hasMore: d['has_more'] == true,
    );
  }

  /// [action]: approve | reject | activate | deactivate | update | remove
  Future<void> adminReview(
    String id,
    String action, {
    WallpaperRarity? rarity,
    int? weight,
    String? name,
  }) async {
    await _call(
      'wibuplay-wallpaper-admin',
      {
        'action': action,
        'id': id,
        if (rarity != null) 'rarity': rarity.name,
        if (weight != null) 'weight': weight,
        if (name != null) 'name': name,
      },
      'Aksi gagal, coba lagi',
    );
  }
}
