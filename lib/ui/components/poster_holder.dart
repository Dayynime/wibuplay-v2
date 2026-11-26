/// Port PosterTransitionHolder (sisi URL): menyimpan poster yang barusan
/// diketuk di Beranda supaya Detail bisa langsung menampilkannya sebagai
/// latar sebelum data selesai dimuat.
///
/// Juga menyimpan tag Hero kartu poster yang diketuk, supaya posternya
/// "terbang" ke posisi poster di halaman Detail.
class PosterTransitionHolder {
  PosterTransitionHolder._();

  static String? url;

  /// Detail dibuka dari panel yang sudah membesar memenuhi area hero
  /// (Rekomendasi manga): hero Detail langsung tampil penuh tanpa animasi
  /// mengembang lagi. Dipakai sekali oleh Detail.
  static bool zoomedIn = false;

  static Object? _heroTag;
  static DateTime? _heroAt;

  /// Dipanggil kartu poster tepat sebelum membuka Detail.
  static void setHero(Object tag) {
    _heroTag = tag;
    _heroAt = DateTime.now();
  }

  /// Tag hero yang masih baru (< 1 detik). Kartu yang diketuk tapi tidak
  /// membuka Detail tidak boleh "menerbangkan" poster lain belakangan.
  static Object? get freshHero {
    final at = _heroAt;
    if (_heroTag == null || at == null) return null;
    if (DateTime.now().difference(at) > const Duration(seconds: 1)) return null;
    return _heroTag;
  }

  /// Ambil lalu kosongkan (dipakai sekali oleh halaman Detail).
  static Object? takeHero() {
    final t = freshHero;
    _heroTag = null;
    _heroAt = null;
    return t;
  }
}
