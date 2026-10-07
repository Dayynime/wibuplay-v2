import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/comic/comic_providers.dart';
import '../../../data/models/comic_models.dart';
import '../../../data/repository/comic_repository.dart';

class ComicDetailState {
  const ComicDetailState({this.detail, this.isLoading = true, this.error});

  final ComicDetail? detail;
  final bool isLoading;
  final String? error;
}

/// Port ComicDetailViewModel.kt. Argumen family = kunci komik (ComicKey).
/// Favorit & progress baca dibaca langsung dari comicStoreProvider di UI.
class ComicDetailController
    extends AutoDisposeFamilyNotifier<ComicDetailState, String> {
  bool _alive = true;

  ComicRepository get _repo => ref.read(comicRepositoryProvider);

  @override
  ComicDetailState build(String arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future.microtask(load);
    return const ComicDetailState();
  }

  Future<void> load({bool forceRefresh = false}) async {
    if (_alive) state = const ComicDetailState();
    try {
      final d = await _repo.getDetail(arg, forceRefresh: forceRefresh);
      if (_alive) state = ComicDetailState(detail: d, isLoading: false);
    } catch (e) {
      if (_alive) {
        state = ComicDetailState(
          isLoading: false,
          error: errorMessage(e, 'Gagal memuat detail komik.'),
        );
      }
    }
  }

  Future<void> toggleFavorite() async {
    final d = state.detail;
    if (d == null) return;
    final currently = _repo.store.isFavorite(arg);
    await _repo.toggleFavorite(
      slug: arg,
      title: d.title ?? 'Tanpa Judul',
      cover: d.cover,
      status: d.status,
      isCurrentlyFavorite: currently,
    );
  }
}

final comicDetailControllerProvider = NotifierProvider.autoDispose
    .family<ComicDetailController, ComicDetailState, String>(
  ComicDetailController.new,
);
