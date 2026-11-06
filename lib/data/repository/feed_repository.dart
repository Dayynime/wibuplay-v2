import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/supabase_config.dart';
import 'authed_function.dart';
import 'sticker_repository.dart' show StickerRepository;

/// Postingan di Feed (Edge Function `feed`).
class FeedPost {
  const FeedPost({
    required this.id,
    required this.uid,
    required this.username,
    required this.body,
    required this.likeCount,
    required this.commentCount,
    required this.liked,
    required this.createdAt,
    this.avatarUrl,
    this.usernameColor,
    this.userNumber,
    this.imagePath,
    this.imageW,
    this.imageH,
  });

  final int id;
  final String uid;
  final String username;
  final String? avatarUrl;
  final String? usernameColor;
  final int? userNumber;
  final String body;
  final String? imagePath;
  final int? imageW;
  final int? imageH;
  final int likeCount;
  final int commentCount;
  final bool liked;
  final DateTime createdAt;

  String? get imageUrl =>
      imagePath == null ? null : '${SupabaseConfig.url}/storage/v1/object/public/feed/$imagePath';

  /// Rasio gambar (lebar/tinggi), dibatasi supaya kartu tidak terlalu tinggi.
  double get imageRatio {
    final w = imageW ?? 0;
    final h = imageH ?? 0;
    if (w <= 0 || h <= 0) return 4 / 3;
    return (w / h).clamp(0.75, 2.0).toDouble();
  }

  FeedPost copyWith({bool? liked, int? likeCount, int? commentCount}) => FeedPost(
        id: id,
        uid: uid,
        username: username,
        avatarUrl: avatarUrl,
        usernameColor: usernameColor,
        userNumber: userNumber,
        body: body,
        imagePath: imagePath,
        imageW: imageW,
        imageH: imageH,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        liked: liked ?? this.liked,
        createdAt: createdAt,
      );

  static FeedPost? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = (v['id'] as num?)?.toInt();
    final uid = v['uid'];
    if (id == null || uid is! String) return null;
    final img = v['image_path'] as String?;
    return FeedPost(
      id: id,
      uid: uid,
      username: (v['username'] as String?) ?? 'Pengguna',
      avatarUrl: v['avatar_url'] as String?,
      usernameColor: v['username_color'] as String?,
      userNumber: (v['user_number'] as num?)?.toInt(),
      body: (v['body'] as String?) ?? '',
      imagePath: (img == null || img.isEmpty) ? null : img,
      imageW: (v['image_w'] as num?)?.toInt(),
      imageH: (v['image_h'] as num?)?.toInt(),
      likeCount: (v['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (v['comment_count'] as num?)?.toInt() ?? 0,
      liked: v['liked'] == true,
      createdAt: DateTime.tryParse((v['created_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

class FeedComment {
  const FeedComment({
    required this.id,
    required this.postId,
    required this.uid,
    required this.username,
    required this.body,
    required this.createdAt,
    this.avatarUrl,
    this.usernameColor,
  });

  final int id;
  final int postId;
  final String uid;
  final String username;
  final String? avatarUrl;
  final String? usernameColor;
  final String body;
  final DateTime createdAt;

  static FeedComment? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = (v['id'] as num?)?.toInt();
    final uid = v['uid'];
    if (id == null || uid is! String) return null;
    return FeedComment(
      id: id,
      postId: (v['post_id'] as num?)?.toInt() ?? 0,
      uid: uid,
      username: (v['username'] as String?) ?? 'Pengguna',
      avatarUrl: v['avatar_url'] as String?,
      usernameColor: v['username_color'] as String?,
      body: (v['body'] as String?) ?? '',
      createdAt: DateTime.tryParse((v['created_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

class FeedException implements Exception {
  const FeedException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FeedRepository {
  FeedRepository(this._dio);

  final Dio _dio;

  static const int maxImageBytes = 2 * 1024 * 1024;
  static final RegExp _uuidRe = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static final RegExp _pathRe = RegExp(r'^[0-9a-f-]{36}\.(png|webp|jpg)$');
  static final RegExp _tokenRe = RegExp(r'^[A-Za-z0-9._-]{20,2048}$');

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final d = await callAuthedFunction(_dio, 'feed', body);
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } on DioException catch (_) {
      throw const FeedException('Koneksi bermasalah, coba lagi');
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '').trim();
      throw FeedException(m.isEmpty || m.length > 200 ? fallback : m);
    }
  }

  /// [tab]: 'all' | 'friends'. [before] = id postingan terakhir yang sudah dimuat.
  Future<List<FeedPost>> list(String tab, {int before = 0}) async {
    final d = await _call({'action': 'list', 'tab': tab, if (before > 0) 'before': before}, 'Gagal memuat feed');
    final l = d['posts'];
    return l is List ? l.map(FeedPost.fromJson).whereType<FeedPost>().toList() : const [];
  }

  Future<FeedPost> get(int id) async {
    final d = await _call({'action': 'get', 'id': id}, 'Gagal memuat postingan');
    final p = FeedPost.fromJson(d['post']);
    if (p == null) throw const FeedException('Postingan tidak ditemukan');
    return p;
  }

  /// Bikin postingan. [imagePath] opsional (file lokal hasil pilih galeri).
  Future<FeedPost> create({
    required String body,
    String? imagePath,
    int? width,
    int? height,
    void Function(double progress)? onProgress,
  }) async {
    String? uploadId;
    if (imagePath != null) {
      final file = File(imagePath);
      final size = await file.length();
      if (size <= 0 || size > maxImageBytes) throw const FeedException('Ukuran gambar maksimal 2 MB');
      final mime = await StickerRepository.detectMime(imagePath);
      if (mime == null || mime == 'image/gif') throw const FeedException('Gambar harus JPG, PNG, atau WebP');

      final signed = await _call({'action': 'upload_sign', 'mime': mime}, 'Gagal menyiapkan upload');
      final id = signed['id'];
      final path = signed['path'];
      final token = signed['token'];
      if (id is! String ||
          !_uuidRe.hasMatch(id) ||
          path is! String ||
          !_pathRe.hasMatch(path) ||
          token is! String ||
          !_tokenRe.hasMatch(token)) {
        throw const FeedException('Respons server tidak valid');
      }
      final uploader = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(seconds: 60),
      ));
      try {
        await uploader.put<dynamic>(
          '${SupabaseConfig.url}/storage/v1/object/upload/sign/feed-staging/$path',
          queryParameters: {'token': token},
          data: file.openRead(),
          options: Options(headers: {
            'apikey': SupabaseConfig.anonKey,
            Headers.contentTypeHeader: mime,
            Headers.contentLengthHeader: size,
            'x-upsert': 'false',
          }),
          onSendProgress: (sent, total) {
            if (onProgress != null && total > 0) onProgress(sent / total);
          },
        );
      } catch (_) {
        throw const FeedException('Upload gambar gagal, coba lagi');
      } finally {
        uploader.close();
      }
      uploadId = id;
    }

    final d = await _call({
      'action': 'create',
      'body': body,
      if (uploadId != null) 'upload_id': uploadId,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    }, 'Gagal membuat postingan');
    final p = FeedPost.fromJson(d['post']);
    if (p == null) throw const FeedException('Gagal membuat postingan');
    return p;
  }

  Future<void> delete(int id) => _call({'action': 'delete', 'id': id}, 'Gagal menghapus postingan');

  /// Return jumlah like terbaru.
  Future<int> like(int id, bool on) async {
    final d = await _call({'action': 'like', 'id': id, 'on': on}, 'Gagal menyukai postingan');
    return (d['like_count'] as num?)?.toInt() ?? 0;
  }

  Future<List<FeedComment>> comments(int postId, {int after = 0}) async {
    final d = await _call({'action': 'comments', 'post_id': postId, if (after > 0) 'after': after}, 'Gagal memuat komentar');
    final l = d['comments'];
    return l is List ? l.map(FeedComment.fromJson).whereType<FeedComment>().toList() : const [];
  }

  Future<FeedComment> comment(int postId, String body) async {
    final d = await _call({'action': 'comment', 'post_id': postId, 'body': body}, 'Gagal mengirim komentar');
    final c = FeedComment.fromJson(d['comment']);
    if (c == null) throw const FeedException('Gagal mengirim komentar');
    return c;
  }

  Future<void> deleteComment(int id) => _call({'action': 'comment_delete', 'id': id}, 'Gagal menghapus komentar');
}
