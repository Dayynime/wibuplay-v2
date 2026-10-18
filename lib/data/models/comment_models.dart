/// Baris tabel `episode_comments` (Supabase, dipakai bersama Zenime).
/// Komentar top-level dan balasan dibedakan lewat [parentId]
/// (null = top-level). Thread cuma 1 level.
class EpisodeComment {
  const EpisodeComment({
    required this.id,
    required this.episodeId,
    required this.animeId,
    required this.firebaseUid,
    required this.username,
    this.avatarUrl,
    required this.comment,
    this.parentId,
    this.replyToUsername,
    required this.createdAt,
    this.isPinned = false,
    this.replyCount = 0,
    this.animeTitle,
    this.animePosterUrl,
    this.episodeIndex,
  });

  final int id;
  final String episodeId;
  final String animeId;
  final String firebaseUid;
  final String username;
  final String? avatarUrl;
  final String comment;
  final int? parentId;

  /// Cuma terisi kalau balasan ini membalas BALASAN lain di thread yang sama.
  final String? replyToUsername;
  final String createdAt;

  /// Komentar yang disorot user Premium (tombol mahkota).
  final bool isPinned;
  final int replyCount;

  /// Snapshot anime saat komentar dikirim (dipakai tab Komentar di Profil).
  final String? animeTitle;
  final String? animePosterUrl;
  final String? episodeIndex;

  DateTime? get time => DateTime.tryParse(createdAt)?.toLocal();

  factory EpisodeComment.fromJson(Map<String, dynamic> j) {
    return EpisodeComment(
      id: (j['id'] as num?)?.toInt() ?? 0,
      episodeId: (j['episode_id'] as String?) ?? '',
      animeId: (j['anime_id'] as String?) ?? '',
      firebaseUid: (j['firebase_uid'] as String?) ?? '',
      username: (j['username'] as String?) ?? 'Pengguna',
      avatarUrl: j['avatar_url'] as String?,
      comment: (j['comment'] as String?) ?? '',
      parentId: (j['parent_id'] as num?)?.toInt(),
      replyToUsername: j['reply_to_username'] as String?,
      createdAt: (j['created_at'] as String?) ?? '',
      isPinned: (j['is_pinned'] as bool?) ?? false,
      replyCount: (j['reply_count'] as num?)?.toInt() ?? 0,
      animeTitle: j['anime_title'] as String?,
      animePosterUrl: j['anime_poster_url'] as String?,
      episodeIndex: j['episode_index']?.toString(),
    );
  }
}

/// Hasil getComments: sudah berbentuk pohon thread.
class CommentThreadResult {
  const CommentThreadResult({
    required this.topLevel,
    required this.repliesByParent,
    required this.totalCount,
  });

  final List<EpisodeComment> topLevel;
  final Map<int, List<EpisodeComment>> repliesByParent;
  final int totalCount;
}

/// Snapshot judul/poster/nomor episode yang ditempel ke tiap komentar baru
/// (dipakai tab "Komentar" di Profil Zenime).
class CommentMeta {
  const CommentMeta({this.animeTitle, this.animePosterUrl, this.episodeIndex});

  final String? animeTitle;
  final String? animePosterUrl;
  final String? episodeIndex;
}
