import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/remote_config_manager.dart';
import '../models/comic_models.dart';
import 'comic_source.dart';

/// Sumber kedua (Dayynime-v2): API situs Westmanga, dipanggil LANGSUNG dari
/// app (dulu lewat Sanka, berhenti jalan sejak Westmanga pindah domain).
///
/// Base URL dari Remote Config `westmanga_base_url` (mis. https://v1.westmanga.my).
/// Tiap request butuh token kunjungan (header X-WM-Visit) dari
/// /api/visit-token; token terikat IP, berlaku ~30 menit, disimpan & diperbarui
/// otomatis. Header dibuat mirip browser supaya tidak ditolak Cloudflare.
///
/// Endpoint:
///   /api/contents?...      daftar, cari, genre (paginator.current_page/last_page)
///   /api/contents/genres   daftar genre
///   /api/comic/{slug}      detail + daftar chapter
///   /api/v/{slug}          isi chapter (images relatif /img/...)
class WestmangaSource implements ComicSource {
  WestmangaSource()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
            responseType: ResponseType.plain,
            // 4xx dibaca sendiri (403 = token kedaluwarsa).
            validateStatus: (s) => s != null && s < 500,
          ),
        );

  final Dio _dio;

  static const String _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  String? _token;
  int _tokenExp = 0; // detik epoch
  Future<String>? _tokenFuture;

  @override
  ComicSourceId get id => ComicSourceId.westmanga;

  String get _base {
    final b = RemoteConfigManager.westmangaBaseUrl;
    if (b == null) throw Exception('Sumber Dayynime-v2 belum siap, coba lagi nanti');
    return b;
  }

  Map<String, String> _headers(String base, {String? referer}) => {
        'User-Agent': _ua,
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'id-ID,id;q=0.9,en;q=0.8',
        'Origin': base,
        'Referer': referer ?? '$base/',
        'sec-ch-ua': '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
      };

  static Object? _decode(Object? data) {
    if (data is String) {
      final t = data.trim();
      if (t.isEmpty || !(t.startsWith('{') || t.startsWith('['))) return null;
      try {
        return jsonDecode(t);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  Future<String> _visitToken(String base, {bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final t = _token;
    if (!force && t != null && _tokenExp - now > 120) return Future.value(t);
    return _tokenFuture ??= () async {
      try {
        final res = await _dio.get<dynamic>('$base/api/visit-token',
            options: Options(headers: _headers(base)));
        final j = _decode(res.data);
        final tok = j is Map ? j['token']?.toString() : null;
        if (tok == null || tok.isEmpty) {
          throw Exception('Gagal menyambung ke Dayynime-v2, coba lagi');
        }
        _token = tok;
        _tokenExp = _optLong(j is Map ? j['expires_at'] : null, now + 1500);
        return tok;
      } finally {
        _tokenFuture = null;
      }
    }();
  }

  /// GET JSON dengan token; 401/403 = token diperbarui lalu diulang sekali.
  Future<Map<String, dynamic>> _get(String pathAndQuery, {String? referer}) async {
    final base = _base;
    for (var attempt = 0; attempt < 2; attempt++) {
      final tok = await _visitToken(base, force: attempt > 0);
      final res = await _dio.get<dynamic>(
        '$base$pathAndQuery',
        options: Options(headers: {..._headers(base, referer: referer), 'X-WM-Visit': tok}),
      );
      final code = res.statusCode ?? 0;
      final j = _decode(res.data);
      if ((code == 401 || code == 403) && attempt == 0) continue;
      if (code == 404) throw Exception('Komik tidak ditemukan');
      if (j is Map && code < 400) return Map<String, dynamic>.from(j);
      throw Exception(code == 403
          ? 'Dayynime-v2 sedang menolak akses, coba lagi nanti'
          : 'Server Dayynime-v2 bermasalah (kode $code)');
    }
    throw Exception('Gagal memuat Dayynime-v2');
  }

  /// "/img/..." -> "https://host/img/..."; alamat penuh dibiarkan.
  String? _abs(String? u) {
    if (u == null || u.trim().isEmpty) return null;
    final v = u.trim();
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (v.startsWith('//')) return 'https:$v';
    final b = RemoteConfigManager.westmangaBaseUrl ?? '';
    return v.startsWith('/') ? '$b$v' : '$b/$v';
  }

  static String _q(Map<String, String> m) => m.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  // id tab -> parameter /api/contents (lihat _tabQuery)
  @override
  List<ComicTab> get tabs => const [
        ComicTab('latest', 'Terbaru'),
        ComicTab('popular', 'Populer'),
        ComicTab('ongoing', 'Ongoing'),
        ComicTab('completed', 'Tamat'),
        ComicTab('list', 'Semua'),
        ComicTab('manga', 'Manga'),
        ComicTab('manhwa', 'Manhwa'),
        ComicTab('manhua', 'Manhua'),
        ComicTab('az', 'A-Z'),
        ComicTab('za', 'Z-A'),
        ComicTab('added', 'Baru Ditambah'),
        ComicTab('projects', 'Project'),
      ];

  static Map<String, String> _tabQuery(String tabId) => switch (tabId) {
        'popular' => {'orderBy': 'Popular'},
        'ongoing' => {'status': 'Ongoing', 'orderBy': 'Update'},
        'completed' => {'status': 'Completed', 'orderBy': 'Update'},
        'list' => {},
        'manga' => {'country': 'JP', 'orderBy': 'Update'},
        'manhwa' => {'country': 'KR', 'orderBy': 'Update'},
        'manhua' => {'country': 'CN', 'orderBy': 'Update'},
        'az' => {'orderBy': 'Az'},
        'za' => {'orderBy': 'Za'},
        'added' => {'orderBy': 'Added'},
        'projects' => {'project': 'true', 'orderBy': 'Update'},
        _ => {'orderBy': 'Update'}, // latest
      };

  @override
  Future<ComicListResponse> browse(String tabId, int page) async {
    final q = _q({..._tabQuery(tabId), 'page': '$page'});
    return _toList(await _get('/api/contents?$q'));
  }

  @override
  Future<ComicListResponse> search(String query, int page) async {
    final q = _q({'q': query, 'page': '$page'});
    return _toList(await _get('/api/contents?$q'));
  }

  @override
  Future<ComicDetail> detail(String slug) async {
    final map = await _get('/api/comic/${Uri.encodeComponent(slug)}',
        referer: '$_base/comic/$slug');
    final d = map['data'];
    if (d is! Map) throw Exception('Detail komik tidak ditemukan');
    final data = Map<String, dynamic>.from(d);

    final seen = <String>{};
    final chapters = <ComicChapterRef>[];
    for (final c in _maps(data['chapters'])) {
      final s = _str(c['slug']);
      if (s == null || s.trim().isEmpty) continue;
      if (!seen.add(s)) continue; // distinctBy slug
      final updated = _timeFormatted(c['updated_at']);
      final created = _timeFormatted(c['created_at']);
      chapters.add(
        ComicChapterRef(
          title: 'Chapter ${_str(c['number']) ?? ''}'.trim(),
          slug: s,
          date: (updated != null ? _dateOnly(updated) : null) ??
              (created != null ? _dateOnly(created) : null),
        ),
      );
    }

    final rating = _double(data['rating']);
    return ComicDetail(
      title: _str(data['title']),
      cover: _abs(_str(data['cover'])),
      rating: rating != null && rating > 0 ? rating.toString() : null,
      status: _str(data['status']),
      type: _typeOf(_str(data['country_id'])),
      author: _str(data['author']),
      synopsis: _str(data['sinopsis']),
      genres: [
        for (final g in _maps(data['genres']))
          if (_str(g['name']) != null)
            ComicGenreRef(title: _str(g['name'])!, slug: _str(g['id']) ?? ''),
      ],
      chapters: chapters,
    );
  }

  @override
  Future<ComicChapterResponse> chapter(String comicSlug, String chapterSlug) async {
    // Lokasi array gambar di dalam `data` dicari fleksibel (lihat _findImages).
    final map = await _get('/api/v/${Uri.encodeComponent(chapterSlug)}',
        referer: '$_base/view/$chapterSlug');
    final d = map['data'];
    if (d is! Map) throw Exception('Respons chapter tidak valid');
    final data = Map<String, dynamic>.from(d);
    final images = _findImages(data);
    if (images == null) throw Exception('Gambar chapter tidak ditemukan');

    // Daftar chapter ikut di respons (terbaru dulu) -> prev/next dihitung dari sini.
    final chapters = data['chapters'];
    final currentId = _optLong(data['id'], -1);
    var idx = -1;
    var slugs = <(String, String)>[]; // slug to number
    if (chapters is List) {
      slugs = [
        for (final c in chapters)
          if (c is Map) (_optString(c['slug']), _optString(c['number'])),
      ];
      for (var i = 0; i < chapters.length; i++) {
        final c = chapters[i];
        if (c is! Map) continue;
        if (_optLong(c['id'], -2) == currentId || _optString(c['slug']) == chapterSlug) {
          idx = i;
          break;
        }
      }
    }
    String? slugAt(int i) => i >= 0 && i < slugs.length ? slugs[i].$1 : null;
    final next = idx > 0 ? slugAt(idx - 1) : null;
    final prev = idx >= 0 ? slugAt(idx + 1) : null;
    final content = data['content'];
    final comicTitle = content is Map ? _optString(content['title']) : '';
    final number = idx >= 0 && idx < slugs.length ? slugs[idx].$2 : '';
    final full = '$comicTitle Chapter $number'.trim();
    return ComicChapterResponse(
      title: comicTitle.isNotEmpty || number.isNotEmpty ? full : null,
      images: images,
      next: next == null || next.trim().isEmpty ? null : next,
      prev: prev == null || prev.trim().isEmpty ? null : prev,
    );
  }

  @override
  Future<List<ComicGenreItem>> genres() async {
    final map = await _get('/api/contents/genres');
    return [
      for (final g in _maps(map['data']))
        if (_str(g['id']) != null)
          ComicGenreItem(title: _str(g['name']) ?? '', slug: _str(g['id'])!),
    ];
  }

  // genreSlug = id genre; boleh beberapa id dipisah koma ("13,344").
  @override
  Future<ComicListResponse> byGenre(String genreSlug, int page) async {
    final ids = genreSlug.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final g = ids.map((id) => 'genre[]=${Uri.encodeQueryComponent(id)}').join('&');
    final q = _q({'orderBy': 'Update', 'page': '$page'});
    return _toList(await _get('/api/contents?$g&$q'));
  }

  // ---------------------------------------------------------------- mapper

  String? _typeOf(String? country) => switch (country) {
        'KR' => 'Manhwa',
        'CN' => 'Manhua',
        'JP' => 'Manga',
        _ => null,
      };

  // "30 Sep 2026 03:25" -> "30 Sep 2026"
  String _dateOnly(String formatted) => formatted.split(' ').take(3).join(' ');

  static String? _str(Object? v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    return null;
  }

  /// Setara org.json optString: kosong kalau tidak ada.
  static String _optString(Object? v) => _str(v) ?? '';

  static int _optLong(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static double? _double(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static List<Map<String, dynamic>> _maps(Object? v) => (v is List ? v : const [])
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();

  static String? _timeFormatted(Object? v) =>
      v is Map ? _str(v['formatted']) : null;

  static int _timeMillis(Object? v) => v is Map ? _optLong(v['time'], 0) : 0;

  ComicListItem? _toListItem(Map<String, dynamic> m) {
    final s = _str(m['slug']);
    if (s == null || s.trim().isEmpty) return null;
    final t = _str(m['title']);
    if (t == null || t.trim().isEmpty) return null;

    // Chapter terbaru = updated_at.time paling besar (yang pertama kalau seri).
    final last = _maps(m['lastChapters'] ?? m['last_chapters']);
    Map<String, dynamic>? newest;
    var best = -1;
    for (final c in last) {
      final time = _timeMillis(c['updated_at']);
      if (time > best) {
        best = time;
        newest = c;
      }
    }
    final number = newest == null ? null : _str(newest['number']);
    final newestDate = newest == null ? null : _timeFormatted(newest['updated_at']);
    final rating = _double(m['rating']);
    return ComicListItem(
      title: t,
      slug: s,
      cover: _abs(_str(m['cover'])),
      chapter: number != null ? 'Chapter $number' : null,
      date: newestDate != null ? _dateOnly(newestDate) : null,
      rating: rating != null && rating > 0 ? rating.toString() : null,
      type: _typeOf(_str(m['country_id'])),
    );
  }

  ComicListResponse _toList(Map<String, dynamic> map) {
    final p = map['paginator'] ?? map['pagination'];
    final pm = p is Map ? Map<String, dynamic>.from(p) : const <String, dynamic>{};
    final current = _optLong(pm['current_page'], 1);
    final last = _optLong(pm['last_page'], 1);
    final seen = <String>{};
    final items = <ComicListItem>[];
    for (final m in _maps(map['data'])) {
      final item = _toListItem(m);
      if (item != null && seen.add(item.slug)) items.add(item);
    }
    return ComicListResponse(
      komikList: items,
      hasNextPage: current < last,
      currentPage: current,
    );
  }

  // Cari array URL gambar di struktur JSON yang lokasinya belum pasti.
  List<String>? _findImages(Object? node) {
    if (node is Map) {
      for (final k in const ['images', 'image', 'pages', 'chapter_images']) {
        final found = _urlList(node[k]);
        if (found != null) return found;
      }
      for (final v in node.values) {
        final found = _findImages(v);
        if (found != null) return found;
      }
    } else if (node is List) {
      final direct = _urlList(node);
      if (direct != null) return direct;
      for (final v in node) {
        final found = _findImages(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<String>? _urlList(Object? arr) {
    if (arr is! List || arr.isEmpty) return null;
    final out = <String>[];
    for (final v in arr) {
      if (v is! String) return null;
      final t = v.trim();
      if (!(t.startsWith('http') || t.startsWith('/img/') || t.startsWith('//'))) return null;
      out.add(_abs(t)!);
    }
    return out;
  }
}
