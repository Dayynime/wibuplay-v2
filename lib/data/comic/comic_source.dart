import '../models/comic_models.dart';

/// Sumber komik yang tersedia (port ComicSourceId.kt). Semuanya lewat API
/// Sanka: https://www.sankavollerei.web.id/comic/{source}/...
enum ComicSourceId {
  // id tetap (dipakai di API, penyimpanan & route); cuma label tampilan.
  bacakomik('bacakomik', 'Dayynime-v1'),
  westmanga('westmanga', 'Dayynime-v2');

  const ComicSourceId(this.id, this.label);

  final String id;
  final String label;
}

/// Kunci komik = slug yang diberi awalan sumber, supaya slug yang sama di dua
/// sumber tidak bentrok di penyimpanan (favorit / progress baca) maupun route.
///
/// Bacakomik sengaja TIDAK diberi awalan, jadi data favorit & progress yang
/// sudah ada (termasuk hasil impor dari Zenime) tetap valid.
///   "nano-machine"            -> Bacakomik
///   "westmanga~solo-leveling" -> Westmanga
class ComicKey {
  ComicKey._();

  static const String _sep = '~';

  static String encode(ComicSourceId source, String slug) =>
      source == ComicSourceId.bacakomik ? slug : '${source.id}$_sep$slug';

  static (ComicSourceId, String) decode(String key) {
    final idx = key.indexOf(_sep);
    if (idx > 0) {
      final prefix = key.substring(0, idx);
      for (final s in ComicSourceId.values) {
        if (s.id == prefix) return (s, key.substring(idx + 1));
      }
    }
    return (ComicSourceId.bacakomik, key);
  }
}

/// Satu tab daftar di layar Komik (mis. "Terbaru", "Populer", "Manhwa").
class ComicTab {
  const ComicTab(this.id, this.label);

  final String id;
  final String label;
}

/// Adapter satu sumber komik. Semua slug di sini POLOS (tanpa awalan sumber);
/// awalan ditambah/dibuang oleh ComicRepository lewat [ComicKey].
/// Method melempar exception kalau gagal.
abstract class ComicSource {
  ComicSourceId get id;
  List<ComicTab> get tabs;

  Future<ComicListResponse> browse(String tabId, int page);
  Future<ComicListResponse> search(String query, int page);
  Future<ComicDetail> detail(String slug);
  Future<ComicChapterResponse> chapter(String comicSlug, String chapterSlug);
  Future<List<ComicGenreItem>> genres();
  Future<ComicListResponse> byGenre(String genreSlug, int page);
}
