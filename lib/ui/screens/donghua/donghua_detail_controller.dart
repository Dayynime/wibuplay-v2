import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/anichin_models.dart';
import '../../../data/repository/anichin_repository.dart';
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

  AnichinRepository get _repo => ref.read(anichinRepositoryProvider);

  Future<_Fetch> _fetch(String target) async {
    try {
      return _Fetch(data: await _repo.getDetail(target));
    } catch (e) {
      return _Fetch(error: e);
    }
  }

  /// Slug anime induk dari /episode/{slug} (null kalau gagal / tidak ada).
  Future<String?> _rootOf(String slug) async {
    try {
      final root = (await _repo.getEpisode(slug)).root;
      return (root == null || root.trim().isEmpty) ? null : root;
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    _update(const DonghuaDetailState(isLoading: true));
    final slug = arg;
    _Fetch result;

    if (!_isEpisodeSlug(slug)) {
      result = await _fetch(slug);

      // Slug film/episode tanpa "-episode-N" (mis. "xxx-movie-subtitle-indonesia")
      // dibalas API sebagai "Unknown Title" karena endpoint detail cuma paham
      // slug anime. Cari slug anime induknya lewat "root" episode, atau buang
      // ekor "-subtitle-indonesia".
      if (result.isUnknownTitle) {
        final root = await _rootOf(slug);
        final candidates = <String>{
          if (root != null) root,
          slug.replaceAll(_subtitleTail, ''),
        }.where((c) => c.trim().isNotEmpty && c != slug).toList();
        for (final candidate in candidates) {
          final r = await _fetch(candidate);
          if (!r.isUnknownTitle) {
            result = r;
            break;
          }
        }
      }
    } else {
      // 1) Tebak slug anime dari slug episode (buang "-episode-160-subtitle-indonesia").
      final derived = slug.replaceAll(_episodeTail, '');
      result = await _fetch(derived);

      // 2) Tebakan meleset (typo di slug, dll) -> tanya /episode/{slug} buat
      //    dapetin "root".
      if (result.isUnusable) {
        final root = await _rootOf(slug);
        if (root != null && root != derived) result = await _fetch(root);
      }
    }

    final data = result.data;
    if (data != null) {
      _update(DonghuaDetailState(detail: data, isLoading: false));
    } else {
      _update(DonghuaDetailState(
        isLoading: false,
        error: errorMessage(result.error ?? 'x', 'Gagal memuat detail donghua.'),
      ));
    }
  }
}

class _Fetch {
  const _Fetch({this.data, this.error});

  final AnichinAnimeDetail? data;
  final Object? error;

  bool get isUnknownTitle => data != null && data!.name == 'Unknown Title';

  bool get isUnusable =>
      data == null || data!.name == 'Unknown Title' || data!.episodes.isEmpty;
}

final donghuaDetailControllerProvider = NotifierProvider.autoDispose
    .family<DonghuaDetailController, DonghuaDetailState, String>(
  DonghuaDetailController.new,
);
