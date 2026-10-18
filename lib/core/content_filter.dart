import 'build_flags.dart';

/// Filter konten dewasa sederhana berbasis genre dan kata kunci judul.
/// Aktif hanya kalau [BuildFlags.safeContent] true.
class ContentFilter {
  ContentFilter._();

  static bool get enabled => BuildFlags.safeContent;

  // Dibandingkan setelah dinormalisasi (huruf kecil, tanpa spasi/tanda baca).
  static const Set<String> _blockedGenres = {
    'ecchi', 'hentai', 'adult', 'mature', 'smut', 'erotica', 'erotic',
    'sexual', 'sexualviolence', 'pornographic', 'nsfw', '18', '18plus',
    'doujinshi', 'r18', 'r18plus',
  };

  static const List<String> _blockedTitleWords = [
    'hentai', 'ecchi', 'nsfw', '18+', 'r18', 'r-18', 'smut', 'porn',
    'sex', 'seks', 'mesum', 'bokep', 'nude', 'naked', 'erotic',
  ];

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9+]'), '').replaceAll('+', 'plus');

  static bool isBlockedGenre(String titleOrSlug) {
    if (!enabled) return false;
    final n = _norm(titleOrSlug);
    return _blockedGenres.contains(n);
  }

  static bool hasBlockedGenre(Iterable<String> genres) =>
      enabled && genres.any(isBlockedGenre);

  static bool isBlockedTitle(String title) {
    if (!enabled) return false;
    final t = ' ${title.toLowerCase()} ';
    for (final w in _blockedTitleWords) {
      if (RegExp('(^|[^a-z0-9])${RegExp.escape(w)}([^a-z0-9]|\$)').hasMatch(t)) {
        return true;
      }
    }
    return false;
  }
}
