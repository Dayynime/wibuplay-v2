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
      selectedGenreId != null || selectedType != null || selectedYear != null;

  /// Field nullable memakai fungsi supaya bisa diisi null secara eksplisit.
  ExploreUiState copyWith({
    String? query,
    String? Function()? selectedGenreId,
    String? Function()? selectedType,
    String? Function()? selectedYear,
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

  void onGenreSelected(String? genreId) {
    final newGenre = state.selectedGenreId == genreId ? null : genreId;
    _update((s) => s.copyWith(
          selectedGenreId: () => newGenre,
          selectedType: () => null,
          selectedYear: () => null,
        ));
    _loadAnime(page: 0, isInitial: true);
  }

  void onTypeSelected(String? type) {
    final newType = state.selectedType == type ? null : type;
    _update((s) => s.copyWith(
          selectedType: () => newType,
          selectedGenreId: () => null,
          selectedYear: () => null,
        ));
    _loadAnime(page: 0, isInitial: true);
  }

  void onSortSelected(String sort) {
    if (state.selectedSort == sort) return;
    _update((s) => s.copyWith(selectedSort: sort));
    _loadAnime(page: 0, isInitial: true);
  }

  void onYearSelected(String? year) {
    final newYear = state.selectedYear == year ? null : year;
    _update((s) => s.copyWith(
          selectedYear: () => newYear,
          selectedGenreId: () => null,
          selectedType: () => null,
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
      final newItems = await ref.read(repositoryProvider).explore(
            keyword: snap.query,
            genreId: snap.selectedGenreId,
            type: snap.selectedType,
            year: snap.selectedYear,
            studio: snap.selectedStudio,
            sort: snap.selectedSort,
            page: page,
          );
      if (gen != _generation) return;
      _update((cur) {
        final combined = isInitial ? newItems : [...cur.items, ...newItems];
        return cur.copyWith(
          items: combined,
          currentPage: page,
          isEndOfList: newItems.isEmpty,
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
