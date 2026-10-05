import '../../core/json_helper.dart';
import '../api/api_service.dart';
import '../local/entities.dart';
import '../local/local_store.dart';
import '../models/anime_item.dart';
import '../models/cuplix_item.dart';
import '../models/episode_item.dart';
import '../models/genre_item.dart';
import '../models/home_sections.dart';
import '../models/media_item.dart';
import '../models/stream_data.dart';

/// Port AnimeRepository.kt. Method jaringan melempar exception kalau gagal
/// (setara Result.failure); pemanggil yang menangkapnya.
class AnimeRepository {
  AnimeRepository(this._api, this._store);

  final ApiService _api;
  final LocalStore _store;

  // Cache dalam memori
  HomeSectionData? _cachedHome;
  int _cachedHomeTime = 0;
  final Map<String, AnimeItem> _detailCache = {};
  List<GenreItem>? _cachedGenres;

  static bool _blank(String? s) => s == null || s.trim().isEmpty;

  List<AnimeItem> _filterValidHeroAnime(List<AnimeItem> list) {
    return list
        .where((item) {
          final hasImage = !_blank(item.imageCover) || !_blank(item.imagePoster);
          final t = item.title;
          final hasTitle = !_blank(t) &&
              t!.toLowerCase() != 'none' &&
              t.toLowerCase() != 'anime';
          return hasImage && hasTitle;
        })
        .take(6)
        .toList();
  }

  Future<HomeSectionData> getHomeSections({
    bool forceRefresh = false,
    String currentDay = 'SENIN',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _cachedHome;
    if (!forceRefresh && cached != null && (now - _cachedHomeTime < 5 * 60 * 1000)) {
      return cached;
    }

    try {
      // Ambil kategori hot dari 3/2/home/hot supaya carousel hero berisi anime asli
      var heroAnimeList = <AnimeItem>[];
      try {
        final hotApiResp = await _api.getHomeCategory('hot', page: 0);
        heroAnimeList = _filterValidHeroAnime(JsonHelper.parseAnimeList(hotApiResp.data));
      } catch (_) {}

      final resp = await _api.getHomeList(limit: 12, day: currentDay);
      final rawData = resp.data;
      if (rawData is Map) {
        final hot = JsonHelper.parseAnimeList(rawData['hot']);
        final popular = JsonHelper.parseAnimeList(rawData['popular']);
        final newRelease = JsonHelper.parseAnimeList(rawData['new']);
        final random = JsonHelper.parseAnimeList(rawData['random']);
        final today = JsonHelper.parseAnimeList(rawData['today']);
        final update = JsonHelper.parseAnimeList(rawData['update']);

        // Kalau hero kosong, ambil dari hot lalu popular (JANGAN rawData['slider'])
        if (heroAnimeList.isEmpty) heroAnimeList = _filterValidHeroAnime(hot);
        if (heroAnimeList.isEmpty) heroAnimeList = _filterValidHeroAnime(popular);

        final result = HomeSectionData(
          slider: heroAnimeList,
          hot: hot,
          popular: popular,
          newRelease: newRelease,
          random: random,
          today: today,
          update: update,
        );
        _cachedHome = result;
        _cachedHomeTime = now;
        return result;
      }

      // Fallback ke kategori satu per satu
      final hotResp = await _api.getHomeCategory('hot', page: 0);
      final popResp = await _api.getHomeCategory('popular', page: 0);
      final newResp = await _api.getHomeCategory('new', page: 0);
      final ranResp = await _api.getHomeCategory('random', page: 0);

      final hot = JsonHelper.parseAnimeList(hotResp.data);
      final popular = JsonHelper.parseAnimeList(popResp.data);
      final newRelease = JsonHelper.parseAnimeList(newResp.data);
      final random = JsonHelper.parseAnimeList(ranResp.data);

      if (heroAnimeList.isEmpty) {
        heroAnimeList = _filterValidHeroAnime(hot);
        if (heroAnimeList.isEmpty) heroAnimeList = _filterValidHeroAnime(popular);
      }

      final result = HomeSectionData(
        slider: heroAnimeList,
        hot: hot,
        popular: popular,
        newRelease: newRelease,
        random: random,
      );
      _cachedHome = result;
      _cachedHomeTime = now;
      return result;
    } catch (_) {
      // Pakai cache walau sudah kedaluwarsa kalau ada
      final c = _cachedHome;
      if (c != null) return c;
      rethrow;
    }
  }

  Future<List<AnimeItem>> getHomeCategory(String category, int page) async {
    final resp = await _api.getHomeCategory(category, page: page);
    return JsonHelper.parseAnimeList(resp.data);
  }

  Future<List<AnimeItem>> getSchedule(String day, {int page = 0}) async {
    final resp = await _api.getSchedule(day, sort: 'views', page: page);
    return JsonHelper.parseAnimeList(resp.data);
  }

  Future<List<GenreItem>> getGenres() async {
    final cached = _cachedGenres;
    if (cached != null && cached.isNotEmpty) return cached;
    final resp = await _api.getGenreList();
    final list = JsonHelper.parseGenreList(resp.data);
    _cachedGenres = list;
    return list;
  }

  /// API tidak punya endpoint pencarian gabungan, jadi satu filter dipilih
  /// sebagai "endpoint utama" (prioritas: kata kunci > genre > tipe > tahun >
  /// studio), lalu filter lainnya (status, tipe, tahun, genre) diterapkan di
  /// sisi app dari hasil endpoint utama. Pola yang sama dengan Zenime.
  ///
  /// Kalau satu halaman habis tersaring, halaman berikutnya diminta otomatis
  /// (maks 5 kali) supaya daftar tidak kosong padahal masih ada hasil.
  /// [page] di hasil = halaman terakhir yang benar-benar diminta.
  Future<({List<AnimeItem> items, int page, bool hasMore})> explore({
    String keyword = '',
    String? genreId,
    String? genreName,
    String? type,
    String? year,
    String? status,
    String? studio,
    String sort = 'views',
    int page = 0,
  }) async {
    final primary = _primaryFilter(keyword, genreId, type, year, studio);
    var current = page;
    for (var attempt = 0; attempt < 5; attempt++) {
      final ApiResponse resp;
      switch (primary) {
        case 'keyword':
          resp = await _api.exploreMovie(keyword: keyword, sort: sort, page: current);
        case 'genre':
          resp = await _api.exploreByGenre(genreId!, sort: sort, page: current);
        case 'type':
          resp = await _api.exploreByType(type!, sort: sort, page: current);
        case 'year':
          resp = await _api.exploreByYear(year!, season: '', sort: sort, page: current);
        case 'studio':
          resp = await _api.exploreByStudio(studio!, sort: sort, page: current);
        default:
          resp = await _api.exploreMovie(keyword: '', sort: sort, page: current);
      }
      final raw = JsonHelper.parseAnimeList(resp.data);
      final hasMore = raw.isNotEmpty;
      final items = _applyLocalFilters(
        raw,
        primary: primary,
        genreName: genreName,
        type: type,
        year: year,
        status: status,
      );
      if (items.isNotEmpty || !hasMore) {
        return (items: items, page: current, hasMore: hasMore);
      }
      current++;
    }
    return (items: const <AnimeItem>[], page: current - 1, hasMore: true);
  }

  static String _primaryFilter(
    String keyword,
    String? genreId,
    String? type,
    String? year,
    String? studio,
  ) {
    if (!_blank(keyword)) return 'keyword';
    if (!_blank(genreId)) return 'genre';
    if (!_blank(type)) return 'type';
    if (!_blank(year)) return 'year';
    if (!_blank(studio)) return 'studio';
    return 'none';
  }

  static List<AnimeItem> _applyLocalFilters(
    List<AnimeItem> raw, {
    required String primary,
    String? genreName,
    String? type,
    String? year,
    String? status,
  }) {
    bool eq(String? a, String b) =>
        a != null && a.trim().toLowerCase() == b.trim().toLowerCase();
    return raw.where((a) {
      if (!_blank(status) && !eq(a.status, status!)) return false;
      if (primary != 'type' && !_blank(type) && !eq(a.type, type!)) return false;
      if (primary != 'year' && !_blank(year) && !eq(a.year, year!)) return false;
      if (primary != 'genre' && !_blank(genreName)) {
        final g = (a.genre ?? '').toLowerCase();
        if (!g.contains(genreName!.trim().toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  Future<AnimeItem> getMovieDetail(String id, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _detailCache[id];
      if (cached != null) return cached;
    }
    try {
      final resp = await _api.getMovieDetail(id);
      final data = resp.data;
      AnimeItem? animeItem;
      if (data is Map) {
        final movie = data['movie'];
        final Map movieObj = movie is Map ? movie : data;
        animeItem = JsonHelper.parseAnimeItem(movieObj);
      }
      if (animeItem != null) {
        _detailCache[id] = animeItem;
        return animeItem;
      }
      throw Exception('Format detail anime tidak dikenali');
    } catch (_) {
      final cached = _detailCache[id];
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<EpisodeItem>> getMovieEpisodes(String id,
      {int page = 0, String search = ''}) async {
    final resp = await _api.getMovieEpisodes(id, page: page, search: search);
    return JsonHelper.parseEpisodeList(resp.data);
  }

  Future<StreamData> getEpisodeStream(String idEpisode) async {
    final resp = await _api.getEpisodeStream(idEpisode);
    return JsonHelper.parseStreamData(resp.data);
  }

  Future<List<MediaGalleryItem>> getMovieCovers(String idMovie, {int page = 0}) async {
    final resp = await _api.getMovieCovers(idMovie, page: page);
    return JsonHelper.parseMediaList(resp.data);
  }

  Future<List<MediaGalleryItem>> getMoviePosters(String idMovie, {int page = 0}) async {
    final resp = await _api.getMoviePosters(idMovie, page: page);
    return JsonHelper.parseMediaList(resp.data);
  }

  Future<List<CuplixItem>> getMovieCuplix(String idMovie, {int page = 0}) async {
    final resp = await _api.getMovieCuplix(idMovie, page: page);
    return JsonHelper.parseCuplixList(resp.data);
  }

  Future<(List<CuplixItem>, Map<String, String>)> getCuplixScroll({
    String sort = 'scroll_likes',
    String keyIdFyp = '',
    Map<String, String> cursorParams = const {},
  }) async {
    final resp = await _api.getCuplixScroll(
      limit: 30,
      sort: sort,
      keyIdFyp: keyIdFyp,
      cursorParams: cursorParams,
    );
    final list = JsonHelper.parseCuplixList(resp.data);
    final newCursors = JsonHelper.extractCursors(resp.data);
    return (list, newCursors);
  }

  // ---- Penyimpanan lokal (setara Room) ----

  List<FavoriteEntity> get favorites => _store.favorites;

  bool isFavorite(String id) => _store.isFavorite(id);

  Future<void> toggleFavorite(AnimeItem anime) async {
    final animeId = anime.id;
    if (animeId == null) return;
    if (_store.isFavorite(animeId)) {
      await _store.deleteFavorite(animeId);
    } else {
      await _store.insertFavorite(
        FavoriteEntity(
          id: animeId,
          title: anime.title ?? 'Anime',
          posterUrl: anime.posterUrl,
          coverUrl: anime.coverUrl,
          synopsis: anime.synopsis,
          genre: anime.genre,
          status: anime.status,
          type: anime.type,
          views: anime.views,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> removeFavorite(String id) => _store.deleteFavorite(id);

  List<WatchHistoryEntity> get watchHistory => _store.history;

  WatchHistoryEntity? latestHistoryForMovie(String movieId) =>
      _store.latestHistoryForMovie(movieId);

  WatchHistoryEntity? historyForEpisode(String episodeId) =>
      _store.historyForEpisode(episodeId);

  Future<void> saveWatchProgress({
    required String movieId,
    required String movieTitle,
    required String moviePoster,
    required String episodeId,
    required String episodeIndex,
    required String episodeTitle,
    required int playbackPositionMs,
    required int durationMs,
  }) async {
    if (episodeId.isEmpty || movieId.isEmpty) return;
    await _store.insertOrUpdateHistory(
      WatchHistoryEntity(
        id: '${movieId}_$episodeId',
        movieId: movieId,
        movieTitle: movieTitle,
        moviePoster: moviePoster,
        episodeId: episodeId,
        episodeIndex: episodeIndex,
        episodeTitle: episodeTitle,
        playbackPositionMs: playbackPositionMs,
        durationMs: durationMs,
        lastWatchedTime: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> deleteHistory(String id) => _store.deleteHistory(id);

  Future<void> clearAllHistory() => _store.clearAllHistory();
}
