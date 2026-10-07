import '../comic/comic_source.dart';
import '../local/comic_store.dart';
import '../models/comic_models.dart';

class _CacheEntry<T> {
  _CacheEntry(this.data) : timestamp = DateTime.now().millisecondsSinceEpoch;

  final T data;
  final int timestamp;

  bool isFresh(int ttlMillis) =>
      DateTime.now().millisecondsSinceEpoch - timestamp < ttlMillis;
}

/// Repository komik multi-sumber (Dayynime-v1, Dayynime-v2). Port
/// ComicRepository.kt. Method melempar exception kalau gagal (setara
/// Result.Error); pemanggil yang menangkapnya.
///
/// Slug komik yang keluar dari repository ini SUDAH berupa "kunci" (lihat
/// [ComicKey]): Bacakomik polos, sumber lain diberi awalan "sumber~". Kunci
/// itu yang dipakai UI, route, dan penyimpanan lokal. Slug chapter tetap polos.
class ComicRepository {
  ComicRepository(this.availableSources, this._store);

  final List<ComicSource> availableSources;
  final ComicStore _store;

  static const int _ttlList = 5 * 60 * 1000; // 5 menit, cuma page 1
  static const int _ttlDetail = 30 * 60 * 1000; // 30 menit
  static const int _ttlGenres = 60 * 60 * 1000; // 1 jam

  ComicStore get store => _store;

  ComicSource _sourceOf(ComicSourceId id) =>
      availableSources.firstWhere((s) => s.id == id);

  List<ComicTab> tabsOf(ComicSourceId id) => _sourceOf(id).tabs;

  // Cache CUMA buat page 1 tiap (sumber, tab). Page 2+ ("Load More") selalu fetch baru.
  final Map<String, _CacheEntry<ComicListResponse>> _listPage1Cache = {};
  final Map<String, _CacheEntry<ComicDetail>> _detailCache = {};
  final Map<ComicSourceId, _CacheEntry<List<ComicGenreItem>>> _genresCache = {};

  // Tambahkan awalan sumber ke slug tiap komik di hasil list.
  ComicListResponse _withKeys(ComicListResponse r, ComicSourceId source) =>
      r.copyWith(
        komikList: r.komikList
            ?.map((e) => e.copyWith(slug: ComicKey.encode(source, e.slug)))
            .toList(),
      );

  // ---- List per tab ----

  Future<ComicListResponse> browse(
    ComicSourceId sourceId,
    String tabId, {
    int page = 1,
    bool forceRefresh = false,
  }) async {
    final source = _sourceOf(sourceId);
    if (page == 1) {
      final cacheKey = '${sourceId.id}/$tabId';
      final cached = _listPage1Cache[cacheKey];
      if (!forceRefresh && cached != null && cached.isFresh(_ttlList)) {
        return cached.data;
      }
      try {
        final res = _withKeys(await source.browse(tabId, page), sourceId);
        _listPage1Cache[cacheKey] = _CacheEntry(res);
        return res;
      } catch (_) {
        if (cached != null) return cached.data;
        rethrow;
      }
    }
    return _withKeys(await source.browse(tabId, page), sourceId);
  }

  // Dipakai Beranda (kartu komik): tetap Bacakomik, seperti di Zenime.
  Future<ComicListResponse> getLatest({int page = 1, bool forceRefresh = false}) =>
      browse(ComicSourceId.bacakomik, 'latest', page: page, forceRefresh: forceRefresh);

  Future<ComicListResponse> getPopular({int page = 1, bool forceRefresh = false}) =>
      browse(ComicSourceId.bacakomik, 'popular', page: page, forceRefresh: forceRefresh);

  // Search sengaja tidak di-cache: query berubah-ubah tiap ketikan.
  Future<ComicListResponse> search(ComicSourceId sourceId, String query, {int page = 1}) async =>
      _withKeys(await _sourceOf(sourceId).search(query, page), sourceId);

  // ---- Detail & chapter ----

  // comicKey = kunci komik (lihat ComicKey); Bacakomik lama (tanpa awalan) tetap jalan.
  Future<ComicDetail> getDetail(String comicKey, {bool forceRefresh = false}) async {
    final (sourceId, slug) = ComicKey.decode(comicKey);
    final cached = _detailCache[comicKey];
    if (!forceRefresh && cached != null && cached.isFresh(_ttlDetail)) {
      return cached.data;
    }
    try {
      final detail = await _sourceOf(sourceId).detail(slug);
      _detailCache[comicKey] = _CacheEntry(detail);
      return detail;
    } catch (_) {
      if (cached != null) return cached.data;
      rethrow;
    }
  }

  // Chapter (halaman baca) sengaja tidak di-cache.
  Future<ComicChapterResponse> getChapter(String comicKey, String chapterSlug) {
    final (sourceId, comicSlug) = ComicKey.decode(comicKey);
    return _sourceOf(sourceId).chapter(comicSlug, chapterSlug);
  }

  // ---- Genre ----

  Future<List<ComicGenreItem>> getGenres(
    ComicSourceId sourceId, {
    bool forceRefresh = false,
  }) async {
    final cached = _genresCache[sourceId];
    if (!forceRefresh && cached != null && cached.isFresh(_ttlGenres)) {
      return cached.data;
    }
    try {
      final list = await _sourceOf(sourceId).genres();
      _genresCache[sourceId] = _CacheEntry(list);
      return list;
    } catch (_) {
      if (cached != null) return cached.data;
      rethrow;
    }
  }

  Future<ComicListResponse> getByGenre(
    ComicSourceId sourceId,
    String genreSlug, {
    int page = 1,
  }) async =>
      _withKeys(await _sourceOf(sourceId).byGenre(genreSlug, page), sourceId);

  // ---- Favorit (bookmark) -- slug = kunci komik ----

  Future<void> toggleFavorite({
    required String slug,
    required String title,
    String? cover,
    String? status,
    required bool isCurrentlyFavorite,
  }) {
    if (isCurrentlyFavorite) return _store.removeFavorite(slug);
    return _store.addFavorite(
      ComicFavorite(
        slug: slug,
        title: title,
        cover: cover,
        status: status,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  // ---- Progress baca ("Lanjutkan Baca") -- comicSlug = kunci komik ----

  Future<ComicProgress?> getProgressOnce(String comicSlug) async {
    await _store.ready;
    return _store.progressFor(comicSlug);
  }

  Future<void> saveProgress({
    required String comicSlug,
    required String comicTitle,
    String? comicCover,
    required String chapterSlug,
    String? chapterLabel,
    required int scrollItemIndex,
    required double scrollAlignment,
  }) async {
    await _store.ready;
    await _store.upsertProgress(
      ComicProgress(
        comicSlug: comicSlug,
        comicTitle: comicTitle,
        comicCover: comicCover,
        chapterSlug: chapterSlug,
        chapterLabel: chapterLabel,
        scrollItemIndex: scrollItemIndex,
        scrollAlignment: scrollAlignment,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
