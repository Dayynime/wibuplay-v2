import 'package:dio/dio.dart';

import '../models/comment_models.dart';
import 'authed_function.dart';

/// Komentar episode lewat PostgREST Supabase (tabel `episode_comments`,
/// sama persis dengan Zenime). Port CommentRepository.kt.
class CommentRepository {
  CommentRepository(this._dio);

  final Dio _dio;

  static const String _columns =
      'id,episode_id,anime_id,firebase_uid,username,avatar_url,comment,'
      'parent_id,reply_to_username,created_at,is_pinned,reply_count';

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Satu request ambil SEMUA komentar + balasan episode ini, lalu disusun
  /// jadi pohon thread di sini.
  Future<CommentThreadResult> getComments(String episodeId) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/episode_comments',
      queryParameters: {
        'episode_id': 'eq.$episodeId',
        'select': _columns,
        'order': 'created_at.asc',
        'limit': 500,
      },
    );
    final rows = _rows(res.data).map(EpisodeComment.fromJson).toList();
    final topLevel = rows.where((c) => c.parentId == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final replies = <int, List<EpisodeComment>>{};
    for (final c in rows) {
      final p = c.parentId;
      if (p != null) replies.putIfAbsent(p, () => []).add(c);
    }
    for (final list in replies.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    return CommentThreadResult(
      topLevel: topLevel,
      repliesByParent: replies,
      totalCount: rows.length,
    );
  }

  Future<EpisodeComment> postComment({
    required String episodeId,
    required String animeId,
    required String firebaseUid,
    required String username,
    String? avatarUrl,
    required String comment,
    int? parentId,
    String? replyToUsername,
    bool isPinned = false,
    CommentMeta meta = const CommentMeta(),
  }) async {
    // UID, username, dan avatar diambil server dari token + profil, jadi
    // [firebaseUid], [username], [avatarUrl] sengaja TIDAK dikirim (anti
    // impersonasi). Parameter dipertahankan agar pemanggil lama tidak berubah.
    final data = await callAuthedFunction(_dio, 'comments-write', {
      'action': 'post',
      'episode_id': episodeId,
      'anime_id': animeId,
      'comment': comment,
      'parent_id': parentId,
      'reply_to_username': replyToUsername,
      'pinned': isPinned,
      'anime_title': meta.animeTitle,
      'anime_poster_url': meta.animePosterUrl,
      'episode_index': meta.episodeIndex,
    });
    if (data is! Map) {
      throw Exception('Server tidak mengembalikan komentar yang terkirim');
    }
    return EpisodeComment.fromJson(Map<String, dynamic>.from(data));
  }

  /// Hapus komentar/balasan milik sendiri. Server hanya menghapus kalau
  /// komentar itu milik uid di token ([firebaseUid] tidak dikirim).
  Future<void> deleteComment(int id, String firebaseUid) async {
    await callAuthedFunction(_dio, 'comments-write', {'action': 'delete', 'id': id});
  }

  /// Semua komentar/balasan MILIK 1 user lintas episode (tab Komentar di
  /// Profil), terbaru dulu, maks 50.
  Future<List<EpisodeComment>> getMyComments(String firebaseUid) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/episode_comments',
      queryParameters: {
        'firebase_uid': 'eq.$firebaseUid',
        'select': '$_columns,anime_title,anime_poster_url,episode_index',
        'order': 'created_at.desc',
        'limit': 50,
      },
    );
    return _rows(res.data).map(EpisodeComment.fromJson).toList();
  }

  /// Total komentar+balasan 1 user, dibaca dari header Content-Range
  /// ("0-0/123" atau "*/0"). null kalau gagal.
  Future<int?> getMyCommentCount(String firebaseUid) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/episode_comments',
      queryParameters: {'firebase_uid': 'eq.$firebaseUid', 'select': 'id', 'limit': 1},
      options: Options(
        headers: {'Prefer': 'count=exact'},
        validateStatus: (_) => true,
      ),
    );
    final code = res.statusCode ?? 0;
    if (code < 200 || code >= 300) return null;
    final range = res.headers.value('content-range');
    if (range == null || !range.contains('/')) return null;
    return int.tryParse(range.substring(range.indexOf('/') + 1));
  }
}
