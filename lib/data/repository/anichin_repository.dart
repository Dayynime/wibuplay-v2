import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';

import '../api/anichin_network.dart';
import '../api/svelte_data.dart';
import '../models/anichin_models.dart';

/// Repository donghua yang membaca LANGSUNG situs v1.anichin.space, meniru
/// web anichin-web (anichin_scraper.py + app.py). Hasilnya dipetakan ke model
/// lama (AnichinCard, AnichinAnimeDetail, ...) supaya UI tidak berubah.
///
/// Endpoint sumber (GET, relatif ke AnichinNetwork.baseUrl):
///   api/trending                 api/search?q=
///   __data.json                  beranda (latestEpisodes, popularSeries)
///   ongoing|completed/__data.json?page=
///   series/__data.json?page=[&genre=]
///   genres/__data.json           schedule/__data.json
///   series/<slug>/__data.json    watch/<slug>/__data.json
class AnichinRepository {
  AnichinRepository(this._dio, {Dio? okruDio})
      : _okru = okruDio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
            ));

  final Dio _dio;
  final Dio _okru;

  // ------------------------------------------------------------------ cache

  static const Duration _ttlHome = Duration(minutes: 5);
  static const Duration _ttlList = Duration(minutes: 10);
  static const Duration _ttlGenres = Duration(days: 1);
  static const Duration _ttlSeries = Duration(minutes: 10);
  static const Duration _ttlWatch = Duration(minutes: 30);

  final Map<String, (DateTime, Object)> _cache = {};
  final Map<String, Future<Object>> _inflight = {};

  /// Cache memori per TTL. Kalau sumber gagal tapi ada data lama, pakai data lama.
  /// Request yang sama dan sedang berjalan digabung (misal player memanggil
  /// getEpisode + getVideoSource bersamaan -> cuma SATU download halaman watch).
  Future<T> _cached<T extends Object>(String key, Duration ttl, Future<T> Function() load) {
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < ttl) return Future.value(hit.$2 as T);
    final running = _inflight[key];
    if (running != null) return running.then((v) => v as T);
    final f = _load<T>(key, hit, load).whenComplete(() => _inflight.remove(key));
    _inflight[key] = f;
    return f;
  }

  Future<T> _load<T extends Object>(
    String key,
    (DateTime, Object)? hit,
    Future<T> Function() load,
  ) async {
    try {
      final value = await load();
      _cache[key] = (DateTime.now(), value);
      if (_cache.length > 300) _cache.remove(_cache.keys.first);
      return value;
    } catch (_) {
      if (hit != null) return hit.$2 as T;
      rethrow;
    }
  }

  // ------------------------------------------------------------------- HTTP

  static final RegExp _slugOk = RegExp(r'^[a-z0-9][a-z0-9-]*$');

  static String _slug(String s) {
    final v = s.trim();
    if (!_slugOk.hasMatch(v)) throw Exception('Slug tidak valid.');
    return v;
  }

  Future<String> _body(String path, Map<String, dynamic>? query) async {
    final res = await _dio.get<dynamic>(path, queryParameters: query);
    final data = res.data;
    if (data is! String || data.trim().isEmpty) {
      throw Exception('Respons server tidak dikenali.');
    }
    return data;
  }

  /// `<path>/__data.json` (path kosong = beranda).
  ///
  /// Parsing JSON halaman (bisa ratusan KB) jalan di isolate terpisah supaya
  /// UI / player tidak patah-patah. Redirect dari sumber diikuti sekali.
  Future<Map<String, dynamic>> _page(String path, {Map<String, dynamic>? query, int hops = 0}) async {
    final p = path.isEmpty ? '__data.json' : '$path/__data.json';
    final body = await _body(p, query);
    try {
      return await _parsePageInBackground(body);
    } on SvelteRedirect catch (r) {
      final next = _redirectPath(r.location);
      if (hops >= 2 || next == null) throw Exception('Halaman tidak ditemukan di sumber.');
      return _page(next, hops: hops + 1);
    } on FormatException {
      throw Exception(_looksLikeHtml(body)
          ? 'Sumber sedang sibuk / memblokir. Coba lagi sebentar.'
          : 'Respons server tidak dikenali.');
    }
  }

  /// Location redirect -> path relatif tanpa "/" depan & query (null kalau host lain).
  static String? _redirectPath(String location) {
    final base = Uri.parse(AnichinNetwork.baseUrl);
    final u = Uri.parse(base.toString()).resolve(location);
    if (u.host != base.host) return null;
    var path = u.path;
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static bool _looksLikeHtml(String body) {
    final head = body.trimLeft();
    return head.startsWith('<');
  }

  /// Endpoint JSON biasa (`api/search`, `api/trending`).
  Future<Object?> _api(String path, {Map<String, dynamic>? query}) async {
    final body = await _body(path, query);
    try {
      return await _decodeJsonInBackground(body);
    } on FormatException {
      throw Exception(_looksLikeHtml(body)
          ? 'Sumber sedang sibuk / memblokir. Coba lagi sebentar.'
          : 'Respons server tidak dikenali.');
    }
  }

  // --------------------------------------------------------------- endpoint

  Future<AnichinHomeResponse> getHome({int page = 1}) async {
    if (page > 1) {
      return AnichinHomeResponse(page: page, total: 1, source: AnichinNetwork.sourceBase);
    }
    return _cached('home', _ttlHome, () async {
      final home = await _page('');
      Object? trending;
      try {
        trending = await _api('api/trending');
      } catch (_) {
        trending = home['trendingSlider'];
      }
      final latest = <AnichinCard>[
        for (final e in _maps(home['latestEpisodes']))
          if (_card(e, eps: _int(e['latest_episode']), headline: _s(e['series'])) case final c?) c,
      ];
      return AnichinHomeResponse(
        results: [
          AnichinHomeSection(section: 'Rilis Terbaru', cards: latest),
          AnichinHomeSection(section: 'Trending', cards: _cards(trending)),
          AnichinHomeSection(section: 'Populer', cards: _cards(home['popularSeries'])),
        ],
        page: 1,
        total: 1,
        source: AnichinNetwork.sourceBase,
      );
    });
  }

  Future<AnichinListResponse> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return AnichinListResponse(query: q, source: AnichinNetwork.sourceBase);
    }
    final key = 'search:${q.toLowerCase()}';
    return _cached(key, _ttlList, () async {
      final raw = await _api('api/search', query: {'q': q.length > 100 ? q.substring(0, 100) : q});
      return AnichinListResponse(
        results: _cards(raw),
        query: q,
        source: AnichinNetwork.sourceBase,
      );
    });
  }

  /// Daftar berhalaman. `status: 'Ongoing'|'Completed'` memakai /ongoing atau
  /// /completed; tanpa status = /series (semua). `type` dan `order` tidak
  /// dipakai sumber, jadi diabaikan.
  Future<AnichinListResponse> getAnimeList({
    String? status,
    String? type,
    String? order,
    Map<String, String> extra = const {},
  }) {
    final n = int.tryParse(extra['page'] ?? '') ?? 1;
    final st = (status ?? '').toLowerCase();
    if (st == 'ongoing' || st == 'completed') {
      return _listPage('$st:$n', st, {'page': n}, '${st}Series');
    }
    return _listPage('all:$n', 'series', {'page': n}, 'seriesData');
  }

  Future<List<AnichinGenre>> getGenres() {
    return _cached('genres', _ttlGenres, () async {
      final data = await _page('genres');
      final seen = <String>{};
      return <AnichinGenre>[
        for (final o in _maps(data['dataList']))
          if (_s(o['key']) case final key? when seen.add(key))
            AnichinGenre(name: _unescape(_s(o['label']) ?? key), slug: key),
      ];
    });
  }

  Future<AnichinListResponse> getByGenre(String slug, {int page = 1}) async {
    final key = _slug(slug);
    return _listPage('genre:$key:$page', 'series', {'genre': key, 'page': page}, 'seriesData',
        slug: key);
  }

  Future<AnichinListResponse> _listPage(
    String cacheKey,
    String path,
    Map<String, dynamic> query,
    String listKey, {
    String? slug,
  }) {
    return _cached(cacheKey, _ttlList, () async {
      final data = await _page(path, query: query);
      return AnichinListResponse(
        results: _cards(data[listKey]),
        slug: slug,
        page: _int(data['currentPage']) ?? _int(query['page']) ?? 1,
        total: _int(data['totalPages']) ?? 1,
        source: AnichinNetwork.sourceBase,
      );
    });
  }

  /// Detail anime (slug anime, TANPA kata "episode").
  Future<AnichinAnimeDetail> getDetail(String slug) async {
    final key = _slug(slug);
    final data = await _cached('series:$key', _ttlSeries, () => _page('series/$key'));
    final a = data['anime'];
    if (a is! Map) throw Exception('Anime tidak ditemukan');
    final m = Map<String, dynamic>.from(a);
    final thumb = _img(m);
    return AnichinAnimeDetail(
      name: _s(m['title']) ?? 'Unknown',
      thumbnail: thumb,
      genres: _genreNames(m['genres']),
      rating: _sv(m['rating']),
      sinopsis: _paragraphs(m['description']).join('\n\n'),
      episodes: _episodeRefs(m['all_episodes'], thumb),
      info: _info(m),
    );
  }

  Future<AnichinEpisodeDetail> getEpisode(String slug) async {
    final m = await _episodeMap(slug);
    final anime = m['anime'] is Map ? Map<String, dynamic>.from(m['anime'] as Map) : <String, dynamic>{};
    final thumb = _img(anime) ?? _img(m);
    return AnichinEpisodeDetail(
      name: _s(m['title']) ?? 'Unknown',
      root: _s(anime['slug']),
      thumbnail: thumb,
      genres: _genreNames(anime['genres']),
      rating: _sv(anime['rating']),
      sinopsis: _paragraphs(anime['description'] ?? m['description']).join('\n\n'),
      episodes: _episodeRefs(anime['episodes'], thumb),
      players: _playable(m['videos']),
      info: _info(anime),
    );
  }

  Future<Map<String, dynamic>> _episodeMap(String slug) async {
    final key = _slug(slug);
    final data = await _cached('watch:$key', _ttlWatch, () => _page('watch/$key'));
    final e = data['episode'];
    if (e is! Map) throw Exception('Episode tidak ditemukan');
    return Map<String, dynamic>.from(e);
  }

  // ----------------------------------------------------------- link video

  static final RegExp _okruId = RegExp(r'/videoembed/(\d+)');
  static final RegExp _dmId = RegExp(r'(?:video[=/]|/video/)([a-zA-Z0-9]+)');

  /// Link video langsung untuk pemutar app. Urutan prioritas:
  /// 1. OK.ru  -> mp4 per kualitas (144p..1080p).
  /// 2. Link `.m3u8` langsung dari sumber -> HLS kualitas "auto".
  /// 3. Dailymotion -> HLS "auto" dari metadata player Dailymotion.
  /// Embed lain (halaman HTML) dilewati. Tidak di-cache: link video ada masa
  /// berlakunya.
  Future<AnichinVideoSource> getVideoSource(String slug) async {
    final ep = await _episodeMap(slug);
    final players = _playable(ep['videos']);
    String? hls;
    var medias = <AnichinMedia>[];

    for (final p in players) {
      if (medias.isNotEmpty) break;
      final id = _okruId.firstMatch(p.url)?.group(1);
      if (id == null) continue;
      try {
        final r = await _resolveOkru(id);
        medias = r.medias;
        hls ??= r.hls;
      } catch (_) {
        // mirror ini gagal -> coba yang lain
      }
    }

    if (medias.isEmpty) {
      for (final p in players) {
        if (p.url.split('?').first.endsWith('.m3u8')) {
          hls ??= p.url;
          medias = [AnichinMedia(quality: 'auto', url: p.url)];
          break;
        }
      }
    }

    if (medias.isEmpty) {
      for (final p in players) {
        if (!p.url.contains('dailymotion.com')) continue;
        final id = _dmId.firstMatch(p.url)?.group(1);
        if (id == null) continue;
        try {
          final url = await _resolveDailymotion(id);
          if (url != null) {
            hls ??= url;
            medias = [AnichinMedia(quality: 'auto', url: url)];
            break;
          }
        } catch (_) {
          // coba mirror berikutnya
        }
      }
    }

    if (medias.isEmpty) {
      // UI memakai 404 untuk pesan "episode ini belum punya video di sumber".
      final ro = RequestOptions(path: 'video-source/$slug');
      throw DioException(
        requestOptions: ro,
        response: Response<dynamic>(requestOptions: ro, statusCode: 404),
        type: DioExceptionType.badResponse,
        message: 'Video belum tersedia untuk episode ini.',
      );
    }
    return AnichinVideoSource(title: _s(ep['title']), hls: hls, medias: medias);
  }

  /// Metadata player Dailymotion -> URL HLS (m3u8) kualitas auto.
  Future<String?> _resolveDailymotion(String videoId) async {
    final res = await _okru.get<dynamic>(
      'https://www.dailymotion.com/player/metadata/video/$videoId',
      options: Options(headers: {'User-Agent': AnichinNetwork.userAgent}),
    );
    var data = res.data;
    if (data is String) data = jsonDecode(data);
    if (data is! Map) return null;
    final q = data['qualities'];
    if (q is! Map) return null;
    for (final key in ['auto', ...q.keys.map((k) => '$k')]) {
      for (final v in _maps(q[key])) {
        final url = _s(v['url']);
        if (url != null && '${v['type']}'.contains('mpegURL')) return url;
      }
    }
    return null;
  }

  Future<({List<AnichinMedia> medias, String? hls})> _resolveOkru(String videoId) async {
    final res = await _okru.post<dynamic>(
      'https://ok.ru/dk',
      data: {'cmd': 'videoPlayerMetadata', 'mid': videoId},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: AnichinNetwork.videoHeaders,
      ),
    );
    var data = res.data;
    if (data is String) data = jsonDecode(data);
    if (data is! Map) throw Exception('Metadata OK.ru tidak dikenali.');
    final medias = <AnichinMedia>[
      for (final v in _maps(data['videos']))
        if (_s(v['name']) != null && _s(v['url']) != null)
          AnichinMedia(quality: v['name'] as String, url: v['url'] as String),
    ]..sort((a, b) => qualityRank(a.quality).compareTo(qualityRank(b.quality)));
    return (medias: medias, hls: _s(data['hlsManifestUrl']));
  }

  // ---------------------------------------------------------------- kualitas

  /// "auto" = HLS adaptif (Dailymotion / m3u8 sumber), satu-satunya pilihan
  /// kalau OK.ru tidak ada.
  /// Urutan kualitas OK.ru dari terendah ke tertinggi:
  /// mobile=144p, lowest=240p, low=360p, sd=480p, hd=720p, full=1080p.
  static const List<String> qualityOrder = [
    'auto', 'mobile', 'lowest', 'low', 'sd', 'hd', 'full', 'quad', 'ultra',
  ];

  static const Map<String, String> _qualityLabels = {
    'auto': 'Auto',
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

// ============================ parsing di isolate =============================

/// Top-level (bukan method) supaya closure yang dikirim ke isolate cuma
/// membawa String body, bukan objek repository / Dio.
Future<Map<String, dynamic>> _parsePageInBackground(String body) =>
    Isolate.run(() => parsePageData(body));

Future<Object?> _decodeJsonInBackground(String body) => Isolate.run(() => jsonDecode(body));

// ======================= pemetaan data sumber -> model app ===================

String? _s(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

/// Nilai apa pun (angka/teks) -> String tidak kosong.
String? _sv(Object? v) => v == null ? null : _s(v.toString());

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt();
  return null;
}

Iterable<Map<String, dynamic>> _maps(Object? v) =>
    (v is List ? v : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m));

String? _img(Map<String, dynamic> m) {
  for (final k in const ['thumbnail', 'image', 'image_url', 'poster', 'cover']) {
    final v = m[k];
    if (v is String && v.startsWith('http')) return v;
  }
  return null;
}

AnichinCard? _card(Map<String, dynamic> m, {int? eps, String? headline}) {
  final slug = _s(m['slug']);
  if (slug == null) return null;
  return AnichinCard(
    title: _s(m['title']) ?? _s(m['series']),
    type: _s(m['type']),
    headline: headline ?? _s(m['series']),
    eps: eps,
    status: _s(m['status']),
    thumbnail: _img(m),
    slug: slug,
  );
}

List<AnichinCard> _cards(Object? items) {
  final seen = <String>{};
  return [
    for (final m in _maps(items))
      if (_card(m) case final c? when seen.add(c.slug!)) c,
  ];
}

List<String> _genreNames(Object? genres) {
  final out = <String>[];
  for (final g in (genres is List ? genres : const [])) {
    final name = g is Map ? (_s(g['name']) ?? _s(g['label'])) : _s(g);
    if (name != null) out.add(_unescape(name.trim()));
  }
  return out;
}

List<AnichinEpisodeRef> _episodeRefs(Object? episodes, String? fallbackThumb) {
  final seen = <String>{};
  final out = <AnichinEpisodeRef>[];
  for (final e in _maps(episodes)) {
    final slug = _s(e['slug']);
    if (slug == null || !seen.add(slug)) continue;
    out.add(AnichinEpisodeRef(
      slug: slug,
      name: _s(e['title']),
      episode: e['episode']?.toString(),
      date: _s(e['publish_date']) ?? _s(e['date']),
      thumbnail: _img(e) ?? fallbackThumb,
    ));
  }
  return out;
}

/// Field tambahan layar detail (key lowercase_underscore, sama dengan daftar
/// `_preferredInfo` di donghua_detail_screen.dart).
Map<String, String> _info(Map<String, dynamic> a) {
  final info = <String, String>{};
  void put(String key, Object? val) {
    final v = val is List ? val.where((x) => x != null).join(', ') : val;
    if (v is String && v.trim().isNotEmpty) info[key] = v.trim();
  }

  put('status', a['status']);
  put('type', a['type']);
  put('studio', a['studio']);
  put('durasi', a['duration']);
  put('network', a['network']);
  final season = a['season'];
  put('season', season is List && season.isNotEmpty ? season.first : season);
  put('tanggal_rilis', a['release_date']);
  return info;
}

/// Embed yang boleh diteruskan (whitelist yang sama dengan app.py).
const Set<String> _embedHosts = {
  'rmb.anichin.bio',
  'geo.dailymotion.com',
  'www.dailymotion.com',
  'ok.ru',
};

List<AnichinPlayer> _playable(Object? videos) {
  final out = <AnichinPlayer>[];
  for (final v in _maps(videos)) {
    final embed = _s(v['embed']) ?? '';
    final u = Uri.tryParse(embed);
    if (u == null || u.scheme != 'https' || !_embedHosts.contains(u.host)) continue;
    if (embed.endsWith('#') || embed.endsWith('/videoembed/')) continue; // OK.ru kosong
    out.add(AnichinPlayer(name: _s(v['host_name']) ?? u.host, url: embed));
  }
  // VIP (HLS sumber) biasanya paling stabil -> paling depan (sort stabil).
  final vip = out.where((p) => p.name.toLowerCase() == 'vip').toList();
  return [...vip, ...out.where((p) => p.name.toLowerCase() != 'vip')];
}

// ------------------------------------------------------------- HTML -> teks

final RegExp _breaks = RegExp(r'</p>|<br\s*/?>', caseSensitive: false);
final RegExp _tags = RegExp(r'<[^>]+>');
final RegExp _spaces = RegExp(r'\s+');

/// HTML sumber -> daftar paragraf teks biasa (tidak pernah dirender sebagai HTML).
List<String> _paragraphs(Object? html) {
  final raw = (html ?? '').toString().replaceAll(_breaks, '\n').replaceAll(_tags, ' ');
  return [
    for (final line in _unescape(raw).split('\n'))
      if (line.replaceAll(_spaces, ' ').trim().isNotEmpty) line.replaceAll(_spaces, ' ').trim(),
  ];
}

final RegExp _entity = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

String _unescape(String s) {
  const named = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '};
  return s.replaceAllMapped(_entity, (m) {
    final e = m.group(1)!;
    if (e.startsWith('#')) {
      final hex = e.startsWith('#x') || e.startsWith('#X');
      final code = int.tryParse(e.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    }
    return named[e] ?? m.group(0)!;
  });
}
