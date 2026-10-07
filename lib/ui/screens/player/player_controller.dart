import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/anime_item.dart';
import '../../../data/models/episode_item.dart';
import '../../../data/models/stream_data.dart';
import '../../../providers.dart';

/// Port PlayerUiState.
class PlayerUiState {
  const PlayerUiState({
    this.movieId = '',
    this.currentEpisodeId = '',
    this.anime,
    this.episodes = const [],
    this.episodesLoaded = false,
    this.streamData,
    this.selectedServer,
    this.recommended = const [],
    this.isLoadingStream = false,
    this.streamError,
    this.isFullscreen = false,
    this.autoNextCountdown,
    this.resumePositionMs = 0,
  });

  final String movieId;
  final String currentEpisodeId;
  final AnimeItem? anime;
  final List<EpisodeItem> episodes;

  /// True setelah daftar episode selesai dimuat (sukses ATAU gagal).
  final bool episodesLoaded;
  final StreamData? streamData;
  final StreamServer? selectedServer;
  final List<AnimeItem> recommended;
  final bool isLoadingStream;
  final String? streamError;
  final bool isFullscreen;

  /// null kalau tidak sedang menghitung mundur.
  final int? autoNextCountdown;
  final int resumePositionMs;

  /// Field nullable memakai fungsi supaya bisa diisi null secara eksplisit.
  PlayerUiState copyWith({
    String? currentEpisodeId,
    AnimeItem? anime,
    List<EpisodeItem>? episodes,
    bool? episodesLoaded,
    StreamData? streamData,
    StreamServer? Function()? selectedServer,
    List<AnimeItem>? recommended,
    bool? isLoadingStream,
    String? Function()? streamError,
    bool? isFullscreen,
    int? Function()? autoNextCountdown,
    int? resumePositionMs,
  }) {
    return PlayerUiState(
      movieId: movieId,
      currentEpisodeId: currentEpisodeId ?? this.currentEpisodeId,
      anime: anime ?? this.anime,
      episodes: episodes ?? this.episodes,
      episodesLoaded: episodesLoaded ?? this.episodesLoaded,
      streamData: streamData ?? this.streamData,
      selectedServer: selectedServer != null ? selectedServer() : this.selectedServer,
      recommended: recommended ?? this.recommended,
      isLoadingStream: isLoadingStream ?? this.isLoadingStream,
      streamError: streamError != null ? streamError() : this.streamError,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      autoNextCountdown:
          autoNextCountdown != null ? autoNextCountdown() : this.autoNextCountdown,
      resumePositionMs: resumePositionMs ?? this.resumePositionMs,
    );
  }
}

/// Port PlayerViewModel. Argumen: (movieId, episodeId).
class PlayerController
    extends AutoDisposeFamilyNotifier<PlayerUiState, (String, String)> {
  bool _alive = true;
  int _countdownToken = 0;

  @override
  PlayerUiState build((String, String) arg) {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _countdownToken++;
    });
    final movieId = arg.$1;
    final episodeId = arg.$2;
    Future.microtask(() {
      _loadAnimeInfo();
      _loadEpisodes();
      _loadRecommendations();
      if (episodeId.trim().isNotEmpty) loadEpisodeStream(episodeId);
    });
    return PlayerUiState(movieId: movieId, currentEpisodeId: episodeId);
  }

  void _update(PlayerUiState Function(PlayerUiState s) f) {
    if (_alive) state = f(state);
  }

  Future<void> _loadAnimeInfo() async {
    try {
      final anime = await ref.read(repositoryProvider).getMovieDetail(state.movieId);
      _update((s) => s.copyWith(anime: anime));
    } catch (_) {}
  }

  Future<void> _loadEpisodes() async {
    try {
      final eps = await ref.read(repositoryProvider).getMovieEpisodes(state.movieId, page: 0);
      _update((s) => s.copyWith(episodes: eps, episodesLoaded: true));
      // Kalau episode awal kosong, putar episode pertama
      if (_alive && state.currentEpisodeId.trim().isEmpty && eps.isNotEmpty) {
        final id = eps.first.id;
        if (id != null) loadEpisodeStream(id);
      }
    } catch (_) {
      _update((s) => s.copyWith(episodesLoaded: true));
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final list = await ref.read(repositoryProvider).getHomeCategory('random', 0);
      _update((s) => s.copyWith(recommended: list.take(8).toList()));
    } catch (_) {}
  }

  Future<void> loadEpisodeStream(String episodeId) async {
    cancelAutoNext();
    _update((s) => s.copyWith(
          currentEpisodeId: episodeId,
          isLoadingStream: true,
          // Buang link episode sebelumnya supaya tidak ikut diputar kalau
          // episode baru ini ternyata terkunci / gagal dimuat.
          selectedServer: () => null,
          streamError: () => null,
        ));

    final repo = ref.read(repositoryProvider);
    // Posisi tersimpan untuk melanjutkan tontonan
    final resumeMs = repo.historyForEpisode(episodeId)?.playbackPositionMs ?? 0;

    // Episode yang sudah didownload (khusus Premium) diputar dari file lokal.
    final localServer = await _localServer(episodeId);

    try {
      final data = await repo.getEpisodeStream(episodeId);
      StreamServer? defaultServer;
      for (final s in data.server) {
        final link = s.link;
        if (link != null && link.trim().isNotEmpty) {
          defaultServer = s;
          break;
        }
      }
      // File offline jadi pilihan pertama (hemat kuota, tetap bisa ganti server).
      final merged = localServer == null
          ? data
          : StreamData(
              episode: data.episode,
              episodeNext: data.episodeNext,
              hasNextEpisode: data.hasNextEpisode,
              server: [localServer, ...data.server],
            );
      _update((s) => s.copyWith(
            streamData: merged,
            selectedServer: () => localServer ?? defaultServer,
            isLoadingStream: false,
            resumePositionMs: resumeMs,
          ));
    } catch (e) {
      if (localServer != null) {
        // Gagal ambil stream (kemungkinan offline) tapi file lokal ada:
        // putar dari file; next episode / ganti server disembunyikan.
        final dl = ref.read(localStoreProvider).downloadFor(episodeId);
        _update((s) => s.copyWith(
              streamData: StreamData(
                episode: EpisodeItem(
                  id: episodeId,
                  title: dl?.episodeTitle,
                  index: dl?.episodeIndex,
                ),
                server: [localServer],
              ),
              selectedServer: () => localServer,
              isLoadingStream: false,
              resumePositionMs: resumeMs,
            ));
        return;
      }
      final msg = errorMessage(e, 'Gagal memuat server video');
      _update((s) => s.copyWith(isLoadingStream: false, streamError: () => msg));
    }
  }

  /// Server "Offline" dari file hasil download, atau null kalau episode ini
  /// belum didownload / filenya sudah tidak ada di disk. Memutar file offline
  /// TIDAK butuh Premium (hanya memulai download yang khusus Premium).
  Future<StreamServer?> _localServer(String episodeId) async {
    try {
      final file = ref.read(episodeDownloadManagerProvider).localFileFor(episodeId);
      if (file == null) return null;
      return StreamServer(
        link: Uri.file(file.path).toString(),
        quality: 'Offline',
        type: 'offline',
        name: 'Offline',
      );
    } catch (_) {
      return null;
    }
  }

  void selectServer(StreamServer server) {
    _update((s) => s.copyWith(selectedServer: () => server, streamError: () => null));
  }

  void setFullscreen(bool fullscreen) {
    _update((s) => s.copyWith(isFullscreen: fullscreen));
  }

  Future<void> toggleFavorite() async {
    final anime = state.anime;
    if (anime == null) return;
    await ref.read(repositoryProvider).toggleFavorite(anime);
  }

  Future<void> saveProgress(int positionMs, int durationMs) async {
    final s = state;
    EpisodeItem? ep;
    for (final e in s.episodes) {
      if (e.id == s.currentEpisodeId) {
        ep = e;
        break;
      }
    }
    ep ??= s.streamData?.episode;
    final anime = s.anime;
    final dl = ref.read(localStoreProvider).downloadFor(s.currentEpisodeId);
    if (s.currentEpisodeId.trim().isNotEmpty && (anime != null || dl != null)) {
      await ref.read(repositoryProvider).saveWatchProgress(
            movieId: s.movieId,
            movieTitle: anime?.title ?? dl?.animeTitle ?? 'Anime',
            moviePoster: anime?.posterUrl ?? dl?.posterUrl ?? '',
            episodeId: s.currentEpisodeId,
            episodeIndex: ep?.index ?? '1',
            episodeTitle: ep?.title ?? 'Episode',
            playbackPositionMs: positionMs,
            durationMs: durationMs,
          );
    }
  }

  /// Hitung mundur 5 detik lalu putar episode berikutnya.
  Future<void> startAutoNextCountdown() async {
    final nextEp = state.streamData?.episodeNext;
    final hasNext = state.streamData?.hasNextEpisode == true || nextEp != null;
    if (!hasNext) return;

    final token = ++_countdownToken;
    for (var i = 5; i >= 1; i--) {
      if (!_alive || token != _countdownToken) return;
      _update((s) => s.copyWith(autoNextCountdown: () => i));
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!_alive || token != _countdownToken) return;
    _update((s) => s.copyWith(autoNextCountdown: () => null));

    final nextEpId = nextEp?.id ?? _findNextEpisodeIdInList();
    if (nextEpId != null && nextEpId.trim().isNotEmpty) {
      loadEpisodeStream(nextEpId);
    }
  }

  void cancelAutoNext() {
    _countdownToken++;
    if (_alive && state.autoNextCountdown != null) {
      state = state.copyWith(autoNextCountdown: () => null);
    }
  }

  /// Id episode berikutnya (dari data stream, fallback ke urutan daftar episode).
  String? get nextEpisodeId {
    final id = state.streamData?.episodeNext?.id;
    if (id != null && id.trim().isNotEmpty) return id;
    return _findNextEpisodeIdInList();
  }

  /// Id episode sebelumnya menurut urutan daftar episode.
  String? get previousEpisodeId {
    final list = state.episodes;
    final idx = list.indexWhere((e) => e.id == state.currentEpisodeId);
    if (idx > 0) return list[idx - 1].id;
    return null;
  }

  void playNext() {
    final id = nextEpisodeId;
    if (id != null && id.trim().isNotEmpty) loadEpisodeStream(id);
  }

  void playPrevious() {
    final id = previousEpisodeId;
    if (id != null && id.trim().isNotEmpty) loadEpisodeStream(id);
  }

  String? _findNextEpisodeIdInList() {
    final list = state.episodes;
    final idx = list.indexWhere((e) => e.id == state.currentEpisodeId);
    if (idx >= 0 && idx < list.length - 1) return list[idx + 1].id;
    return null;
  }
}

final playerControllerProvider = NotifierProvider.autoDispose
    .family<PlayerController, PlayerUiState, (String, String)>(PlayerController.new);
