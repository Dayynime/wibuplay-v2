import 'media_uploader.dart';

/// Upload foto profil, banner, dan banner clan. Dulu ke Cloudinary; sejak
/// akun Cloudinary dinonaktifkan (kuota free habis) pindah ke Supabase Storage
/// lewat [MediaUploader]. Nama fungsi tetap supaya pemanggil tidak berubah.
class ProfileImageUploader {
  ProfileImageUploader._();

  /// [filePath] hasil ImagePrep.prepare (GIF tetap utuh, selain itu maks 512px).
  static Future<String> uploadAvatar(String filePath, String firebaseUid) =>
      MediaUploader.upload(filePath, kind: 'avatar');

  /// [filePath] hasil ImagePrep.prepare (GIF tetap utuh, selain itu maks 1280px).
  static Future<String> uploadBanner(String filePath, String firebaseUid) =>
      MediaUploader.upload(filePath, kind: 'banner');

  /// Banner clan (GIF tetap utuh, selain itu sudah dipotong 1280x720). Khusus leader.
  static Future<String> uploadClanBanner(String filePath, String clanId) =>
      MediaUploader.upload(filePath, kind: 'clan_banner', clanId: clanId);
}
