import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/anime_item.dart';
import '../../../data/models/cuplix_item.dart';
import '../../../data/models/episode_item.dart';
import '../../../data/models/media_item.dart';
import '../../../providers.dart';

/// Port DetailUiState. selectedTab: 0 = Ringkasan, 1 = Daftar Episode,
/// 2 = Media & Cuplix.
class DetailUiState {
  const DetailUiState({
    this.anime,
    this.episodes = const [],
    this.covers = const [],
    this.posters = const [],
    this.cuplix = const [],
    this.episodeSearch = '',
    this.selectedTab = 0,
    this.isLoading = false,
    this.isLoadingEpisodes = false,
    this.error,
  });

  final AnimeItem? anime;
  final List<EpisodeItem> episodes;
  final List<MediaGalleryItem> covers;
  final List<MediaGalleryItem> posters;
  final List<CuplixItem> cuplix;
  final String episodeSearch;
  final int selectedTab;
  final bool isLoading;
  final bool isLoadingEpisodes;
  final String? error;

  /// [error] berupa fungsi supaya bisa mengisi null secara eksplisit.
  DetailUiState copyWith({
    AnimeItem? anime,
    List<EpisodeItem>? episodes,
    List<MediaGalleryItem>? covers,
    List<MediaGalleryItem>? posters,
    List<CuplixItem>? cuplix,
    String? episodeSearch,
    int? selectedTab,
    bool? isLoading,
    bool? isLoadingEpisodes,
    String? Function()? error,
  }) {
    return DetailUiState(
      anime: anime ?? this.anime,
      episodes: episodes ?? this.episodes,
      covers: covers ?? this.covers,
      posters: posters ?? this.posters,
      cuplix: cuplix ?? this.cuplix,
      episodeSearch: episodeSearch ?? this.episodeSearch,
      selectedTab: selectedTab ?? this.selectedTab,
      isLoading: isLoading ?? this.isLoading,
      isLoadingEpisodes: isLoadingEpisodes ?? this.isLoadingEpisodes,
      error: error != null ? error() : this.error,
    );
  }
}

/// Port DetailViewModel.
class DetailController extends AutoDisposeFamilyNotifier<DetailUiState, String> {
  bool _alive = true;
  int _episodeRequest = 0;

  String get movieId => arg;

  @override
  DetailUiState build(String arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future.microtask(() {
      loadDetail();
      loadEpisodes();
      _loadGallery();
    });
    return const DetailUiState(isLoading: true);
  }

  void _update(DetailUiState Function(DetailUiState s) f) {
    if (_alive) state = f(state);
  }

  void setTab(int index) => _update((s) => s.copyWith(selectedTab: index));

  void onEpisodeSearchChange(String query) {
    _update((s) => s.copyWith(episodeSearch: query));
    loadEpisodes(query);
  }

  Future<void> loadDetail() async {
    _update((s) => s.copyWith(isLoading: true, error: () => null));
    try {
      final anime = await ref.read(repositoryProvider).getMovieDetail(movieId);
      _update((s) => s.copyWith(anime: anime, isLoading: false));
    } catch (e) {
      final msg = errorMessage(e, 'Gagal memuat detail anime');
      _update((s) => s.copyWith(error: () => msg, isLoading: false));
    }
  }

  Future<void> loadEpisodes([String search = '']) async {
    final request = ++_episodeRequest;
    _update((s) => s.copyWith(isLoadingEpisodes: true));
    try {
      final list = await ref
          .read(repositoryProvider)
          .getMovieEpisodes(movieId, page: 0, search: search);
      // Abaikan hasil lama kalau ada pencarian yang lebih baru
      if (request != _episodeRequest) return;
      _update((s) => s.copyWith(episodes: list, isLoadingEpisodes: false));
    } catch (_) {
      if (request != _episodeRequest) return;
      _update((s) => s.copyWith(isLoadingEpisodes: false));
    }
  }

  Future<T> _orDefault<T>(Future<T> Function() f, T fallback) async {
    try {
      return await f();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _loadGallery() async {
    final repo = ref.read(repositoryProvider);
    final covers = await _orDefault<List<MediaGalleryItem>>(
        () => repo.getMovieCovers(movieId), const []);
    final posters = await _orDefault<List<MediaGalleryItem>>(
        () => repo.getMoviePosters(movieId), const []);
    final cuplix =
        await _orDefault<List<CuplixItem>>(() => repo.getMovieCuplix(movieId), const []);
    _update((s) => s.copyWith(covers: covers, posters: posters, cuplix: cuplix));
  }

  Future<void> toggleFavorite() async {
    final anime = state.anime;
    if (anime == null) return;
    await ref.read(repositoryProvider).toggleFavorite(anime);
  }
}

final detailControllerProvider = NotifierProvider.autoDispose
    .family<DetailController, DetailUiState, String>(DetailController.new);
