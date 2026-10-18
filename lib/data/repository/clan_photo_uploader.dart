import 'package:dio/dio.dart';

/// Upload foto clan ke Cloudinary lewat unsigned upload preset, sama seperti
/// ClanPhotoUploader.kt di Zenime. Cloud name + preset unsigned memang publik
/// by design (tidak ada API secret di client).
class ClanPhotoUploader {
  ClanPhotoUploader._();

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

  /// [filePath] sudah dikecilkan (maks 512px) oleh image_picker.
  /// [pathKey] contoh: "<uid>-<millis>". Mengembalikan secure_url (HTTPS).
  static Future<String> uploadClanPhoto(String filePath, String pathKey) async {
    final form = FormData.fromMap({
      'upload_preset': _uploadPreset,
      'public_id': 'clan-photos/$pathKey',
      'file': await MultipartFile.fromFile(filePath, filename: '$pathKey.jpg'),
    });
    final res = await _dio.post<dynamic>(_url, data: form);
    final data = res.data;
    final url = data is Map ? data['secure_url'] : null;
    if (url is! String || url.isEmpty) {
      throw Exception('Upload foto clan gagal');
    }
    return url;
  }
}
