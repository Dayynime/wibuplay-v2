/// Flag build. Satu kode, dua versi:
///
/// - Build APK biasa (release.yml): semua fitur seperti biasa.
/// - Build Google Play (play-release.yml, `--dart-define=PLAY_BUILD=true`):
///   updater APK mati (update lewat Play Store), cek tanda tangan mengikuti
///   kunci Play App Signing, dan filter konten dewasa aktif.
class BuildFlags {
  BuildFlags._();

  static const bool isPlay = bool.fromEnvironment('PLAY_BUILD');

  /// Filter konten dewasa (genre/judul) di komik dan daftar genre anime.
  /// Selalu aktif di build Play; di build APK bisa dinyalakan dengan
  /// `--dart-define=SAFE_CONTENT=true`.
  static const bool safeContent =
      isPlay || bool.fromEnvironment('SAFE_CONTENT');

  /// Halaman legal yang dipakai di Play Console.
  static const String privacyUrl = 'https://app.zenime.biz.id/privacy';
  static const String deleteAccountUrl = 'https://app.zenime.biz.id/delete';
  static const String termsUrl = 'https://app.zenime.biz.id/tos';
}
