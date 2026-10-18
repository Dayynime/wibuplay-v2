import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/cuplix_item.dart';
import '../../../data/models/stream_data.dart';
import '../../../providers.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Port CuplixUiState.
class CuplixUiState {
  const CuplixUiState({
    this.items = const [],
    this.currentIndex = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isEndOfFeed = false,
    this.error,
    this.likedIds = const <String>{},
    this.sort = 'scroll_likes',
  });

  final List<CuplixItem> items;
  final int currentIndex;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isEndOfFeed;
  final String? error;
  final Set<String> likedIds;

  /// scroll_likes | scroll_new | scroll_old. Kotlin selalu memakai scroll_likes.
  final String sort;

  /// Field nullable memakai fungsi supaya bisa diisi null secara eksplisit.
  CuplixUiState copyWith({
    List<CuplixItem>? items,
    int? currentIndex,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isEndOfFeed,
    String? Function()? error,
    Set<String>? likedIds,
    String? sort,
  }) {
    return CuplixUiState(
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isEndOfFeed: isEndOfFeed ?? this.isEndOfFeed,
      error: error != null ? error() : this.error,
      likedIds: likedIds ?? this.likedIds,
      sort: sort ?? this.sort,
    );
  }
}

/// Port CuplixViewModel.
class CuplixController extends Notifier<CuplixUiState> {
  bool _alive = true;

  /// Naik setiap kali muat awal dimulai; hasil dari generasi lama dibuang.
  int _generation = 0;

  final Set<String> _displayedIds = <String>{};
  Map<String, String> _cursors = const {};

  /// episodeId -> URL stream langsung.
  final Map<String, String> _streamUrlCache = {};

  /// Permintaan stream yang sedang berjalan, supaya prefetch dan resolve
  /// untuk episode yang sama tidak memanggil API dua kali.
  final Map<String, Future<String?>> _inflight = {};

  @override
  CuplixUiState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future.microtask(() => loadFeed(isInitial: true));
    return const CuplixUiState(isLoading: true);
  }

  void _update(CuplixUiState Function(CuplixUiState s) f) {
    if (_alive) state = f(state);
  }

  Future<void> loadFeed({bool isInitial = false}) async {
    if (!_alive) return;
    if (state.isEndOfFeed && !isInitial) return;
    // Beda dari Kotlin: tanpa penjaga ini, dua muat-lanjut bersamaan (geser cepat
    // dekat akhir list) membuat hasil kedua semuanya duplikat, lalu feed
    // ditandai habis padahal belum.
    if (!isInitial && (state.isLoading || state.isLoadingMore)) return;

    final gen = isInitial ? ++_generation : _generation;
    _update((s) => s.copyWith(
          isLoading: isInitial,
          isLoadingMore: !isInitial,
          error: () => null,
        ));

    final keyIdFyp = _displayedIds.join(',');
    try {
      final (rawList, newCursors) = await ref.read(repositoryProvider).getCuplixScroll(
            sort: state.sort,
            keyIdFyp: keyIdFyp,
            cursorParams: _cursors,
          );
      if (!_alive || gen != _generation) return;
      _cursors = newCursors;

      // Buang item tanpa id_episode dan yang sudah pernah tampil.
      final filtered = rawList
          .where((item) => !_blank(item.idEpisode) && !_displayedIds.contains(item.id))
          .toList();

      if (filtered.isEmpty && rawList.isNotEmpty) {
        // Semua item terbuang -> feed dianggap habis.
        _update((s) => s.copyWith(
              isLoading: false,
              isLoadingMore: false,
              isEndOfFeed: true,
            ));
        return;
      }

      for (final item in filtered) {
        _displayedIds.add(item.id);
      }

      _update((cur) => cur.copyWith(
            items: isInitial ? filtered : [...cur.items, ...filtered],
            isLoading: false,
            isLoadingMore: false,
            isEndOfFeed: filtered.isEmpty,
          ));

      // Prefetch link video untuk 3 item pertama.
      for (final item in filtered.take(3)) {
        final epId = item.idEpisode;
        if (epId != null) _prefetchStream(epId);
      }
    } catch (e) {
      if (!_alive || gen != _generation) return;
      final msg = errorMessage(e, 'Gagal memuat Cuplix');
      _update((s) => s.copyWith(
            isLoading: false,
            isLoadingMore: false,
            // Error muat-lanjut tidak ditampilkan (sama seperti Kotlin).
            error: isInitial ? () => msg : () => null,
          ));
    }
  }

  /// Ganti urutan feed lalu muat ulang dari awal. Kotlin tidak punya UI untuk
  /// ini (selalu scroll_likes); disediakan karena API mendukungnya.
  void setSort(String sort) {
    if (state.sort == sort) return;
    _displayedIds.clear();
    _cursors = const {};
    _update((s) => s.copyWith(
          sort: sort,
          items: const [],
          currentIndex: 0,
          isEndOfFeed: false,
        ));
    loadFeed(isInitial: true);
  }

  void onPageChanged(int newIndex) {
    _update((s) => s.copyWith(currentIndex: newIndex));
    final items = state.items;
    // Prefetch 2 item berikutnya.
    for (var i = newIndex + 1; i <= newIndex + 2; i++) {
      if (i < items.length) {
        final epId = items[i].idEpisode;
        if (epId != null) _prefetchStream(epId);
      }
    }
    // Dekat akhir -> muat lagi.
    if (newIndex >= items.length - 3) loadFeed();
  }

  /// Like hanya disimpan di state (tidak dikirim ke server, tidak disimpan
  /// permanen), sama seperti Kotlin.
  void toggleLike(String id) {
    _update((s) {
      final next = Set<String>.of(s.likedIds);
      if (!next.remove(id)) next.add(id);
      return s.copyWith(likedIds: next);
    });
  }

  void _prefetchStream(String episodeId) {
    if (_streamUrlCache.containsKey(episodeId)) return;
    unawaited(resolveStreamUrl(episodeId));
  }

  Future<String?> resolveStreamUrl(String episodeId) async {
    final cached = _streamUrlCache[episodeId];
    if (cached != null) return cached;
    final pending = _inflight[episodeId];
    if (pending != null) return pending;
    final future = _fetchStream(episodeId);
    _inflight[episodeId] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(episodeId);
    }
  }

  Future<String?> _fetchStream(String episodeId) async {
    try {
      final data = await ref.read(repositoryProvider).getEpisodeStream(episodeId);
      final link = _findBestDirectServer(data.server)?.link;
      if (link != null) _streamUrlCache[episodeId] = link;
      return link;
    } catch (_) {
      return null;
    }
  }

  void invalidateStreamCache(String episodeId) => _streamUrlCache.remove(episodeId);

  /// Pilih server bertipe "direct" dengan kualitas terdekat 480p, lalu 720p,
  /// lalu yang pertama. Kalau tidak ada yang "direct", pakai semua server.
  StreamServer? _findBestDirectServer(List<StreamServer> servers) {
    if (servers.isEmpty) return null;
    final direct =
        servers.where((s) => (s.type ?? '').toLowerCase() == 'direct').toList();
    final pool = direct.isNotEmpty ? direct : servers;

    bool has(StreamServer s, String q) => (s.quality ?? '').toLowerCase().contains(q);

    for (final s in pool) {
      if (has(s, '480')) return s;
    }
    for (final s in pool) {
      if (has(s, '720')) return s;
    }
    return pool.first;
  }
}

final cuplixControllerProvider =
    NotifierProvider<CuplixController, CuplixUiState>(CuplixController.new);
