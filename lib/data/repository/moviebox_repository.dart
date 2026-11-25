import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/remote_config_manager.dart';
import '../api/moviebox_network.dart';
import '../models/moviebox_models.dart';

/// Urutan daftar film.
enum MbSort {
  recommend('populer', 'Populer'),
  latest('latest', 'Terbaru');

  const MbSort(this.value, this.label);

  /// Path halaman daftar di LK21 (/populer, /latest).
  final String value;
  final String label;
}

/// Kategori daftar film LK21 (path halaman daftar, tanpa /page/N).
class MbCategory {
  const MbCategory(this.path, this.label);

  /// Mis. 'populer', 'latest', 'genre/action', 'country/japan', 'year/2026'.
  final String path;
  final String label;

  static const populer = MbCategory('populer', 'Populer');
  static const latest = MbCategory('latest', 'Terbaru');

  /// Pilihan cepat di baris atas layar Film.
  static const quick = <MbCategory>[
    populer,
    latest,
    MbCategory('genre/action', 'Action'),
    MbCategory('genre/animation', 'Anime'),
    MbCategory('genre/horror', 'Horror'),
    MbCategory('genre/comedy', 'Komedi'),
    MbCategory('genre/sci-fi', 'Sci-Fi'),
    MbCategory('genre/romance', 'Romance'),
    MbCategory('country/china', 'Cina'),
    MbCategory('country/india', 'India'),
    MbCategory('country/japan', 'Jepang'),
    MbCategory('country/south-korea', 'Korea'),
    MbCategory('country/thailand', 'Thailand'),
    MbCategory('quality/bluray', 'Bluray'),
    MbCategory('year/2026', '2026'),
    MbCategory('year/2025', '2025'),
  ];

  static const genres = <MbCategory>[
    MbCategory('genre/action', 'Action'),
    MbCategory('genre/adventure', 'Adventure'),
    MbCategory('genre/animation', 'Anime'),
    MbCategory('genre/biography', 'Biografi'),
    MbCategory('genre/comedy', 'Komedi'),
    MbCategory('genre/crime', 'Kriminal'),
    MbCategory('genre/documentary', 'Dokumenter'),
    MbCategory('genre/drama', 'Drama'),
    MbCategory('genre/family', 'Keluarga'),
    MbCategory('genre/fantasy', 'Fantasi'),
    MbCategory('genre/history', 'Sejarah'),
    MbCategory('genre/horror', 'Horror'),
    MbCategory('genre/musical', 'Musikal'),
    MbCategory('genre/mystery', 'Misteri'),
    MbCategory('genre/romance', 'Romance'),
    MbCategory('genre/sci-fi', 'Sci-Fi'),
    MbCategory('genre/sport', 'Olahraga'),
    MbCategory('genre/thriller', 'Thriller'),
    MbCategory('genre/war', 'Perang'),
    MbCategory('genre/western', 'Western'),
  ];

  static const countries = <MbCategory>[
    MbCategory('country/australia', 'Australia'),
    MbCategory('country/canada', 'Kanada'),
    MbCategory('country/china', 'Cina'),
    MbCategory('country/france', 'Prancis'),
    MbCategory('country/germany', 'Jerman'),
    MbCategory('country/hong-kong', 'Hong Kong'),
    MbCategory('country/india', 'India'),
    MbCategory('country/italy', 'Italia'),
    MbCategory('country/japan', 'Jepang'),
    MbCategory('country/malaysia', 'Malaysia'),
    MbCategory('country/mexico', 'Meksiko'),
    MbCategory('country/philippines', 'Filipina'),
    MbCategory('country/romania', 'Rumania'),
    MbCategory('country/russia', 'Rusia'),
    MbCategory('country/south-korea', 'Korea'),
    MbCategory('country/taiwan', 'Taiwan'),
    MbCategory('country/thailand', 'Thailand'),
    MbCategory('country/uk', 'Inggris'),
    MbCategory('country/usa', 'Amerika'),
  ];

  static final years = <MbCategory>[
    for (var y = 2026; y >= 2007; y--) MbCategory('year/$y', '$y'),
  ];

  @override
  bool operator ==(Object other) => other is MbCategory && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Sumber film = LK21, di-scrape LANGSUNG dari HP user (IP server/VPS
/// diblokir Cloudflare LK21, IP rumah/seluler lolos). Nama class tetap
/// "MovieBox" supaya layar film, Nobar, Favorit, Riwayat tidak perlu diubah.
/// Id film = slug LK21 (mis. "jailer-2-2026").
///
/// Base URL dari Remote Config `lk21_base_url` (mis. https://tv12.lk21official.cc).
///   daftar   : {base}/{latest|populer|genre/x|country/x|year/x|quality/x}/page/{n}  (<article>)
///   cari     : {data-search_url}search.php?s=&page=              (JSON)
///   detail   : {base}/{slug}
///   video    : iframe {host}/iframe3/p2p/{id}
///              -> POST {host}/api.php host=p2p&id=     -> embedUrl {embed}/{slug}
///              -> GET  {embed-origin}/verify/{slug}     -> fileUrl (m3u8)
/// Subtitle LK21 sudah menempel di video (hardsub) -> tidak ada caption terpisah.
class MovieBoxRepository {
  MovieBoxRepository(this._subDio)
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(seconds: 25),
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (s) => s != null && s < 500,
            headers: {
              'User-Agent': _ua,
              'Accept-Language': 'id-ID,id;q=0.9,en;q=0.8',
            },
          ),
        );

  final Dio _dio;
  final Dio _subDio;

  static const String _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const int pageSize = 24;

  String? _searchUrl; // data-search_url dari halaman LK21 (domainnya disamarkan)
  String? _thumbUrl; // data-thumbnail_url

  // ------------------------------------------------------------- dasar

  String get _base {
    final b = RemoteConfigManager.lk21BaseUrl;
    if (b == null) throw Exception('Sumber film belum siap, coba lagi nanti');
    return b;
  }

  static String _str(Object? data) => data is String ? data : (data == null ? '' : '$data');

  static bool _isChallenge(int code, String body) =>
      code == 403 && (body.contains('Just a moment') || body.contains('challenge'));

  /// GET halaman LK21. Mengembalikan (html, alamat akhir).
  Future<(String, Uri)> _page(String url) async {
    final res = await _dio.get<dynamic>(url, options: Options(headers: {'Referer': '$_base/'}));
    final code = res.statusCode ?? 0;
    final body = _str(res.data);
    if (_isChallenge(code, body)) {
      throw Exception('Server film sedang menolak akses, coba lagi nanti');
    }
    if (code == 404) throw Exception('Film tidak ditemukan');
    if (code >= 400) throw Exception('Server film bermasalah (kode $code)');
    _rememberUrls(body);
    return (body, res.realUri);
  }

  void _rememberUrls(String html) {
    final s = RegExp(r'''data-search_url=['"]([^'"]+)['"]''').firstMatch(html)?.group(1);
    if (s != null && s.startsWith('http')) _searchUrl = s.endsWith('/') ? s : '$s/';
    final t = RegExp(r'''data-thumbnail_url=['"]([^'"]+)['"]''').firstMatch(html)?.group(1);
    if (t != null && t.startsWith('http')) _thumbUrl = t.endsWith('/') ? t : '$t/';
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&#8217;', '’')
      .replaceAll('&#8211;', '–')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');

  static String _stripTags(String s) =>
      _unescape(s.replaceAll(RegExp(r'<[^>]+>'), ' ')).replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _yearOf(String slug) => RegExp(r'-(\d{4})$').firstMatch(slug)?.group(1);

  // ------------------------------------------------------------- daftar

  List<MbItem> _parseCards(String html) {
    final out = <MbItem>[];
    final seen = <String>{};
    for (final m in RegExp(r'<article\b[^>]*>(.*?)</article>', dotAll: true).allMatches(html)) {
      final a = m.group(1)!;
      // Hanya link relatif (serial dialihkan ke situs lain -> dilewati).
      final slug = RegExp(r'href="/([a-z0-9-]+)/?"').firstMatch(a)?.group(1);
      if (slug == null || !seen.add(slug)) continue;
      final title = RegExp(r'class="poster-title"[^>]*>(.*?)</h3>', dotAll: true).firstMatch(a)?.group(1) ??
          RegExp(r'<img[^>]+alt="([^"]+)"').firstMatch(a)?.group(1);
      final img = RegExp(r'<img[^>]+src="(https?://[^"]+)"').firstMatch(a)?.group(1);
      final rating = RegExp(r'itemprop="ratingValue">([^<]+)<').firstMatch(a)?.group(1)?.trim();
      final year = RegExp(r'class="year"[^>]*>(\d{4})<').firstMatch(a)?.group(1) ?? _yearOf(slug);
      out.add(MbItem(
        id: slug,
        title: title == null ? slug : _stripTags(title),
        cover: img,
        rating: (rating == null || rating.isEmpty || rating == '0') ? null : rating,
        year: year,
        subjectType: 1,
      ));
    }
    return out;
  }

  /// [category] (mis. 'genre/action') mengganti [sort] kalau diisi.
  Future<List<MbItem>> getMovies({int page = 1, MbSort sort = MbSort.recommend, String? category}) async {
    final c = category ?? sort.value;
    final path = page <= 1 ? '/$c' : '/$c/page/$page';
    final (html, _) = await _page('$_base$path');
    return _parseCards(html);
  }

  // ------------------------------------------------------------- cari

  Future<List<MbItem>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    if (_searchUrl == null) await _page('$_base/latest'); // ambil data-search_url
    final su = _searchUrl;
    if (su == null) throw Exception('Pencarian film belum tersedia');

    Future<Map<String, dynamic>?> fetch(int p) async {
      try {
        final res = await _dio.get<dynamic>(
          '${su}search.php',
          queryParameters: {'s': q, 'page': p},
          options: Options(headers: {'Referer': '$_base/', 'Origin': _base}),
        );
        final j = jsonDecode(_str(res.data));
        return j is Map ? Map<String, dynamic>.from(j) : null;
      } catch (_) {
        return null;
      }
    }

    final first = await fetch(1);
    if (first == null) throw Exception('Pencarian film gagal, coba lagi');
    final total = int.tryParse('${first['totalPages'] ?? first['total_pages'] ?? 1}') ?? 1;
    final pages = [first, if (total > 1) await fetch(2)];

    final thumb = _thumbUrl ?? '';
    final seen = <String>{};
    final out = <MbItem>[];
    for (final p in pages) {
      final list = (p?['data'] ?? p?['items']);
      if (list is! List) continue;
      for (final e in list) {
        if (e is! Map) continue;
        if ('${e['type'] ?? 'movie'}' != 'movie') continue; // film saja
        final slug = '${e['slug'] ?? ''}'.trim();
        if (slug.isEmpty || !seen.add(slug)) continue;
        final poster = '${e['poster'] ?? ''}'.trim();
        final rating = '${e['rating'] ?? ''}'.trim();
        out.add(MbItem(
          id: slug,
          title: _unescape('${e['title'] ?? slug}').replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), ''),
          cover: poster.isEmpty ? null : (poster.startsWith('http') ? poster : '$thumb$poster'),
          rating: (rating.isEmpty || rating == '0') ? null : rating,
          year: '${e['year'] ?? ''}'.trim().isEmpty ? _yearOf(slug) : '${e['year']}',
          subjectType: 1,
        ));
      }
    }
    return out;
  }

  // ------------------------------------------------------------- detail

  final Map<String, String> _detailHtml = {}; // slug -> html (dipakai lagi untuk link video)

  Future<String> _detailPage(String slug) async {
    final cached = _detailHtml[slug];
    if (cached != null) return cached;
    final base = Uri.parse(_base);
    final (html, finalUri) = await _page('$_base/${Uri.encodeComponent(slug)}');
    if (finalUri.host.isNotEmpty && finalUri.host != base.host) {
      throw Exception('Judul ini serial, belum didukung');
    }
    if (_detailHtml.length > 20) _detailHtml.remove(_detailHtml.keys.first);
    _detailHtml[slug] = html;
    return html;
  }

  static String? _meta(String html, String prop) {
    final v = RegExp('<meta[^>]+(?:property|name)="${RegExp.escape(prop)}"[^>]+content="([^"]*)"')
            .firstMatch(html)
            ?.group(1) ??
        RegExp('<meta[^>]+content="([^"]*)"[^>]+(?:property|name)="${RegExp.escape(prop)}"')
            .firstMatch(html)
            ?.group(1);
    final t = v == null ? null : _unescape(v).trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Node schema.org Movie dari ld+json (kalau ada).
  static Map<String, dynamic>? _ldMovie(String html) {
    for (final m in RegExp(r'<script type="application/ld\+json">(.*?)</script>', dotAll: true)
        .allMatches(html)) {
      try {
        final j = jsonDecode(m.group(1)!.trim());
        final nodes = <Object?>[
          if (j is Map && j['@graph'] is List) ...(j['@graph'] as List),
          if (j is List) ...j,
          if (j is Map) j,
        ];
        for (final n in nodes) {
          if (n is Map && '${n['@type']}'.contains('Movie')) return Map<String, dynamic>.from(n);
        }
      } catch (_) {}
    }
    return null;
  }

  static String? _isoDuration(Object? v) {
    final m = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?').firstMatch('${v ?? ''}');
    if (m == null || (m.group(1) == null && m.group(2) == null)) return null;
    final h = int.tryParse(m.group(1) ?? '0') ?? 0;
    final mi = int.tryParse(m.group(2) ?? '0') ?? 0;
    return [if (h > 0) '${h}h', if (mi > 0) '${mi}m'].join(' ');
  }

  Future<MbDetail> getDetail(String id) async {
    final html = await _detailPage(id);
    final ld = _ldMovie(html);

    var title = ld?['name']?.toString();
    if (title == null || title.isEmpty) {
      final h1 = RegExp(r'<h1[^>]*>(.*?)</h1>', dotAll: true).firstMatch(html)?.group(1);
      title = h1 == null ? null : _stripTags(h1);
    }
    if (title == null || title.isEmpty) {
      final og = _meta(html, 'og:title') ?? '';
      title = RegExp(r'Nonton (.+?) Sub Indo').firstMatch(og)?.group(1) ?? og;
    }
    title = title
        .replaceFirst(RegExp(r'^(Lk21\s+)?Nonton\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+Sub Indo.*$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*\(\d{4}\)\s*$'), '')
        .trim();

    final ldDesc = ld?['description']?.toString();
    final itemDesc = RegExp(r'itemprop="description"[^>]*>(.*?)</', dotAll: true).firstMatch(html)?.group(1);
    final desc = (ldDesc != null && ldDesc.trim().length > 30)
        ? _unescape(ldDesc.trim())
        : (itemDesc != null && _stripTags(itemDesc).length > 30)
            ? _stripTags(itemDesc)
            : (_meta(html, 'og:description') ?? _meta(html, 'description'));

    final img = ld?['image'];
    final cover = (img is String ? img : (img is Map ? img['url']?.toString() : null)) ??
        _meta(html, 'og:image');

    final agg = ld?['aggregateRating'];
    final rating = agg is Map ? agg['ratingValue']?.toString() : null;

    final g = ld?['genre'];
    final genre = g is List ? g.join(', ') : g?.toString();

    final date = ld?['datePublished']?.toString() ?? _yearOf(id);

    return MbDetail(
      id: id,
      title: title.isEmpty ? id : title,
      description: desc,
      releaseDate: date,
      duration: _isoDuration(ld?['duration']),
      rating: (rating == null || rating == '0') ? null : rating,
      genre: (genre == null || genre.isEmpty) ? null : genre,
      cover: cover,
      subjectType: 1,
    );
  }

  // ------------------------------------------------------------- video

  /// Link m3u8 lewat server "p2p" (hydrax terenkripsi, cast belum didukung).
  Future<List<MbStream>> getStreams(String id, {String? detailPath}) async {
    final html = await _detailPage(id);
    final m = RegExp(r'(https?://[^"/\s]+)/iframe3/p2p/([A-Za-z0-9_-]+)').firstMatch(html);
    if (m == null) throw Exception('Film ini belum bisa diputar di Zenime');
    final nodeOrigin = m.group(1)!;
    final nodeId = m.group(2)!;

    // 1. videonode api.php -> embedUrl
    final r1 = await _dio.post<dynamic>(
      '$nodeOrigin/api.php',
      data: 'host=p2p&id=${Uri.encodeQueryComponent(nodeId)}',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Referer': '$nodeOrigin/iframe3/p2p/$nodeId', 'Origin': nodeOrigin},
      ),
    );
    final b1 = _str(r1.data);
    if (_isChallenge(r1.statusCode ?? 0, b1)) {
      throw Exception('Server video sedang menolak akses, coba lagi nanti');
    }
    String? embed;
    try {
      final j = jsonDecode(b1);
      if (j is Map) embed = j['embedUrl']?.toString();
    } catch (_) {}
    if (embed == null || embed.isEmpty) throw Exception('Link video tidak ditemukan');

    // 2. playcdn /verify/{slug} -> fileUrl (m3u8)
    final eu = Uri.parse(embed);
    final segs = eu.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) throw Exception('Link video tidak dikenali');
    final origin = '${eu.scheme}://${eu.host}';
    final r2 = await _dio.get<dynamic>(
      '$origin/verify/${segs.last}',
      options: Options(headers: {'Referer': embed, 'X-Requested-With': 'XMLHttpRequest'}),
    );
    String? file;
    try {
      final j = jsonDecode(_str(r2.data));
      if (j is Map && '${j['status']}' == 'success') file = j['fileUrl']?.toString();
    } catch (_) {}
    if (file == null || file.isEmpty) throw Exception('Video belum tersedia, coba lagi nanti');

    final headers = <String, String>{'User-Agent': _ua, 'Referer': '$origin/'};
    MovieBoxNetwork.rememberHeaders(file, headers);
    return [
      MbStream(
        url: file,
        quality: 'HD',
        qualityValue: 720,
        format: 'HLS',
        codec: 'h264',
        source: 'LK21',
        headers: headers,
      ),
    ];
  }

  /// LK21 memakai subtitle yang sudah menempel di video.
  Future<List<MbCaption>> getCaptions(String id) async => const [];

  /// Isi file subtitle (SRT/VTT).
  Future<String> fetchSubtitle(String url) async {
    final res = await _subDio.get<List<int>>(url);
    return utf8.decode(res.data ?? const [], allowMalformed: true);
  }
}

final movieBoxRepositoryProvider = Provider<MovieBoxRepository>(
  (ref) => MovieBoxRepository(MovieBoxNetwork.createSubtitleDio()),
);
