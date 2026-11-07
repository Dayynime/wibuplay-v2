import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache gambar di HP (disk) untuk seluruh app.
///
/// Bawaan `cached_network_image` cuma menyimpan 200 file. App anime menampilkan
/// puluhan poster per halaman, jadi 200 cepat penuh: poster lama dibuang lalu
/// di-download ulang saat dibuka lagi (kedip loading + boros kuota). Di sini
/// batasnya dinaikkan, dan halaman komik punya cache sendiri supaya membaca
/// satu chapter tidak menggusur poster.
///
/// Pembersihan otomatis: file yang tidak dipakai lebih dari [_stale] dihapus,
/// dan kalau jumlahnya lewat batas, yang paling lama tidak dipakai dibuang.
class AppImageCache {
  AppImageCache._();

  static const String _imagesKey = 'wibuplay_images_v1';
  static const String _comicKey = 'wibuplay_comic_pages_v1';
  static const Duration _stale = Duration(days: 30);

  /// Poster, cover, avatar, wallpaper, dll.
  static final CacheManager images = CacheManager(
    Config(_imagesKey, stalePeriod: _stale, maxNrOfCacheObjects: 1000),
  );

  /// Halaman komik (besar & banyak): dipisah, disimpan lebih singkat.
  static final CacheManager comicPages = CacheManager(
    Config(_comicKey, stalePeriod: const Duration(days: 7), maxNrOfCacheObjects: 400),
  );

  static const String _migratedPref = 'image_cache_migrated_v1';

  /// Sekali saja setelah update: kosongkan cache gambar lama (bawaan) yang
  /// sudah tidak dipakai, supaya tidak memakan memori HP. Tanpa ditunggu.
  static Future<void> migrateOnce() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_migratedPref) == true) return;
      await DefaultCacheManager().emptyCache();
      await p.setBool(_migratedPref, true);
    } catch (_) {}
  }

  /// Total ukuran cache gambar di HP (byte).
  static Future<int> diskBytes() async {
    var total = 0;
    try {
      final base = await getTemporaryDirectory();
      for (final key in const [_imagesKey, _comicKey, DefaultCacheManager.key]) {
        final dir = Directory('${base.path}/$key');
        if (!await dir.exists()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return total;
  }

  /// Kosongkan cache gambar di memori DAN di HP.
  static Future<void> clearAll() async {
    final mem = PaintingBinding.instance.imageCache;
    mem.clear();
    mem.clearLiveImages();
    for (final m in [images, comicPages, DefaultCacheManager()]) {
      try {
        await m.emptyCache();
      } catch (_) {}
    }
  }

  /// "12,3 MB" dsb.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var v = bytes / 1024;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s.replaceAll('.', ',')} ${units[i]}';
  }
}
