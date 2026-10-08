import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Siapkan gambar sebelum diupload (foto profil / banner).
///
/// GIF dilewatkan APA ADANYA supaya animasinya tidak hilang (image_picker
/// yang meresize/kompres selalu mengubah GIF jadi JPEG statis). Gambar lain
/// dikecilkan seperti sebelumnya (sisi terpanjang maks [maxSide], kualitas 82).
class ImagePrep {
  ImagePrep._();

  /// Batas ukuran GIF (Cloudinary gratis menolak file > 10 MB).
  static const int maxGifBytes = 8 * 1024 * 1024;

  static Future<bool> isGif(String path) async {
    final raf = await File(path).open();
    try {
      final head = String.fromCharCodes(await raf.read(6));
      return head == 'GIF87a' || head == 'GIF89a';
    } finally {
      await raf.close();
    }
  }

  /// Mengembalikan path file yang siap diupload.
  static Future<String> prepare(String path, {required int maxSide}) async {
    if (await isGif(path)) {
      if (await File(path).length() > maxGifBytes) {
        throw Exception('GIF terlalu besar, maksimal 8 MB');
      }
      return path;
    }
    final result = await compute(_resizeJob, <Object>[path, maxSide, 82]);
    if (result == null) return path; // format tak dikenal: kirim apa adanya
    final bytes = result[0] as Uint8List;
    final ext = result[1] as String;
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/up_${DateTime.now().microsecondsSinceEpoch}.$ext');
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }
}

List<Object>? _resizeJob(List<Object> args) {
  final path = args[0] as String;
  final maxSide = args[1] as int;
  final quality = args[2] as int;
  var image = img.decodeImage(File(path).readAsBytesSync());
  if (image == null) return null;
  image = img.bakeOrientation(image);
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }
  // PNG/WebP transparan tetap PNG supaya latar tidak jadi hitam.
  if (image.hasAlpha) {
    return <Object>[Uint8List.fromList(img.encodePng(image)), 'png'];
  }
  return <Object>[Uint8List.fromList(img.encodeJpg(image, quality: quality)), 'jpg'];
}
