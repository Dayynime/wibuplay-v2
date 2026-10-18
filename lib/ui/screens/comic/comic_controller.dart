import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/comic/comic_providers.dart';
import '../../../data/comic/comic_source.dart';
import '../../../data/models/comic_models.dart';
import '../../../data/repository/comic_repository.dart';

/// State list komik yang bisa "Muat Lebih Banyak": dipakai buat tab aktif
/// maupun mode Search/Genre. `hasNextPage` ikut field di tiap response.
class ComicListState {
  const ComicListState({
    this.items = const [],
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.hasNextPage = false,
    this.currentPage = 1,
    this.errorMessage,
  });

  final List<ComicListItem> items;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final bool hasNextPage;
  final int currentPage;
  final String? errorMessage;

  bool get isEmpty => !isInitialLoading && errorMessage == null && items.isEmpty;

  ComicListState copyWith({bool? isLoadingMore}) => ComicListState(
        items: items,
        isInitialLoading: isInitialLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasNextPage: hasNextPage,
        currentPage: currentPage,
        errorMessage: errorMessage,
      );
}

class ComicUiState {
  const ComicUiState({
    required this.source,
    required this.tabs,
    required this.selectedTab,
    this.list = const ComicListState(),
    this.genres = const [],
    this.query = '',
    this.selectedGenre,
    // Dipakai bareng buat mode search DAN filter genre.
    this.filter = const ComicListState(isInitialLoading: false),
  });

  final ComicSourceId source;
  final List<ComicTab> tabs;
  final String selectedTab;
  final ComicListState list;
  final List<ComicGenreItem> genres;
  final String query;
  final ComicGenreItem? selectedGenre;
  final ComicListState filter;

  bool get isFiltering => query.trim().isNotEmpty || selectedGenre != null;

  ComicUiState copyWith({
    ComicSourceId? source,
    List<ComicTab>? tabs,
    String? selectedTab,
    ComicListState? list,
    List<ComicGenreItem>? genres,
    String? query,
    ComicGenreItem? Function()? selectedGenre,
    ComicListState? filter,
  }) {
    return ComicUiState(
      source: source ?? this.source,
      tabs: tabs ?? this.tabs,
      selectedTab: selectedTab ?? this.selectedTab,
      list: list ?? this.list,
      genres: genres ?? this.genres,
      query: query ?? this.query,
      selectedGenre: selectedGenre != null ? selectedGenre() : this.selectedGenre,
      filter: filter ?? this.filter,
    );
  }
}

/// Port ComicViewModel.kt.
class ComicController extends Notifier<ComicUiState> {
  bool _alive = true;
  Timer? _searchTimer;

  // Setara Job.cancel(): hasil request lama dibuang kalau token sudah berganti.
  int _tabToken = 0;
  int _genreToken = 0;
  int _filterToken = 0;

  ComicRepository get _repo => ref.read(comicRepositoryProvider);

  /// Sumber yang tersedia, urutannya ikut comicRepositoryProvider.
  List<ComicSourceId> get sources =>
      _repo.availableSources.map((s) => s.id).toList();

  @override
  ComicUiState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _searchTimer?.cancel();
    });
    final first = sources.first;
    final tabs = _repo.tabsOf(first);
    Future.microtask(() {
      loadTab();
      _loadGenres();
    });
    return ComicUiState(source: first, tabs: tabs, selectedTab: tabs.first.id);
  }

  void _update(ComicUiState Function(ComicUiState s) f) {
    if (_alive) state = f(state);
  }

  // ---------------------------------------------------------------- sumber & tab

  void selectSource(ComicSourceId source) {
    if (source == state.source) return;
    _searchTimer?.cancel();
    _filterToken++;
    final tabs = _repo.tabsOf(source);
    state = ComicUiState(
      source: source,
      tabs: tabs,
      selectedTab: tabs.first.id,
    );
    loadTab();
    _loadGenres();
  }

  void selectTab(String tabId) {
    if (tabId == state.selectedTab) return;
    state = state.copyWith(selectedTab: tabId);
    loadTab();
  }

  /// [silent] = tarik-untuk-refresh: daftar lama tetap tampil, tanpa shimmer.
  Future<void> loadTab({bool forceRefresh = false, bool silent = false}) async {
    final token = ++_tabToken;
    final source = state.source;
    final tab = state.selectedTab;
    if (!silent) {
      _update((s) => s.copyWith(list: const ComicListState(isInitialLoading: true)));
    }
    try {
      final res = await _repo.browse(source, tab, page: 1, forceRefresh: forceRefresh);
      if (token != _tabToken) return;
      _update((s) => s.copyWith(list: _firstPage(res)));
    } catch (e) {
      if (token != _tabToken) return;
      if (silent && state.list.items.isNotEmpty) return;
      _update((s) => s.copyWith(
            list: ComicListState(
              isInitialLoading: false,
              errorMessage: errorMessage(e, 'Gagal memuat komik.'),
            ),
          ));
    }
  }

  Future<void> loadMoreTab() async {
    final current = state.list;
    if (current.isLoadingMore || !current.hasNextPage) return;
    final token = _tabToken;
    final source = state.source;
    final tab = state.selectedTab;
    final nextPage = current.currentPage + 1;
    _update((s) => s.copyWith(list: current.copyWith(isLoadingMore: true)));
    try {
      final res = await _repo.browse(source, tab, page: nextPage);
      if (token != _tabToken) return;
      _update((s) => s.copyWith(list: _mergeNext(current, res, nextPage)));
    } catch (_) {
      // Gagal load more: diam saja, user bisa coba lagi lewat tombol.
      if (token != _tabToken) return;
      _update((s) => s.copyWith(list: current.copyWith(isLoadingMore: false)));
    }
  }

  Future<void> _loadGenres() async {
    final token = ++_genreToken;
    final source = state.source;
    _update((s) => s.copyWith(genres: const []));
    try {
      final list = await _repo.getGenres(source);
      if (token != _genreToken) return;
      _update((s) => s.copyWith(genres: list));
    } catch (_) {
      // Gagal = chip genre tidak tampil.
    }
  }

  // ---------------------------------------------------------------- search & genre

  void onSearchQueryChange(String query) {
    _searchTimer?.cancel();
    _filterToken++;
    state = state.copyWith(query: query);
    if (query.trim().isEmpty) {
      _restoreFilterAfterQueryCleared();
      return;
    }
    // Langsung tampilkan shimmer, bukan "tidak ditemukan" selama debounce.
    state = state.copyWith(filter: const ComicListState(isInitialLoading: true));
    // Debounce 400 ms: jangan menembak API tiap ketikan.
    _searchTimer = Timer(const Duration(milliseconds: 400), _runSearch);
  }

  void clearSearch() {
    _searchTimer?.cancel();
    _filterToken++;
    state = state.copyWith(query: '');
    _restoreFilterAfterQueryCleared();
  }

  // Query kosong: kalau masih ada genre terpilih tampilkan genre itu lagi,
  // kalau tidak, kosongkan mode filter.
  void _restoreFilterAfterQueryCleared() {
    final genre = state.selectedGenre;
    if (genre != null) {
      selectGenre(genre);
    } else {
      state = state.copyWith(filter: const ComicListState(isInitialLoading: false));
    }
  }

  Future<void> _runSearch() async {
    final query = state.query;
    if (query.trim().isEmpty) return;
    final token = ++_filterToken;
    final source = state.source;
    _update((s) => s.copyWith(filter: const ComicListState(isInitialLoading: true)));
    try {
      final res = await _repo.search(source, query, page: 1);
      if (token != _filterToken) return;
      _update((s) => s.copyWith(filter: _firstPage(res)));
    } catch (e) {
      if (token != _filterToken) return;
      _update((s) => s.copyWith(
            filter: ComicListState(
              isInitialLoading: false,
              errorMessage: errorMessage(e, 'Gagal mencari komik.'),
            ),
          ));
    }
  }

  Future<void> selectGenre(ComicGenreItem? genre) async {
    _searchTimer?.cancel();
    final token = ++_filterToken;
    state = state.copyWith(query: '', selectedGenre: () => genre);
    if (genre == null) {
      state = state.copyWith(filter: const ComicListState(isInitialLoading: false));
      return;
    }
    final source = state.source;
    _update((s) => s.copyWith(filter: const ComicListState(isInitialLoading: true)));
    try {
      final res = await _repo.getByGenre(source, genre.slug, page: 1);
      if (token != _filterToken) return;
      _update((s) => s.copyWith(filter: _firstPage(res)));
    } catch (e) {
      if (token != _filterToken) return;
      _update((s) => s.copyWith(
            filter: ComicListState(
              isInitialLoading: false,
              errorMessage: errorMessage(e, 'Gagal memuat komik.'),
            ),
          ));
    }
  }

  void retryFilter() {
    if (state.query.trim().isNotEmpty) {
      _runSearch();
    } else if (state.selectedGenre != null) {
      selectGenre(state.selectedGenre);
    }
  }

  // Load more buat mode filter: lanjut ke yang lagi aktif (search kalau query
  // terisi, genre kalau lagi memilih genre).
  Future<void> loadMoreFilter() async {
    final current = state.filter;
    if (current.isLoadingMore || !current.hasNextPage) return;
    final query = state.query;
    final genre = state.selectedGenre;
    if (query.trim().isEmpty && genre == null) return;
    final token = _filterToken;
    final source = state.source;
    final nextPage = current.currentPage + 1;
    _update((s) => s.copyWith(filter: current.copyWith(isLoadingMore: true)));
    try {
      final res = query.trim().isNotEmpty
          ? await _repo.search(source, query, page: nextPage)
          : await _repo.getByGenre(source, genre!.slug, page: nextPage);
      if (token != _filterToken) return;
      _update((s) => s.copyWith(filter: _mergeNext(current, res, nextPage)));
    } catch (_) {
      if (token != _filterToken) return;
      _update((s) => s.copyWith(filter: current.copyWith(isLoadingMore: false)));
    }
  }

  // ---------------------------------------------------------------- mapper

  ComicListState _firstPage(ComicListResponse res) => ComicListState(
        items: res.komikList ?? const [],
        isInitialLoading: false,
        hasNextPage: res.hasNextPage ?? false,
        currentPage: res.currentPage ?? 1,
      );

  ComicListState _mergeNext(
    ComicListState current,
    ComicListResponse res,
    int requestedPage,
  ) {
    final have = current.items.map((e) => e.slug).toSet();
    final fresh = (res.komikList ?? const <ComicListItem>[])
        .where((e) => have.add(e.slug))
        .toList();
    // Halaman baru kosong / tidak menambah apa-apa = anggap sudah habis,
    // supaya tidak loop tanpa akhir.
    final stillHasNext = (res.hasNextPage ?? false) && fresh.isNotEmpty;
    return ComicListState(
      items: [...current.items, ...fresh],
      isInitialLoading: false,
      isLoadingMore: false,
      hasNextPage: stillHasNext,
      currentPage: res.currentPage ?? requestedPage,
    );
  }
}

final comicControllerProvider =
    NotifierProvider<ComicController, ComicUiState>(ComicController.new);
