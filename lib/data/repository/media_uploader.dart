import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/supabase_config.dart';
import '../supabase/supabase_client.dart';
import 'authed_function.dart';

/// Upload gambar (foto/banner profil, foto/banner clan) ke Supabase Storage,
/// pengganti Cloudinary (akun Cloudinary dinonaktifkan karena kuota free).
///
/// Alur: Edge Function `media-upload` (cek login, leader clan) memberi
/// bucket + path + token -> file di-PUT ke signed URL -> URL publik dipakai.
/// Bucket & path selalu ditentukan SERVER.
class MediaUploader {
  MediaUploader._();

  static final Dio _api = createSupabaseDio();
  static const int maxBytes = 10 * 1024 * 1024;

  static final RegExp _bucketRe = RegExp(r'^(chat-avatars|chat-banners|clan-media)$');
  static final RegExp _pathRe = RegExp(r'^[A-Za-z0-9_/.-]{5,300}$');
  static final RegExp _tokenRe = RegExp(r'^[A-Za-z0-9._-]{20,4096}$');

  /// Jenis file dari isi (magic bytes), bukan ekstensi.
  static Future<String?> _detectMime(String path) async {
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

  /// [kind]: avatar | banner | clan_photo | clan_banner. Mengembalikan URL publik.
  static Future<String> upload(String filePath, {required String kind, String? clanId}) async {
    final file = File(filePath);
    final size = await file.length();
    if (size <= 0 || size > maxBytes) throw Exception('Ukuran gambar maksimal 10 MB');
    final mime = await _detectMime(filePath);
    if (mime == null) throw Exception('File harus JPG, PNG, WebP, atau GIF');

    final d = await callAuthedFunction(_api, 'media-upload', {
      'action': 'sign',
      'kind': kind,
      'mime': mime,
      'size': size,
      if (clanId != null && clanId.isNotEmpty) 'clan_id': clanId,
    });
    final bucket = d is Map ? d['bucket'] : null;
    final path = d is Map ? d['path'] : null;
    final token = d is Map ? d['token'] : null;
    if (bucket is! String ||
        !_bucketRe.hasMatch(bucket) ||
        path is! String ||
        !_pathRe.hasMatch(path) ||
        path.contains('..') ||
        token is! String ||
        !_tokenRe.hasMatch(token)) {
      throw Exception('Respons server tidak valid');
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
        '${SupabaseConfig.url}/storage/v1/object/upload/sign/$bucket/$path',
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
      );
    } on DioException catch (e) {
      final m = e.response?.data;
      final msg = m is Map ? (m['message'] ?? m['error']) : null;
      throw Exception(msg is String && msg.isNotEmpty ? 'Upload gagal: $msg' : 'Upload gambar gagal, periksa koneksi');
    } finally {
      uploader.close();
    }
    return '${SupabaseConfig.url}/storage/v1/object/public/$bucket/$path';
  }
}
