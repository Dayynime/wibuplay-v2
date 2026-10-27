import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/anichin_models.dart';
import '../../../data/repository/anichin_repository.dart';
import '../../../providers.dart';

enum DonghuaTab {
  latest('Terbaru'),
  ongoing('Ongoing'),
  all('Semua');

  const DonghuaTab(this.label);
  final String label;
}

/// State grid donghua yang bisa "Muat Lebih Banyak".
class DonghuaGridState {
  const DonghuaGridState({
    this.items = const [],
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.hasNextPage = false,
    this.page = 1,
    this.errorMessage,
  });

  final List<AnichinCard> items;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final bool hasNextPage;
  final int page;
  final String? errorMessage;

  bool get isEmpty => !isInitialLoading && errorMessage == null && items.isEmpty;

  DonghuaGridState copyWith({bool? isLoadingMore}) => DonghuaGridState(
        items: items,
        isInitialLoading: isInitialLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasNextPage: hasNextPage,
        page: page,
        errorMessage: errorMessage,
      );
}

class DonghuaHomeState {
  const DonghuaHomeState({
    this.sections = const [],
    this.isLoading = true,
    this.errorMessage,
  });

  final List<AnichinHomeSection> sections;
  final bool isLoading;
  final String? errorMessage;

  bool get isEmpty => !isLoading && errorMessage == null && sections.isEmpty;
}

class DonghuaUiState {
  const DonghuaUiState({
    this.home = const DonghuaHomeState(),
    this.ongoing = const DonghuaGridState(),
    this.all = const DonghuaGridState(),
    // Dipakai bareng buat mode search DAN filter genre (cuma satu aktif sekali waktu).
    this.filter = const DonghuaGridState(isInitialLoading: false),
    this.genres = const [],
    this.query = '',
    this.selectedGenre,
  });

  final DonghuaHomeState home;
  final DonghuaGridState ongoing;
  final DonghuaGridState all;
  final DonghuaGridState filter;
  final List<AnichinGenre> genres;
  final String query;
  final AnichinGenre? selectedGenre;

  bool get isFiltering => query.trim().isNotEmpty || selectedGenre != null;

  DonghuaUiState copyWith({
    DonghuaHomeState? home,
    DonghuaGridState? ongoing,
    DonghuaGridState? all,
    DonghuaGridState? filter,
    List<AnichinGenre>? genres,
    String? query,
    AnichinGenre? Function()? selectedGenre,
  }) {
    return DonghuaUiState(
      home: home ?? this.home,
      ongoing: ongoing ?? this.ongoing,
      all: all ?? this.all,
      filter: filter ?? this.filter,
      genres: genres ?? this.genres,
      query: query ?? this.query,
      selectedGenre: selectedGenre != null ? selectedGenre() : this.selectedGenre,
    );
  }
}

enum _Slot { ongoing, all, filter }

/// Port DonghuaViewModel.kt.
class DonghuaController extends AutoDisposeNotifier<DonghuaUiState> {
  bool _alive = true;
  Timer? _searchTimer;
  int _filterRequest = 0;
  bool _ongoingStarted = false;
  bool _allStarted = false;

  @override
  DonghuaUiState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _searchTimer?.cancel();
    });
    Future.microtask(() {
      loadHome();
      _loadGenres();
    });
    return const DonghuaUiState();
  }

  AnichinRepository get _repo => ref.read(anichinRepositoryProvider);

  void _update(DonghuaUiState Function(DonghuaUiState s) f) {
    if (_alive) state = f(state);
  }

  List<AnichinCard> _validCards(List<AnichinCard> list) {
    final seen = <String?>{};
    return list
        .where((c) => (c.slug ?? '').isNotEmpty && c.slug != 'unknown')
        .where((c) => seen.add(c.slug))
        .toList();
  }

  // ---------- Beranda (GET /) ----------

  Future<void> loadHome() async {
    _update((s) => s.copyWith(home: const DonghuaHomeState(isLoading: true)));
    try {
      final res = await _repo.getHome();
      final sections = res.results
          .map((sec) => sec.withCards(_validCards(sec.cards)))
          .where((sec) => sec.cards.isNotEmpty)
          .toList();
      _update((s) => s.copyWith(
            home: DonghuaHomeState(sections: sections, isLoading: false),
          ));
    } catch (e) {
      final msg = errorMessage(e, 'Gagal memuat donghua.');
      _update((s) => s.copyWith(
            home: DonghuaHomeState(isLoading: false, errorMessage: msg),
          ));
    }
  }

  // ---------- Tab Ongoing / Semua (GET /anime) ----------

  void onTabSelected(DonghuaTab tab) {
    switch (tab) {
      case DonghuaTab.ongoing:
        if (!_ongoingStarted) {
          _ongoingStarted = true;
          loadOngoing(1);
        }
      case DonghuaTab.all:
        if (!_allStarted) {
          _allStarted = true;
          loadAll(1);
        }
      case DonghuaTab.latest:
        break;
    }
  }

  Future<void> loadOngoing(int page) => _loadPaged(
        _Slot.ongoing,
        page,
        (p) => _repo.getAnimeList(
          status: 'Ongoing',
          order: 'update',
          extra: p > 1 ? {'page': '$p'} : const {},
        ),
      );

  Future<void> loadAll(int page) => _loadPaged(
        _Slot.all,
        page,
        (p) => _repo.getAnimeList(extra: p > 1 ? {'page': '$p'} : const {}),
      );

  void loadMoreOngoing() => _loadMore(_Slot.ongoing, loadOngoing);
  void loadMoreAll() => _loadMore(_Slot.all, loadAll);

  // ---------- Genre (GET /genres, /genre/{slug}) ----------

  Future<void> _loadGenres() async {
    try {
      final list = await _repo.getGenres();
      _update((s) => s.copyWith(genres: list));
    } catch (_) {
      // Genre opsional: gagal = chip genre tidak tampil.
    }
  }

  void selectGenre(AnichinGenre? genre) {
    _searchTimer?.cancel();
    _update((s) => s.copyWith(selectedGenre: () => genre));
    if (genre == null) {
      if (state.query.trim().isEmpty) {
        _filterRequest++;
        _update((s) => s.copyWith(filter: const DonghuaGridState(isInitialLoading: false)));
      }
      return;
    }
    _update((s) => s.copyWith(query: ''));
    _loadGenrePage(1);
  }

  Future<void> _loadGenrePage(int page) {
    final slug = state.selectedGenre?.slug;
    if (slug == null) return Future.value();
    return _loadPaged(_Slot.filter, page, (p) => _repo.getByGenre(slug, page: p));
  }

  void loadMoreFilter() {
    if (state.selectedGenre != null) _loadMore(_Slot.filter, _loadGenrePage);
    // Hasil search (GET /search/{query}) tidak dipaginasi, jadi tidak ada "muat lebih banyak".
  }

  // ---------- Search (GET /search/{query}) ----------

  void onSearchQueryChange(String query) {
    _update((s) => s.copyWith(query: query));
    _searchTimer?.cancel();
    if (query.trim().isEmpty) {
      if (state.selectedGenre == null) {
        _filterRequest++;
        _update((s) => s.copyWith(filter: const DonghuaGridState(isInitialLoading: false)));
      }
      return;
    }
    _update((s) => s.copyWith(selectedGenre: () => null));
    // Debounce 500ms: endpoint scraping lumayan berat.
    _searchTimer = Timer(const Duration(milliseconds: 500), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final req = ++_filterRequest;
    _update((s) => s.copyWith(filter: const DonghuaGridState(isInitialLoading: true)));
    try {
      final res = await _repo.search(query);
      if (req != _filterRequest) return;
      _update((s) => s.copyWith(
            filter: DonghuaGridState(
              items: _validCards(res.results),
              isInitialLoading: false,
              hasNextPage: false,
            ),
          ));
    } catch (e) {
      if (req != _filterRequest) return;
      final msg = errorMessage(e, 'Gagal mencari donghua.');
      _update((s) => s.copyWith(
            filter: DonghuaGridState(isInitialLoading: false, errorMessage: msg),
          ));
    }
  }

  void clearSearch() => onSearchQueryChange('');

  void retryFilter() {
    if (state.query.trim().isNotEmpty) {
      _runSearch(state.query);
    } else {
      selectGenre(state.selectedGenre);
    }
  }

  // ---------- helper paging ----------

  DonghuaGridState _grid(_Slot slot) => switch (slot) {
        _Slot.ongoing => state.ongoing,
        _Slot.all => state.all,
        _Slot.filter => state.filter,
      };

  void _setGrid(_Slot slot, DonghuaGridState g) {
    _update((s) => switch (slot) {
          _Slot.ongoing => s.copyWith(ongoing: g),
          _Slot.all => s.copyWith(all: g),
          _Slot.filter => s.copyWith(filter: g),
        });
  }

  void _loadMore(_Slot slot, Future<void> Function(int page) load) {
    final current = _grid(slot);
    if (current.isLoadingMore || !current.hasNextPage) return;
    load(current.page + 1);
  }

  Future<void> _loadPaged(
    _Slot slot,
    int page,
    Future<AnichinListResponse> Function(int page) fetch,
  ) async {
    final req = slot == _Slot.filter ? ++_filterRequest : 0;
    final before = _grid(slot);
    _setGrid(
      slot,
      page == 1
          ? const DonghuaGridState(isInitialLoading: true)
          : before.copyWith(isLoadingMore: true),
    );
    try {
      final res = await fetch(page);
      if (slot == _Slot.filter && req != _filterRequest) return;
      final incoming = _validCards(res.results);
      final existing = page == 1 ? <AnichinCard>[] : before.items;
      final known = existing.map((c) => c.slug).toSet();
      final fresh = incoming.where((c) => !known.contains(c.slug)).toList();
      _setGrid(
        slot,
        DonghuaGridState(
          items: [...existing, ...fresh],
          isInitialLoading: false,
          isLoadingMore: false,
          // Berhenti kalau halaman baru tidak menambah item sama sekali.
          hasNextPage: fresh.isNotEmpty,
          page: page,
        ),
      );
    } catch (e) {
      if (slot == _Slot.filter && req != _filterRequest) return;
      _setGrid(
        slot,
        page == 1
            ? DonghuaGridState(
                isInitialLoading: false,
                errorMessage: errorMessage(e, 'Gagal memuat donghua.'),
              )
            : before.copyWith(isLoadingMore: false),
      );
    }
  }
}

final donghuaControllerProvider =
    NotifierProvider.autoDispose<DonghuaController, DonghuaUiState>(DonghuaController.new);
