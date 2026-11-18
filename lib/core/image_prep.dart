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

  /// True untuk gambar ANIMASI: GIF, WebP animasi, dan APNG (PNG animasi).
  /// Banyak "GIF" hasil unduhan (TikTok/Pinterest/Tenor/keyboard) sebenarnya
  /// WebP animasi; semuanya diperlakukan seperti GIF (tanpa crop, tanpa
  /// kompres) supaya animasinya tetap. Dicek dari ISI file, bukan ekstensi.
  static Future<bool> isGif(String path) async {
    final raf = await File(path).open();
    try {
      final h = await raf.read(65536);
      if (h.length < 6) return false;
      final head6 = String.fromCharCodes(h.sublist(0, 6));
      if (head6 == 'GIF87a' || head6 == 'GIF89a') return true;
      String s(int a) => String.fromCharCodes(h.sublist(a, a + 4));
      // WebP animasi: RIFF....WEBP + VP8X dengan flag animasi (bit 0x02).
      if (h.length >= 21 && s(0) == 'RIFF' && s(8) == 'WEBP') {
        return s(12) == 'VP8X' && (h[20] & 0x02) != 0;
      }
      // APNG: PNG yang punya chunk acTL (sebelum IDAT).
      if (h.length >= 8 && h[0] == 0x89 && h[1] == 0x50 && h[2] == 0x4E && h[3] == 0x47) {
        return _indexOf(h, 'acTL') != -1;
      }
      return false;
    } finally {
      await raf.close();
    }
  }

  static int _indexOf(Uint8List b, String t) {
    final c = t.codeUnits;
    outer:
    for (var i = 0; i + c.length <= b.length; i++) {
      for (var j = 0; j < c.length; j++) {
        if (b[i + j] != c[j]) continue outer;
      }
      return i;
    }
    return -1;
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
