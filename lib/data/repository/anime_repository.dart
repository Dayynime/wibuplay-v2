import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/content_filter.dart';
import '../../core/firebase_config.dart';
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
import 'public_profile_repository.dart';

/// Port AnimeRepository.kt. Method jaringan melempar exception kalau gagal
/// (setara Result.failure); pemanggil yang menangkapnya.
class AnimeRepository {
  AnimeRepository(this._api, this._store, [this._publicProfile]);

  final ApiService _api;
  final LocalStore _store;

  /// Sinkronisasi favorit/riwayat ke Supabase (opsional, best-effort).
  final PublicProfileRepository? _publicProfile;

  /// UID user yang login (null kalau belum login / email belum verifikasi,
  /// aturan sama dengan AuthRepository).
  String? _currentUidOrNull() {
    if (!FirebaseConfig.ready) return null;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    final viaGoogle = u.providerData.any((p) => p.providerId == 'google.com');
    return (viaGoogle || u.emailVerified) ? u.uid : null;
  }

  void _sync(Future<void> Function(PublicProfileRepository repo, String uid) job) {
    final repo = _publicProfile;
    final uid = _currentUidOrNull();
    if (repo == null || uid == null) return;
    unawaited(job(repo, uid));
  }

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
      // Kategori hot (untuk carousel hero) dan daftar Beranda diambil
      // BERSAMAAN, bukan bergantian: tunggu satu kali, bukan dua kali.
      // Hot boleh gagal (hero lalu diambil dari hot/popular daftar Beranda).
      final first = await Future.wait<dynamic>([
        _api
            .getHomeCategory('hot', page: 0)
            .then<dynamic>((r) => r.data)
            .catchError((Object _) => null),
        _api.getHomeList(limit: 12, day: currentDay).then<dynamic>((r) => r.data),
      ]);
      final hotCategory = first[0];
      final home = first[1];

      // Respons mentah disimpan apa adanya supaya bisa disimpan ke HP dan
      // diurai ulang dengan aturan yang sama (lihat _homeFromRaw).
      final raw = <String, dynamic>{'hotCategory': hotCategory};
      if (home is Map) {
        raw['home'] = home;
        // Cadangan: jadwal hari ini dari endpoint jadwal kalau section kosong.
        if (JsonHelper.parseAnimeList(home['today']).isEmpty) {
          try {
            raw['schedule'] = (await _api.getSchedule(currentDay, sort: 'views', page: 0)).data;
          } catch (_) {}
        }
      } else {
        // Fallback ke kategori satu per satu (sekarang paralel). Hot dipakai
        // ulang dari request di atas; diulang hanya kalau tadi gagal.
        final rest = await Future.wait([
          _api.getHomeCategory('popular', page: 0),
          _api.getHomeCategory('new', page: 0),
          _api.getHomeCategory('random', page: 0),
        ]);
        raw['hot'] = hotCategory ?? (await _api.getHomeCategory('hot', page: 0)).data;
        raw['popular'] = rest[0].data;
        raw['new'] = rest[1].data;
        raw['random'] = rest[2].data;
      }

      final result = _homeFromRaw(raw);
      _cachedHome = result;
      _cachedHomeTime = now;
      unawaited(_saveHomeCache(raw, currentDay));
      return result;
    } catch (_) {
      // Pakai cache walau sudah kedaluwarsa kalau ada (memori, lalu HP).
      final c = _cachedHome;
      if (c != null) return c;
      final disk = await loadCachedHome(currentDay: currentDay);
      if (disk != null) return disk;
      rethrow;
    }
  }

  /// Urai respons mentah Beranda jadi [HomeSectionData].
  /// [sameDay] false = salinan dari hari lain, section "hari ini" dikosongkan.
  HomeSectionData _homeFromRaw(Map raw, {bool sameDay = true}) {
    var heroAnimeList = _filterValidHeroAnime(JsonHelper.parseAnimeList(raw['hotCategory']));

    final home = raw['home'];
    if (home is Map) {
      final hot = JsonHelper.parseAnimeList(home['hot']);
      final popular = JsonHelper.parseAnimeList(home['popular']);
      final newRelease = JsonHelper.parseAnimeList(home['new']);
      final random = JsonHelper.parseAnimeList(home['random']);
      var today = JsonHelper.parseAnimeList(home['today']);
      if (today.isEmpty) today = JsonHelper.parseAnimeList(raw['schedule']);
      final update = JsonHelper.parseAnimeList(home['update']);
      final waiting = JsonHelper.parseAnimeList(home['waiting']);
      final updateLabels = JsonHelper.parseEpisodeLabels(home['update']);

      // Kalau hero kosong, ambil dari hot lalu popular (JANGAN home['slider'])
      if (heroAnimeList.isEmpty) heroAnimeList = _filterValidHeroAnime(hot);
      if (heroAnimeList.isEmpty) heroAnimeList = _filterValidHeroAnime(popular);

      return HomeSectionData(
        slider: heroAnimeList,
        hot: hot,
        popular: popular,
        newRelease: newRelease,
        random: random,
        today: sameDay ? today : const [],
        update: update,
        waiting: waiting,
        updateLabels: updateLabels,
      );
    }

    final hot = JsonHelper.parseAnimeList(raw['hot']);
    final popular = JsonHelper.parseAnimeList(raw['popular']);
    final newRelease = JsonHelper.parseAnimeList(raw['new']);
    final random = JsonHelper.parseAnimeList(raw['random']);

    if (heroAnimeList.isEmpty) {
      heroAnimeList = _filterValidHeroAnime(hot);
      if (heroAnimeList.isEmpty) heroAnimeList = _filterValidHeroAnime(popular);
    }

    return HomeSectionData(
      slider: heroAnimeList,
      hot: hot,
      popular: popular,
      newRelease: newRelease,
      random: random,
    );
  }

  // ---- Salinan Beranda di HP ----
  // Beranda terakhir disimpan ke file supaya saat app dibuka dari nol isinya
  // langsung tampil, lalu data baru menyusul di belakang (HomeController).

  static const String _homeCacheName = 'home_sections_cache_v1.json';

  Future<File?> _homeCacheFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_homeCacheName');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveHomeCache(Map<String, dynamic> raw, String day) async {
    try {
      final f = await _homeCacheFile();
      if (f == null) return;
      final body = jsonEncode({
        'v': 1,
        'day': day,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'raw': raw,
      });
      // Tulis ke file sementara lalu rename: file lama tidak pernah setengah jadi.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Salinan Beranda terakhir dari HP; null kalau belum ada, rusak, atau kosong.
  Future<HomeSectionData?> loadCachedHome({String currentDay = 'SENIN'}) async {
    try {
      final f = await _homeCacheFile();
      if (f == null || !await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || j['v'] != 1) return null;
      final raw = j['raw'];
      if (raw is! Map) return null;
      final d = _homeFromRaw(raw, sameDay: j['day'] == currentDay);
      final empty = d.slider.isEmpty &&
          d.hot.isEmpty &&
          d.popular.isEmpty &&
          d.newRelease.isEmpty &&
          d.update.isEmpty;
      return empty ? null : d;
    } catch (_) {
      return null;
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
    final list = JsonHelper.parseGenreList(resp.data)
        .where((g) => !ContentFilter.isBlockedGenre(g.name ?? ''))
        .toList();
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

  /// Season lain dari anime ini. Daftar season ada di respons detail (key apa
  /// pun yang mengandung "season" dan berisi list), sama seperti getSeasons
  /// Zenime. Kosong = anime ini belum punya season lain.
  Future<List<AnimeItem>> getSeasons(String movieId) async {
    final resp = await _api.getMovieDetail(movieId);
    final data = resp.data;
    if (data is! Map) return const [];

    List<dynamic>? findList(Map m) {
      for (final e in m.entries) {
        if (e.key.toString().toLowerCase().contains('season') && e.value is List) {
          return e.value as List<dynamic>;
        }
      }
      return null;
    }

    final inner = data['movie'];
    final list = findList(data) ?? (inner is Map ? findList(inner) : null) ?? const [];
    final out = <AnimeItem>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final item = JsonHelper.parseAnimeItem(raw);
      if (item != null && (item.id ?? '').isNotEmpty) out.add(item);
    }
    return out;
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
      _sync((repo, uid) => repo.syncFavoriteRemoved(uid, animeId));
    } else {
      final entity = FavoriteEntity(
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
      );
      await _store.insertFavorite(entity);
      _sync((repo, uid) => repo.syncFavoriteAdded(uid, entity));
    }
  }

  /// Favorit donghua: disimpan di daftar favorit yang sama dengan
  /// `type = Donghua` dan id = slug, supaya bisa dipisah dari anime.
  Future<void> toggleDonghuaFavorite({
    required String slug,
    required String title,
    String? poster,
    String? status,
    String? synopsis,
    String? genre,
  }) async {
    if (slug.isEmpty) return;
    if (_store.isFavorite(slug)) {
      await _store.deleteFavorite(slug);
      _sync((repo, uid) => repo.syncFavoriteRemoved(uid, slug));
      return;
    }
    final entity = FavoriteEntity(
      id: slug,
      title: title.isEmpty ? 'Donghua' : title,
      posterUrl: poster ?? '',
      coverUrl: poster ?? '',
      synopsis: synopsis,
      genre: genre,
      status: status,
      type: FavoriteEntity.donghuaType,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await _store.insertFavorite(entity);
    _sync((repo, uid) => repo.syncFavoriteAdded(uid, entity));
  }

  Future<void> removeFavorite(String id) async {
    await _store.deleteFavorite(id);
    _sync((repo, uid) => repo.syncFavoriteRemoved(uid, id));
  }

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
    final entity = WatchHistoryEntity(
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
    );
    await _store.insertOrUpdateHistory(entity);
    _sync((repo, uid) => repo.syncWatchProgress(uid, entity));
  }

  Future<void> deleteHistory(String id) async {
    // Ambil movieId/episodeId dulu sebelum baris lokal dihapus.
    WatchHistoryEntity? target;
    for (final h in _store.history) {
      if (h.id == id) {
        target = h;
        break;
      }
    }
    await _store.deleteHistory(id);
    if (target != null) {
      final t = target;
      // Episode lain dari anime yang sama yang masih ada di HP (terbaru).
      final remaining = _store.latestHistoryForMovie(t.movieId);
      _sync((repo, uid) =>
          repo.syncHistoryRemoved(uid, t.movieId, t.episodeId, remaining: remaining));
    }
  }

  // CATATAN: sama seperti Zenime, "hapus semua riwayat" hanya mereset data
  // lokal. Salinan server baru tertimpa saat ada progress nonton baru dan
  // tetap dijaga toggle privasi (history_public).
  Future<void> clearAllHistory() async {
    await _store.clearAllHistory();
    _sync((repo, uid) => repo.syncHistoryCleared(uid));
  }
}
