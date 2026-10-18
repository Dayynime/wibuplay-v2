import 'dart:math' as math;

import '../local/entities.dart';

/// Satu baris `user_favorites` milik user lain (GET langsung, dijaga RLS).
class PublicFavoriteRow {
  const PublicFavoriteRow({
    required this.animeId,
    required this.title,
    this.posterUrl,
    this.type,
    this.status,
  });

  final String animeId;
  final String title;
  final String? posterUrl;
  final String? type;
  final String? status;

  factory PublicFavoriteRow.fromJson(Map<String, dynamic> j) => PublicFavoriteRow(
        animeId: (j['anime_id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        posterUrl: j['poster_url'] as String?,
        type: j['type'] as String?,
        status: j['status'] as String?,
      );

  /// Dipetakan ke entity lokal supaya komponen list Profil Saya bisa dipakai ulang.
  FavoriteEntity toEntity() => FavoriteEntity(
        id: animeId,
        title: title,
        posterUrl: posterUrl ?? '',
        coverUrl: posterUrl ?? '',
        status: status,
        type: type,
        timestamp: 0,
      );
}

/// Satu baris `user_watch_history` milik user lain (GET langsung, dijaga RLS).
class PublicHistoryRow {
  const PublicHistoryRow({
    required this.animeId,
    required this.animeTitle,
    this.posterUrl,
    required this.episodeId,
    this.episodeTitle,
    this.episodeIndex,
    this.progressMs = 0,
    this.durationMs = 0,
    this.lastUpdated,
  });

  final String animeId;
  final String animeTitle;
  final String? posterUrl;
  final String episodeId;
  final String? episodeTitle;
  final String? episodeIndex;
  final int progressMs;
  final int durationMs;
  final String? lastUpdated;

  factory PublicHistoryRow.fromJson(Map<String, dynamic> j) => PublicHistoryRow(
        animeId: (j['anime_id'] as String?) ?? '',
        animeTitle: (j['anime_title'] as String?) ?? '',
        posterUrl: j['poster_url'] as String?,
        episodeId: (j['episode_id'] as String?) ?? '',
        episodeTitle: j['episode_title'] as String?,
        episodeIndex: j['episode_index']?.toString(),
        progressMs: (j['progress_ms'] as num?)?.toInt() ?? 0,
        durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        lastUpdated: j['last_updated'] as String?,
      );

  WatchHistoryEntity toEntity() => WatchHistoryEntity(
        id: '${animeId}_$episodeId',
        movieId: animeId,
        movieTitle: animeTitle,
        moviePoster: posterUrl ?? '',
        episodeId: episodeId,
        episodeIndex: episodeIndex ?? '',
        episodeTitle: episodeTitle ?? '',
        playbackPositionMs: math.max(0, progressMs),
        durationMs: math.max(0, durationMs),
        lastWatchedTime:
            DateTime.tryParse(lastUpdated ?? '')?.millisecondsSinceEpoch ?? 0,
      );
}

/// Hasil gabungan toggle privasi + favorit/riwayat user lain.
///
/// `favorites`/`history` == null artinya PRIVAT (toggle dia mati) -- beda dengan
/// list kosong yang artinya publik tapi memang belum ada isinya.
class PublicProfileContent {
  const PublicProfileContent({
    this.favoritesPublic = false,
    this.historyPublic = false,
    this.favorites,
    this.history,
  });

  final bool favoritesPublic;
  final bool historyPublic;
  final List<PublicFavoriteRow>? favorites;
  final List<PublicHistoryRow>? history;
}
