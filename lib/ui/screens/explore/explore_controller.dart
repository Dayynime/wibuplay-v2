import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/anime_item.dart';
import '../../../data/models/genre_item.dart';
import '../../../providers.dart';

/// Port ExploreUiState. selectedSort: "views" atau "alphabet".
class ExploreUiState {
  const ExploreUiState({
    this.query = '',
    this.selectedGenreId,
    this.selectedType,
    this.selectedYear,
    this.selectedStatus,
    this.selectedStudio,
    this.selectedSort = 'views',
    this.genres = const [],
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isEndOfList = false,
    this.error,
    this.currentPage = 0,
  });

  final String query;
  final String? selectedGenreId;
  final String? selectedType;
  final String? selectedYear;
  final String? selectedStatus;
  final String? selectedStudio;
  final String selectedSort;
  final List<GenreItem> genres;
  final List<AnimeItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isEndOfList;
  final String? error;
  final int currentPage;

  bool get hasActiveFilter =>
      selectedGenreId != null ||
      selectedType != null ||
      selectedYear != null ||
      selectedStatus != null ||
      selectedSort != 'views';

  /// Field nullable memakai fungsi supaya bisa diisi null secara eksplisit.
  ExploreUiState copyWith({
    String? query,
    String? Function()? selectedGenreId,
    String? Function()? selectedType,
    String? Function()? selectedYear,
    String? Function()? selectedStatus,
    String? Function()? selectedStudio,
    String? selectedSort,
    List<GenreItem>? genres,
    List<AnimeItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isEndOfList,
    String? Function()? error,
    int? currentPage,
  }) {
    return ExploreUiState(
      query: query ?? this.query,
      selectedGenreId: selectedGenreId != null ? selectedGenreId() : this.selectedGenreId,
      selectedType: selectedType != null ? selectedType() : this.selectedType,
      selectedYear: selectedYear != null ? selectedYear() : this.selectedYear,
      selectedStatus: selectedStatus != null ? selectedStatus() : this.selectedStatus,
      selectedStudio: selectedStudio != null ? selectedStudio() : this.selectedStudio,
      selectedSort: selectedSort ?? this.selectedSort,
      genres: genres ?? this.genres,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isEndOfList: isEndOfList ?? this.isEndOfList,
      error: error != null ? error() : this.error,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

/// Port ExploreViewModel.
class ExploreController extends Notifier<ExploreUiState> {
  Timer? _searchTimer;
  bool _alive = true;

  /// Naik setiap kali muat awal dimulai; hasil dari generasi lama dibuang.
  int _generation = 0;

  @override
  ExploreUiState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _searchTimer?.cancel();
    });
    Future.microtask(() {
      _loadGenres();
      _loadAnime(page: 0, isInitial: true);
    });
    return const ExploreUiState();
  }

  void _update(ExploreUiState Function(ExploreUiState s) f) {
    if (_alive) state = f(state);
  }

  Future<void> _loadGenres() async {
    try {
      final genres = await ref.read(repositoryProvider).getGenres();
      _update((s) => s.copyWith(genres: genres));
    } catch (_) {}
  }

  void onQueryChange(String newQuery) {
    _update((s) => s.copyWith(query: newQuery));
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 400), () {
      _loadAnime(page: 0, isInitial: true);
    });
  }

  /// Filter bisa dikombinasikan; tidak ada lagi yang saling mereset.
  void onGenreSelected(String? genreId) {
    final newGenre = state.selectedGenreId == genreId ? null : genreId;
    _update((s) => s.copyWith(selectedGenreId: () => newGenre));
    _loadAnime(page: 0, isInitial: true);
  }

  void onSortSelected(String sort) {
    if (state.selectedSort == sort) return;
    _update((s) => s.copyWith(selectedSort: sort));
    _loadAnime(page: 0, isInitial: true);
  }

  /// Terapkan semua pilihan dari sheet filter sekaligus (satu kali muat).
  void applyFilters({
    String? genreId,
    String? status,
    String? type,
    String? year,
    required String sort,
  }) {
    _update((s) => s.copyWith(
          selectedGenreId: () => genreId,
          selectedStatus: () => status,
          selectedType: () => type,
          selectedYear: () => year,
          selectedSort: sort,
        ));
    _loadAnime(page: 0, isInitial: true);
  }

  /// Reset filter saja; kata kunci pencarian dibiarkan.
  void clearFilters() {
    _update((s) => s.copyWith(
          selectedGenreId: () => null,
          selectedStatus: () => null,
          selectedType: () => null,
          selectedYear: () => null,
          selectedStudio: () => null,
          selectedSort: 'views',
        ));
    _loadAnime(page: 0, isInitial: true);
  }

  void resetFilters() {
    _searchTimer?.cancel();
    _update((s) => s.copyWith(
          query: '',
          selectedGenreId: () => null,
          selectedType: () => null,
          selectedYear: () => null,
          selectedStatus: () => null,
          selectedStudio: () => null,
          selectedSort: 'views',
        ));
    _loadAnime(page: 0, isInitial: true);
  }

  void loadNextPage() {
    final s = state;
    if (s.isLoading || s.isLoadingMore || s.isEndOfList) return;
    _loadAnime(page: s.currentPage + 1, isInitial: false);
  }

  /// Dipakai tombol "Coba Lagi": ulangi muat awal.
  void retry() => _loadAnime(page: 0, isInitial: true);

  Future<void> _loadAnime({required int page, required bool isInitial}) async {
    final snap = state;
    final gen = isInitial ? ++_generation : _generation;
    _update((s) => s.copyWith(
          isLoading: isInitial,
          isLoadingMore: !isInitial,
          error: () => null,
        ));

    try {
      String? genreName;
      for (final g in snap.genres) {
        if (g.id == snap.selectedGenreId) genreName = g.name;
      }
      final res = await ref.read(repositoryProvider).explore(
            keyword: snap.query,
            genreId: snap.selectedGenreId,
            genreName: genreName,
            type: snap.selectedType,
            year: snap.selectedYear,
            status: snap.selectedStatus,
            studio: snap.selectedStudio,
            sort: snap.selectedSort,
            page: page,
          );
      if (gen != _generation) return;
      _update((cur) {
        // Buang duplikat kalau server mengulang isi yang sama antar halaman.
        final known = isInitial ? <String?>{} : cur.items.map((e) => e.id).toSet();
        final fresh = res.items.where((e) => known.add(e.id)).toList();
        final combined = isInitial ? fresh : [...cur.items, ...fresh];
        return cur.copyWith(
          items: combined,
          currentPage: res.page,
          isEndOfList: !res.hasMore || (res.items.isNotEmpty && fresh.isEmpty),
          isLoading: false,
          isLoadingMore: false,
        );
      });
    } catch (e) {
      if (gen != _generation) return;
      final msg = errorMessage(e, 'Gagal memuat anime');
      _update((cur) => cur.copyWith(
            isLoading: false,
            isLoadingMore: false,
            error: isInitial ? () => msg : () => null,
          ));
    }
  }
}

final exploreControllerProvider =
    NotifierProvider<ExploreController, ExploreUiState>(ExploreController.new);
