import 'package:dio/dio.dart';

import '../api/comic_network.dart';
import '../models/comic_models.dart';
import 'comic_source.dart';

/// Sumber asli (Dayynime-v1): /comic/bacakomik/... (data dari bacakomik.my).
/// Port BacakomikSource.kt + ComicApi.kt.
class BacakomikSource implements ComicSource {
  BacakomikSource(this._dio);

  final Dio _dio;

  @override
  ComicSourceId get id => ComicSourceId.bacakomik;

  @override
  List<ComicTab> get tabs => const [
        ComicTab('latest', 'Terbaru'),
        ComicTab('popular', 'Populer'),
      ];

  @override
  Future<ComicListResponse> browse(String tabId, int page) async {
    // GET bacakomik/latest?page= | bacakomik/populer?page=
    final path = tabId == 'popular' ? 'bacakomik/populer' : 'bacakomik/latest';
    return ComicListResponse.fromJson(
      await comicGetMap(_dio, path, query: {'page': page}),
    );
  }

  @override
  Future<ComicListResponse> search(String query, int page) async {
    // GET bacakomik/search/{query}?page=
    return ComicListResponse.fromJson(
      await comicGetMap(
        _dio,
        'bacakomik/search/${comicEnc(query)}',
        query: {'page': page},
      ),
    );
  }

  @override
  Future<ComicDetail> detail(String slug) async {
    // GET bacakomik/detail/{slug} -> { detail: {...} }
    final map = await comicGetMap(_dio, 'bacakomik/detail/${comicEnc(slug)}');
    final d = map['detail'];
    if (d is! Map) throw Exception('Detail komik tidak ditemukan');
    return ComicDetail.fromJson(Map<String, dynamic>.from(d));
  }

  @override
  Future<ComicChapterResponse> chapter(String comicSlug, String chapterSlug) async {
    // GET bacakomik/chapter/{chapterSlug}. chapterSlug WAJIB slug lengkap
    // dengan nomor chapter (mis. "nano-machine-chapter-1"), yaitu field
    // `slug` di detail.chapters, BUKAN slug komik polos.
    return ComicChapterResponse.fromJson(
      await comicGetMap(_dio, 'bacakomik/chapter/${comicEnc(chapterSlug)}'),
    );
  }

  @override
  Future<List<ComicGenreItem>> genres() async {
    // GET bacakomik/genres -> { genres: [{title, slug}] }
    final map = await comicGetMap(_dio, 'bacakomik/genres');
    return (map['genres'] is List ? map['genres'] as List : const [])
        .whereType<Map>()
        .map((m) => ComicGenreItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  @override
  Future<ComicListResponse> byGenre(String genreSlug, int page) async {
    // GET bacakomik/genre/{slug}?page=
    return ComicListResponse.fromJson(
      await comicGetMap(
        _dio,
        'bacakomik/genre/${comicEnc(genreSlug)}',
        query: {'page': page},
      ),
    );
  }
}
