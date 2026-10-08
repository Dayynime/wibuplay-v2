import 'package:dio/dio.dart';

/// Upload foto profil & banner ke Cloudinary lewat unsigned upload preset,
/// sama seperti AvatarUploader.kt / BannerUploader.kt di Zenime. public_id
/// SELALU unik per upload (nempel timestamp) supaya tidak bentrok di
/// Cloudinary.
class ProfileImageUploader {
  ProfileImageUploader._();

  static const String _cloudName = 'jbtwhnrb';
  static const String _uploadPreset = 'Zenime';
  static const String _url = 'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<String> _upload(String filePath, String publicId) async {
    final dot = filePath.lastIndexOf('.');
    final ext = dot >= 0 && filePath.length - dot <= 5
        ? filePath.substring(dot + 1).toLowerCase()
        : 'jpg';
    final form = FormData.fromMap({
      'upload_preset': _uploadPreset,
      'public_id': publicId,
      'file': await MultipartFile.fromFile(filePath, filename: '${publicId.split('/').last}.$ext'),
    });
    final res = await _dio.post<dynamic>(_url, data: form);
    final data = res.data;
    final url = data is Map ? data['secure_url'] : null;
    if (url is! String || url.isEmpty) {
      throw Exception('Upload gambar gagal');
    }
    return url;
  }

  /// [filePath] hasil ImagePrep.prepare (GIF tetap utuh, selain itu maks 512px).
  static Future<String> uploadAvatar(String filePath, String firebaseUid) =>
      _upload(filePath, 'avatars/$firebaseUid-${DateTime.now().millisecondsSinceEpoch}');

  /// [filePath] hasil ImagePrep.prepare (GIF tetap utuh, selain itu maks 1280px).
  static Future<String> uploadBanner(String filePath, String firebaseUid) =>
      _upload(filePath, 'banners/$firebaseUid-${DateTime.now().millisecondsSinceEpoch}');
}
