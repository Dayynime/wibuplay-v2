import 'dart:convert';

import '../data/models/anime_item.dart';
import '../data/models/cuplix_item.dart';
import '../data/models/episode_item.dart';
import '../data/models/genre_item.dart';
import '../data/models/media_item.dart';
import '../data/models/stream_data.dart';

/// Envelope response: { "status": int?, "error": bool?, "data": dynamic }.
class ApiResponse {
  const ApiResponse({this.status, this.error, this.data});

  final int? status;
  final bool? error;
  final dynamic data;
}

/// Port JsonHelper.kt. Semua helper menerima dynamic dan toleran terhadap
/// bentuk data server yang tidak konsisten.
class JsonHelper {
  JsonHelper._();

  static String? _str(dynamic v) => v?.toString();

  /// Nilai string pertama yang tidak null dari daftar key (setara `a ?: b ?: c`).
  static String? _first(Map map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v != null) return v.toString();
    }
    return null;
  }

  /// `data` bisa List langsung, atau Map yang membungkus list di salah satu key.
  /// Key pertama yang non-null dipakai; kalau bukan List hasilnya kosong.
  static List<dynamic> _extractList(dynamic data, List<String> keys) {
    if (data == null) return const [];
    if (data is List) return data;
    if (data is Map) {
      dynamic found;
      for (final k in keys) {
        final v = data[k];
        if (v != null) {
          found = v;
          break;
        }
      }
      return found is List ? found : const [];
    }
    return const [];
  }

  /// Decode body mentah (String JSON atau sudah berupa Map) menjadi envelope.
  /// Melempar [FormatException] kalau bukan objek JSON.
  static ApiResponse decodeEnvelope(dynamic body) {
    dynamic decoded = body;
    if (body is String) {
      if (body.trim().isEmpty) {
        throw const FormatException('Response kosong');
      }
      decoded = jsonDecode(body);
    }
    if (decoded is! Map) {
      throw const FormatException('Envelope response bukan objek JSON');
    }
    final status = decoded['status'];
    final error = decoded['error'];
    return ApiResponse(
      status: status is num ? status.toInt() : null,
      error: error is bool ? error : null,
      data: decoded['data'],
    );
  }

  // ---- Anime ----

  static AnimeItem? parseAnimeItem(Map? map) {
    if (map == null) return null;
    try {
      return AnimeItem(
        id: _str(map['id']),
        title: _first(map, ['title', 'anime']),
        synopsis: _str(map['synopsis']),
        genre: _str(map['genre']),
        status: _str(map['status']),
        type: _str(map['type']),
        year: _str(map['year']),
        day: _str(map['day']),
        views: _first(map, ['views', 'count_views']),
        imagePoster: _first(map, ['image_poster', 'poster', 'image']),
        imageCover: _first(map, ['image_cover', 'cover']),
        studio: _str(map['studio']),
        airedStart: _str(map['aired_start']),
        airedEnd: _str(map['aired_end']),
      );
    } catch (_) {
      return null;
    }
  }

  static List<AnimeItem> parseAnimeList(dynamic data) {
    final list = _extractList(data, ['movie', 'movies', 'data']);
    return list
        .whereType<Map>()
        .map(parseAnimeItem)
        .whereType<AnimeItem>()
        .toList();
  }

  // ---- Genre ----

  static List<GenreItem> parseGenreList(dynamic data) {
    final list = _extractList(data, ['genre', 'genres', 'data']);
    return [
      for (final item in list)
        if (item is Map)
          GenreItem(
            id: _str(item['id']),
            name: _first(item, ['name', 'title']),
            total: _str(item['total']),
          ),
    ];
  }

  // ---- Episode ----

  static EpisodeItem? parseEpisodeItem(Map? map) {
    if (map == null) return null;
    try {
      return EpisodeItem(
        id: _str(map['id']),
        index: _first(map, ['index', 'episode']),
        image: _first(map, ['image', 'thumbnail']),
        title: _str(map['title']) ??
            'Episode ${map['index'] ?? map['episode'] ?? ''}',
        views: _str(map['views']),
        isNew: map['is_new'],
      );
    } catch (_) {
      return null;
    }
  }

  static List<EpisodeItem> parseEpisodeList(dynamic data) {
    final list = _extractList(data, ['episode', 'episodes', 'data']);
    return list
        .whereType<Map>()
        .map(parseEpisodeItem)
        .whereType<EpisodeItem>()
        .toList();
  }

  // ---- Stream ----

  static StreamData parseStreamData(dynamic data) {
    if (data is! Map) return const StreamData();

    final episodeRaw = data['episode'];
    final episode = episodeRaw is Map ? parseEpisodeItem(episodeRaw) : null;

    final nextRaw = data['episode_next'];
    EpisodeItem? nextEpisode;
    bool hasNext;
    if (nextRaw is Map) {
      nextEpisode = parseEpisodeItem(nextRaw);
      hasNext = true;
    } else if (nextRaw is bool) {
      hasNext = nextRaw;
    } else {
      hasNext = false;
    }

    final serversRaw = data['server'];
    final servers = serversRaw is List
        ? [
            for (final s in serversRaw)
              if (s is Map)
                StreamServer(
                  link: _str(s['link']),
                  quality: _str(s['quality']),
                  type: _str(s['type']),
                  name: _first(s, ['name', 'title']),
                ),
          ]
        : const <StreamServer>[];

    return StreamData(
      episode: episode,
      episodeNext: nextEpisode,
      hasNextEpisode: hasNext,
      server: servers,
    );
  }

  // ---- Cuplix ----

  /// Item tanpa `id` (null) dilewati. Id string kosong tetap lolos,
  /// sama seperti versi Kotlin (hanya null yang dilewati).
  static List<CuplixItem> parseCuplixList(dynamic data) {
    final list = _extractList(data, ['list', 'fyp', 'data']);
    final result = <CuplixItem>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = _str(item['id']);
      if (id == null) continue;
      result.add(CuplixItem(
        id: id,
        caption: _str(item['caption']),
        urlThumbnail: _first(item, ['url_thumbnail', 'thumbnail']),
        idEpisode: _str(item['id_episode']),
        idMovie: _str(item['id_movie']),
        anime: _str(item['anime']),
        episode: _str(item['episode']),
        timeStart: _str(item['time_start']),
        timeEnd: _str(item['time_end']),
        countViews: _first(item, ['count_views', 'views']),
        countLikes: _first(item, ['count_likes', 'likes']),
        countComments: _first(item, ['count_comments', 'comments']),
        username: _str(item['username']),
      ));
    }
    return result;
  }

  // ---- Media (cover/poster) ----

  static List<MediaGalleryItem> parseMediaList(dynamic data) {
    final list = _extractList(data, ['data', 'list', 'poster', 'cover']);
    return [
      for (final item in list)
        if (item is Map)
          MediaGalleryItem(
            id: _str(item['id']),
            image: _first(item, ['image', 'url', 'cover']),
            title: _str(item['title']),
          ),
    ];
  }

  // ---- Kursor cuplix ----

  /// Double bulat dijadikan integer string (77.0 -> "77"); selainnya toString().
  static String sanitizeCursorValue(dynamic value) {
    if (value == null) return '';
    if (value is double) {
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    return value.toString();
  }

  /// Ambil semua key berawalan `cursor_` dari `data` (Map).
  static Map<String, String> extractCursors(dynamic data) {
    if (data is! Map) return const {};
    final cursors = <String, String>{};
    data.forEach((k, v) {
      final key = k?.toString();
      if (key != null && key.startsWith('cursor_')) {
        cursors[key] = sanitizeCursorValue(v);
      }
    });
    return cursors;
  }
}
