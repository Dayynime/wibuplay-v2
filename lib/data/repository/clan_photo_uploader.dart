import 'media_uploader.dart';

/// Upload foto clan ke Supabase Storage (dulu Cloudinary) lewat [MediaUploader].
class ClanPhotoUploader {
  ClanPhotoUploader._();

  static final RegExp _uuidPrefix =
      RegExp(r'^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', caseSensitive: false);

  /// [pathKey] contoh: "<clanId>-<millis>" (ganti foto, khusus leader) atau
  /// "<uid>-<millis>" (buat clan baru). Mengembalikan URL publik (HTTPS).
  static Future<String> uploadClanPhoto(String filePath, String pathKey) {
    final clanId = _uuidPrefix.firstMatch(pathKey)?.group(1);
    return MediaUploader.upload(filePath, kind: 'clan_photo', clanId: clanId);
  }
}
