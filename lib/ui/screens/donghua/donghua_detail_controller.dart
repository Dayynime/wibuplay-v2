import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/anichin_models.dart';
import '../../../providers.dart';

class DonghuaDetailState {
  const DonghuaDetailState({this.detail, this.isLoading = true, this.error});

  final AnichinAnimeDetail? detail;
  final bool isLoading;
  final String? error;
}

// Slug episode: "...-episode-12-subtitle-indonesia" (juga typo "epsiode").
final RegExp _episodeSlug = RegExp(r'-ep[a-z]*sode-\d+');
final RegExp _episodeTail = RegExp(r'-ep[a-z]*sode-\d+.*$');
// Sisa judul tanpa kata episode: "...-subtitle-indonesia".
final RegExp _subtitleTail =
    RegExp(r'-(subtitle|sub)-?(indonesia|indo|indonesa).*$', caseSensitive: false);

/// Port DonghuaDetailViewModel.kt.
///
/// Menerima slug ANIME maupun slug EPISODE (kartu "Terbaru" di Beranda
/// mengirim slug episode). Endpoint detail `/{slug}` cuma paham slug anime,
/// jadi slug episode diubah dulu ke slug anime.
class DonghuaDetailController
    extends AutoDisposeFamilyNotifier<DonghuaDetailState, String> {
  bool _alive = true;

  @override
  DonghuaDetailState build(String arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future.microtask(load);
    return const DonghuaDetailState();
  }

  void _update(DonghuaDetailState s) {
    if (_alive) state = s;
  }

  static bool _isEpisodeSlug(String slug) => _episodeSlug.hasMatch(slug);

  static String _animeSlugFromEpisode(String slug) =>
      slug.replaceFirst(_episodeTail, '').replaceFirst(_subtitleTail, '');

  Future<void> load() async {
    _update(const DonghuaDetailState(isLoading: true));
    final repo = ref.read(anichinRepositoryProvider);
    try {
      final slug = arg;
      AnichinAnimeDetail detail;
      if (!_isEpisodeSlug(slug)) {
        detail = await repo.getDetail(slug);
      } else {
        try {
          detail = await repo.getDetail(_animeSlugFromEpisode(slug));
          // Scraper balas "Unknown Title" kalau slug anime-nya tidak cocok.
          if (detail.name == 'Unknown Title') throw Exception('unknown');
        } catch (_) {
          // Cadangan: tanya halaman episode, ambil slug anime induknya.
          final ep = await repo.getEpisode(slug);
          final root = ep.root;
          if (root == null || root.isEmpty) rethrow;
          detail = await repo.getDetail(root);
        }
      }
      _update(DonghuaDetailState(detail: detail, isLoading: false));
    } catch (e) {
      _update(DonghuaDetailState(
        isLoading: false,
        error: errorMessage(e, 'Gagal memuat detail donghua.'),
      ));
    }
  }
}

final donghuaDetailControllerProvider = NotifierProvider.autoDispose
    .family<DonghuaDetailController, DonghuaDetailState, String>(
  DonghuaDetailController.new,
);
