import 'dart:convert';

import 'package:dio/dio.dart';

import '../api/anichin_network.dart';
import '../models/anichin_models.dart';

/// Port AnichinRepository.kt. Method melempar exception kalau gagal
/// (setara Result.Error); pemanggil yang menangkapnya.
class AnichinRepository {
  AnichinRepository(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> _getMap(String path, {Map<String, dynamic>? query}) async {
    final res = await _dio.get<dynamic>(path, queryParameters: query);
    var data = res.data;
    if (data is String) data = data.trim().isEmpty ? null : jsonDecode(data);
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('Respons server tidak dikenali.');
  }

  static String _enc(String s) => Uri.encodeComponent(s);

  Future<AnichinHomeResponse> getHome({int page = 1}) async {
    final res = AnichinHomeResponse.fromJson(
      await _getMap('', query: page > 1 ? {'page': page} : null),
    );
    AnichinNetwork.updateSourceBase(res.source);
    return _throwIfError(res, res.error);
  }

  Future<AnichinListResponse> search(String query) async {
    // "/" di path kena 404 di server, jadi diganti spasi.
    final q = query.trim().replaceAll('/', ' ');
    final res = AnichinListResponse.fromJson(await _getMap('search/${_enc(q)}'));
    AnichinNetwork.updateSourceBase(res.source);
    return _throwIfError(res, res.error);
  }

  /// Daftar dengan filter bebas (status, type, order, dll), mis.
  /// `status: 'Ongoing', order: 'update'`.
  Future<AnichinListResponse> getAnimeList({
    String? status,
    String? type,
    String? order,
    Map<String, String> extra = const {},
  }) async {
    final params = <String, dynamic>{
      if (status != null) 'status': status,
      if (type != null) 'type': type,
      if (order != null) 'order': order,
      ...extra,
    };
    final res = AnichinListResponse.fromJson(
      await _getMap('anime', query: params.isEmpty ? null : params),
    );
    AnichinNetwork.updateSourceBase(res.source);
    return _throwIfError(res, res.error);
  }

  Future<List<AnichinGenre>> getGenres() async {
    final map = await _getMap('genres');
    _throwIfError(map, _str(map, 'error'));
    final list = (map['genres'] is List ? map['genres'] as List : const [])
        .whereType<Map>()
        .map((m) => AnichinGenre.fromJson(Map<String, dynamic>.from(m)));
    // Server kadang mengirim daftar genre kedobel.
    final seen = <String?>{};
    return list.where((g) => seen.add(g.slug)).toList();
  }

  Future<AnichinListResponse> getByGenre(String slug, {int page = 1}) async {
    final res = AnichinListResponse.fromJson(
      await _getMap('genre/${_enc(slug)}', query: page > 1 ? {'page': page} : null),
    );
    AnichinNetwork.updateSourceBase(res.source);
    return _throwIfError(res, res.error);
  }

  /// Detail anime (slug anime, TANPA kata "episode").
  Future<AnichinAnimeDetail> getDetail(String slug) async {
    final env = await _getMap(_enc(slug));
    AnichinNetwork.updateSourceBase(_str(env, 'source'));
    final map = env['result'];
    if (map is! Map) {
      throw Exception(_str(env, 'error') ?? 'Anime tidak ditemukan');
    }
    final m = Map<String, dynamic>.from(map);
    return AnichinAnimeDetail(
      name: _str(m, 'name') ?? 'Unknown',
      thumbnail: _str(m, 'thumbnail'),
      genres: _strList(m, 'genre'),
      rating: _str(m, 'rating'),
      sinopsis: _sinopsis(m),
      episodes: _episodes(m),
      info: _info(m, _detailKeys),
    );
  }

  Future<AnichinEpisodeDetail> getEpisode(String slug) async {
    final env = await _getMap('episode/${_enc(slug)}');
    AnichinNetwork.updateSourceBase(_str(env, 'source'));
    final map = env['result'];
    if (map is! Map) {
      throw Exception(_str(env, 'error') ?? 'Episode tidak ditemukan');
    }
    final m = Map<String, dynamic>.from(map);
    final root = _str(m, 'root');
    return AnichinEpisodeDetail(
      name: _str(m, 'name') ?? 'Unknown',
      root: root == 'unknown' ? null : root,
      thumbnail: _str(m, 'thumbnail'),
      genres: _strList(m, 'genre'),
      rating: _str(m, 'rating'),
      sinopsis: _sinopsis(m),
      episodes: _episodes(m),
      players: _players(m),
      info: _info(m, _episodeKeys),
    );
  }

  /// Link video langsung. Panggil fresh tiap mau nonton (link ada masa
  /// berlakunya). Pilih dari [AnichinVideoSource.medias], putar dengan header
  /// [AnichinNetwork.videoHeaders].
  Future<AnichinVideoSource> getVideoSource(String slug) async {
    return AnichinVideoSource.fromJson(await _getMap('video-source/${_enc(slug)}'));
  }

  // ---------------------------------------------------------------- kualitas

  static const Set<String> _detailKeys = {
    'name', 'thumbnail', 'genre', 'rating', 'sinopsis', 'episode',
  };
  static const Set<String> _episodeKeys = {..._detailKeys, 'players', 'root'};

  /// Urutan kualitas OK.ru dari terendah ke tertinggi:
  /// mobile=144p, lowest=240p, low=360p, sd=480p, hd=720p, full=1080p.
  static const List<String> qualityOrder = [
    'mobile', 'lowest', 'low', 'sd', 'hd', 'full', 'quad', 'ultra',
  ];

  static const Map<String, String> _qualityLabels = {
    'mobile': '144p',
    'lowest': '240p',
    'low': '360p',
    'sd': '480p',
    'hd': '720p',
    'full': '1080p',
    'quad': '1440p',
    'ultra': '2160p',
  };

  static int qualityRank(String? quality) =>
      qualityOrder.indexOf((quality ?? '').toLowerCase());

  static String qualityLabel(String? quality) {
    final q = (quality ?? '').toLowerCase();
    final label = _qualityLabels[q];
    if (label != null) return label;
    return (quality ?? '').isEmpty ? 'Auto' : quality!;
  }

  /// Non-premium maksimal 480p = "sd".
  static const String nonPremiumMaxQuality = 'sd';

  /// Pilih media mp4 dengan kualitas tertinggi yang masih <= [maxQuality].
  /// Non-premium (max 480p) -> maxQuality = [nonPremiumMaxQuality].
  static AnichinMedia? pickMedia(List<AnichinMedia> medias, {String maxQuality = 'ultra'}) {
    final r = qualityRank(maxQuality);
    final limit = r < 0 ? qualityOrder.length - 1 : r;
    AnichinMedia? best;
    for (final m in medias) {
      if ((m.url ?? '').trim().isEmpty) continue;
      final rank = qualityRank(m.quality);
      if (rank < 0 || rank > limit) continue;
      if (best == null || rank > qualityRank(best.quality)) best = m;
    }
    return best;
  }
}

// ---------- helper parsing Map dinamis ----------

T _throwIfError<T>(T value, String? error) {
  if (error != null && error.isNotEmpty) throw Exception(error);
  return value;
}

String? _str(Map<String, dynamic> m, String key) {
  final v = m[key];
  return v is String && v.trim().isNotEmpty ? v : null;
}

List<String> _strList(Map<String, dynamic> m, String key) {
  final v = m[key];
  return v is List ? v.whereType<String>().toList() : const [];
}

/// "sinopsis" bisa string (halaman episode) atau {paragraphs:[..], title:".."}
/// (halaman detail).
String _sinopsis(Map<String, dynamic> m) {
  final s = m['sinopsis'];
  if (s is String) return s;
  if (s is Map) {
    final p = s['paragraphs'];
    if (p is List) {
      return p.whereType<String>().where((e) => e.trim().isNotEmpty).join('\n\n');
    }
  }
  return '';
}

List<AnichinEpisodeRef> _episodes(Map<String, dynamic> m) {
  final list = m['episode'];
  if (list is! List) return const [];
  final seen = <String>{};
  final out = <AnichinEpisodeRef>[];
  for (final item in list) {
    if (item is! Map) continue;
    final slug = item['slug'];
    if (slug is! String || !seen.add(slug)) continue;
    out.add(AnichinEpisodeRef(
      slug: slug,
      name: item['name'] is String ? item['name'] as String : null,
      subtitle: item['subtitle'] is String ? item['subtitle'] as String : null,
      date: item['date'] is String ? item['date'] as String : null,
      episode: item['episode']?.toString(),
      thumbnail: item['thumbnail'] is String ? item['thumbnail'] as String : null,
    ));
  }
  return out;
}

/// "players" berisi list {name,url}, atau {"error": "..."} kalau gagal.
List<AnichinPlayer> _players(Map<String, dynamic> m) {
  final list = m['players'];
  if (list is! List) return const [];
  final out = <AnichinPlayer>[];
  for (final item in list) {
    if (item is! Map || item['url'] is! String) continue;
    out.add(AnichinPlayer(
      name: item['name'] is String ? item['name'] as String : '',
      url: item['url'] as String,
    ));
  }
  return out;
}

Map<String, String> _info(Map<String, dynamic> m, Set<String> exclude) {
  final out = <String, String>{};
  m.forEach((k, v) {
    if (exclude.contains(k)) return;
    if (v is String && v.trim().isNotEmpty) out[k] = v;
  });
  return out;
}
