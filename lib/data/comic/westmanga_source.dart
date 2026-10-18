import 'package:dio/dio.dart';

import '../api/comic_network.dart';
import '../models/comic_models.dart';
import 'comic_source.dart';

/// Sumber kedua (Dayynime-v2): /comic/westmanga/... Port WestmangaSource.kt +
/// WestmangaApi.kt + WestmangaModels.kt. Respons dibungkus `data`; list
/// dipaginasi lewat pagination.current_page / last_page.
class WestmangaSource implements ComicSource {
  WestmangaSource(this._dio);

  final Dio _dio;

  @override
  ComicSourceId get id => ComicSourceId.westmanga;

  // id tab = nama endpoint /westmanga/{id}
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
        ComicTab('colored', 'Berwarna'),
        ComicTab('uncolored', 'Hitam Putih'),
        ComicTab('projects', 'Project'),
        ComicTab('others', 'Lainnya'),
      ];

  @override
  Future<ComicListResponse> browse(String tabId, int page) async {
    // GET westmanga/{kind}?page=
    return _toList(
      await comicGetMap(_dio, 'westmanga/${comicEnc(tabId)}', query: {'page': page}),
    );
  }

  @override
  Future<ComicListResponse> search(String query, int page) async {
    // GET westmanga/search?q=&page=
    return _toList(
      await comicGetMap(_dio, 'westmanga/search', query: {'q': query, 'page': page}),
    );
  }

  @override
  Future<ComicDetail> detail(String slug) async {
    // GET westmanga/detail/{slug} -> { data: {...} }
    final map = await comicGetMap(_dio, 'westmanga/detail/${comicEnc(slug)}');
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
      cover: _str(data['cover']),
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
    // GET westmanga/chapter/{slug}. Sengaja diambil mentah: lokasi array
    // gambar di dalam `data` dicari fleksibel (lihat _findImages).
    final map = await comicGetMap(_dio, 'westmanga/chapter/${comicEnc(chapterSlug)}');
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
    // GET westmanga/genres -> { data: [{id, name}] }
    final map = await comicGetMap(_dio, 'westmanga/genres');
    return [
      for (final g in _maps(map['data']))
        if (_str(g['id']) != null)
          ComicGenreItem(title: _str(g['name']) ?? '', slug: _str(g['id'])!),
    ];
  }

  // genreSlug = id genre; boleh beberapa id dipisah koma ("13,344") -> genres-filter.
  @override
  Future<ComicListResponse> byGenre(String genreSlug, int page) async {
    if (genreSlug.contains(',')) {
      // GET westmanga/genres-filter?genres=13,344&page=
      return _toList(
        await comicGetMap(
          _dio,
          'westmanga/genres-filter',
          query: {'genres': genreSlug, 'page': page},
        ),
      );
    }
    // GET westmanga/genre/{id}?page=
    return _toList(
      await comicGetMap(
        _dio,
        'westmanga/genre/${comicEnc(genreSlug)}',
        query: {'page': page},
      ),
    );
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
      cover: _str(m['cover']),
      chapter: number != null ? 'Chapter $number' : null,
      date: newestDate != null ? _dateOnly(newestDate) : null,
      rating: rating != null && rating > 0 ? rating.toString() : null,
      type: _typeOf(_str(m['country_id'])),
    );
  }

  ComicListResponse _toList(Map<String, dynamic> map) {
    final p = map['pagination'];
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
      if (v is! String || !v.startsWith('http')) return null;
      out.add(v);
    }
    return out;
  }
}
