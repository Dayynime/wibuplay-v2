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

/// Port DownloadedEpisodeEntity (tabel `downloaded_episodes` di Room Zenime).
///
/// Data download episode (offline, khusus Premium). Berisi download dari Wibuplay
/// sendiri dan hasil migrasi Room Zenime. File videonya ada di
/// `getExternalFilesDir(MOVIES)/<animeId>/<episodeId>.mp4` (app-private).
class DownloadedEpisodeEntity {
  const DownloadedEpisodeEntity({
    required this.episodeId,
    required this.animeId,
    required this.animeTitle,
    this.posterUrl,
    this.episodeTitle,
    this.episodeIndex,
    this.quality,
    this.localFilePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = 'QUEUED',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.episodeThumbnailUrl,
    this.workRequestId,
  });

  final String episodeId;
  final String animeId;
  final String animeTitle;
  final String? posterUrl;
  final String? episodeTitle;
  final String? episodeIndex;
  final String? quality;
  final String? localFilePath;
  final int totalBytes;
  final int downloadedBytes;

  /// QUEUED / DOWNLOADING / COMPLETED / FAILED (sama dengan DownloadStatus Zenime).
  final String status;
  final int createdAt;
  final int updatedAt;
  final String? episodeThumbnailUrl;

  /// ID DownloadManager sistem Android (disimpan sebagai string, sama dengan Zenime).
  final String? workRequestId;

  bool get isCompleted => status == 'COMPLETED';
  bool get isActive => status == 'QUEUED' || status == 'DOWNLOADING';

  DownloadedEpisodeEntity copyWith({
    int? totalBytes,
    int? downloadedBytes,
    String? status,
    int? updatedAt,
  }) =>
      DownloadedEpisodeEntity(
        episodeId: episodeId,
        animeId: animeId,
        animeTitle: animeTitle,
        posterUrl: posterUrl,
        episodeTitle: episodeTitle,
        episodeIndex: episodeIndex,
        quality: quality,
        localFilePath: localFilePath,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        episodeThumbnailUrl: episodeThumbnailUrl,
        workRequestId: workRequestId,
      );

  Map<String, dynamic> toJson() => {
        'episodeId': episodeId,
        'animeId': animeId,
        'animeTitle': animeTitle,
        'posterUrl': posterUrl,
        'episodeTitle': episodeTitle,
        'episodeIndex': episodeIndex,
        'quality': quality,
        'localFilePath': localFilePath,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'status': status,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'episodeThumbnailUrl': episodeThumbnailUrl,
        'workRequestId': workRequestId,
      };

  factory DownloadedEpisodeEntity.fromJson(Map<String, dynamic> j) =>
      DownloadedEpisodeEntity(
        episodeId: (j['episodeId'] as String?) ?? '',
        animeId: (j['animeId'] as String?) ?? '',
        animeTitle: (j['animeTitle'] as String?) ?? '',
        posterUrl: j['posterUrl'] as String?,
        episodeTitle: j['episodeTitle'] as String?,
        episodeIndex: j['episodeIndex'] as String?,
        quality: j['quality'] as String?,
        localFilePath: j['localFilePath'] as String?,
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
        downloadedBytes: (j['downloadedBytes'] as num?)?.toInt() ?? 0,
        status: (j['status'] as String?) ?? 'QUEUED',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        episodeThumbnailUrl: j['episodeThumbnailUrl'] as String?,
        workRequestId: j['workRequestId']?.toString(),
      );
}
