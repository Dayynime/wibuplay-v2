import 'package:dio/dio.dart';

import '../models/comment_models.dart';

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
    final res = await _dio.post<dynamic>(
      'rest/v1/episode_comments',
      data: {
        'episode_id': episodeId,
        'anime_id': animeId,
        'firebase_uid': firebaseUid,
        'username': username,
        'avatar_url': avatarUrl,
        'comment': comment,
        'parent_id': parentId,
        'reply_to_username': replyToUsername,
        'is_pinned': isPinned,
        'anime_title': meta.animeTitle,
        'anime_poster_url': meta.animePosterUrl,
        'episode_index': meta.episodeIndex,
      },
      options: Options(headers: {'Prefer': 'return=representation'}),
    );
    final rows = _rows(res.data);
    if (rows.isEmpty) {
      throw Exception('Server tidak mengembalikan komentar yang terkirim');
    }
    return EpisodeComment.fromJson(rows.first);
  }

  /// Hapus komentar/balasan milik sendiri (firebase_uid ikut difilter di query).
  Future<void> deleteComment(int id, String firebaseUid) async {
    await _dio.delete<dynamic>(
      'rest/v1/episode_comments',
      queryParameters: {'id': 'eq.$id', 'firebase_uid': 'eq.$firebaseUid'},
    );
  }
}
