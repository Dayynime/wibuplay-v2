import '../models/anime_item.dart';

/// Port FavoriteEntity (tabel `favorites`).
class FavoriteEntity {
  const FavoriteEntity({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.coverUrl,
    this.synopsis,
    this.genre,
    this.status,
    this.type,
    this.views,
    required this.timestamp,
  });

  final String id;
  final String title;
  final String posterUrl;
  final String coverUrl;
  final String? synopsis;
  final String? genre;
  final String? status;
  final String? type;
  final String? views;
  final int timestamp;

  AnimeItem toAnimeItem() => AnimeItem(
        id: id,
        title: title,
        synopsis: synopsis,
        genre: genre,
        status: status,
        type: type,
        views: views,
        imagePoster: posterUrl,
        imageCover: coverUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'posterUrl': posterUrl,
        'coverUrl': coverUrl,
        'synopsis': synopsis,
        'genre': genre,
        'status': status,
        'type': type,
        'views': views,
        'timestamp': timestamp,
      };

  factory FavoriteEntity.fromJson(Map<String, dynamic> j) => FavoriteEntity(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        posterUrl: (j['posterUrl'] as String?) ?? '',
        coverUrl: (j['coverUrl'] as String?) ?? '',
        synopsis: j['synopsis'] as String?,
        genre: j['genre'] as String?,
        status: j['status'] as String?,
        type: j['type'] as String?,
        views: j['views'] as String?,
        timestamp: (j['timestamp'] as num?)?.toInt() ?? 0,
      );
}

/// Port WatchHistoryEntity (tabel `watch_history`).
/// id = "${movieId}_${episodeId}".
class WatchHistoryEntity {
  const WatchHistoryEntity({
    required this.id,
    required this.movieId,
    required this.movieTitle,
    required this.moviePoster,
    required this.episodeId,
    required this.episodeIndex,
    required this.episodeTitle,
    required this.playbackPositionMs,
    required this.durationMs,
    required this.lastWatchedTime,
  });

  final String id;
  final String movieId;
  final String movieTitle;
  final String moviePoster;
  final String episodeId;
  final String episodeIndex;
  final String episodeTitle;
  final int playbackPositionMs;
  final int durationMs;
  final int lastWatchedTime;

  double get progressFraction => durationMs > 0
      ? (playbackPositionMs / durationMs).clamp(0.0, 1.0).toDouble()
      : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'movieId': movieId,
        'movieTitle': movieTitle,
        'moviePoster': moviePoster,
        'episodeId': episodeId,
        'episodeIndex': episodeIndex,
        'episodeTitle': episodeTitle,
        'playbackPositionMs': playbackPositionMs,
        'durationMs': durationMs,
        'lastWatchedTime': lastWatchedTime,
      };

  factory WatchHistoryEntity.fromJson(Map<String, dynamic> j) => WatchHistoryEntity(
        id: j['id'] as String,
        movieId: (j['movieId'] as String?) ?? '',
        movieTitle: (j['movieTitle'] as String?) ?? '',
        moviePoster: (j['moviePoster'] as String?) ?? '',
        episodeId: (j['episodeId'] as String?) ?? '',
        episodeIndex: (j['episodeIndex'] as String?) ?? '',
        episodeTitle: (j['episodeTitle'] as String?) ?? '',
        playbackPositionMs: (j['playbackPositionMs'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        lastWatchedTime: (j['lastWatchedTime'] as num?)?.toInt() ?? 0,
      );
}
