import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/supabase_config.dart';
import '../models/sticker_models.dart';
import 'authed_function.dart';

/// Error yang pesannya siap ditampilkan ke user.
class StickerException implements Exception {
  const StickerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Stiker: katalog dibaca publik lewat PostgREST (view `sticker_catalog`),
/// upload & review lewat Edge Function `sticker` (Firebase ID Token).
class StickerRepository {
  StickerRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'sticker';
  static const int maxUploadBytes = 1024 * 1024;

  static final RegExp _uuidRe =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static final RegExp _pathRe = RegExp(r'^[0-9a-f-]{36}\.(png|webp|gif|jpg)$');
  static final RegExp _tokenRe = RegExp(r'^[A-Za-z0-9._-]{20,2048}$');
  static final RegExp _codeRe = RegExp(r'^[A-Za-z0-9]{8}$');

  String _message(Object e, String fallback) {
    if (e is StickerException) return e.message;
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String && (d['error'] as String).trim().isNotEmpty) {
        return (d['error'] as String).trim();
      }
      return 'Koneksi bermasalah, coba lagi.';
    }
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    return s.isEmpty || s.length > 200 ? fallback : s;
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, _fn, body);
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } catch (e) {
      throw StickerException(_message(e, fallback));
    }
  }

  static List<Map<String, dynamic>> _rows(Object? v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

  // ------------------------------------------------------------ katalog

  /// Semua stiker yang disetujui (terbaru dulu).
  Future<List<Sticker>> catalog() async {
    final res = await _dio.get<dynamic>(
      'rest/v1/sticker_catalog',
      queryParameters: {'select': 'code,name,path', 'order': 'approved_at.desc', 'limit': 1000},
    );
    return _rows(res.data).map(Sticker.fromJson).where((s) => s.code.isNotEmpty).toList();
  }

  /// Satu stiker berdasarkan kode (null = tidak ada / belum disetujui).
  Future<Sticker?> byCode(String code) async {
    if (!_codeRe.hasMatch(code)) return null;
    final res = await _dio.get<dynamic>(
      'rest/v1/sticker_catalog',
      queryParameters: {'select': 'code,name,path', 'code': 'eq.$code', 'limit': 1},
    );
    final rows = _rows(res.data);
    return rows.isEmpty ? null : Sticker.fromJson(rows.first);
  }

  // ------------------------------------------------------------ upload

  /// Jenis file dari isi (magic bytes), bukan dari ekstensi.
  static Future<String?> detectMime(String path) async {
    final raf = await File(path).open();
    try {
      final h = await raf.read(12);
      String s(int a, int b) => String.fromCharCodes(h.sublist(a, b));
      if (h.length >= 8 && h[0] == 0x89 && s(1, 4) == 'PNG') return 'image/png';
      if (h.length >= 3 && h[0] == 0xFF && h[1] == 0xD8 && h[2] == 0xFF) return 'image/jpeg';
      if (h.length >= 6 && (s(0, 6) == 'GIF87a' || s(0, 6) == 'GIF89a')) return 'image/gif';
      if (h.length >= 12 && s(0, 4) == 'RIFF' && s(8, 12) == 'WEBP') return 'image/webp';
      return null;
    } finally {
      await raf.close();
    }
  }

  /// sign (server cek Premium + kuota) -> upload ke signed URL bucket privat
  /// -> register (server cek file, masuk antrean review).
  Future<void> upload({
    required String filePath,
    required String name,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(filePath);
    final size = await file.length();
    if (size <= 0 || size > maxUploadBytes) {
      throw const StickerException('Ukuran file maksimal 1 MB');
    }
    final mime = await detectMime(filePath);
    if (mime == null) throw const StickerException('File harus PNG, JPG, WebP, atau GIF');

    final signed = await _call({'action': 'sign', 'name': name.trim(), 'mime': mime}, 'Gagal menyiapkan upload');
    final id = signed['id'];
    final path = signed['path'];
    final token = signed['token'];
    if (id is! String ||
        !_uuidRe.hasMatch(id) ||
        path is! String ||
        !_pathRe.hasMatch(path) ||
        token is! String ||
        !_tokenRe.hasMatch(token)) {
      throw const StickerException('Respons server tidak valid');
    }

    final uploader = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    try {
      await uploader.put<dynamic>(
        '${SupabaseConfig.url}/storage/v1/object/upload/sign/sticker-staging/$path',
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
      throw StickerException(_message(e, 'Upload file gagal'));
    } finally {
      uploader.close();
    }

    await _call({'action': 'register', 'id': id}, 'Gagal mendaftarkan stiker');
  }

  Future<List<MySticker>> mine() async {
    final d = await _call({'action': 'mine'}, 'Gagal memuat stiker kamu');
    return _rows(d['items']).map(MySticker.fromJson).toList();
  }

  // ------------------------------------------------------------ admin

  /// [status]: pending | approved | rejected | removed
  Future<List<AdminSticker>> adminList(String status, {int offset = 0}) async {
    final d = await _call(
      {'action': 'admin_list', 'status': status, 'offset': offset},
      'Gagal memuat stiker',
    );
    return _rows(d['items']).map(AdminSticker.fromJson).toList();
  }

  /// [op]: approve | reject | remove
  Future<void> adminReview(String id, String op, {String? reason}) async {
    await _call(
      {'action': 'admin_review', 'id': id, 'op': op, if (reason != null) 'reason': reason},
      'Aksi gagal, coba lagi',
    );
  }
}
