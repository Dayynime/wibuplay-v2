import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode Ringan untuk HP RAM kecil.
///
/// Yang diubah (animasi badge, border avatar, wallpaper TETAP jalan):
///  - cache gambar di memori dikecilkan (50 MB / 250 gambar, normal 100 MB / 1000);
///  - resolusi decode gambar dibatasi lebih rendah (maks 720 px, normal 1080 px);
///  - shimmer loading diganti placeholder polos (tidak animasi).
///
/// Otomatis nyala kalau RAM HP <= 3 GB. User bisa memaksa nyala/mati di
/// Pengaturan; pilihan itu disimpan dan mengalahkan deteksi otomatis.
class LiteMode {
  LiteMode._();

  static const String _prefKey = 'lite_mode_override';
  static const double _autoRamGb = 3.2; // HP "3 GB" biasanya terbaca ~2.7–3.0 GB

  static bool _auto = false;
  static bool? _override;
  static double _ramGb = 0;

  /// Berubah tiap Mode Ringan nyala/mati (untuk UI Pengaturan).
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static bool get enabled => _override ?? _auto;

  /// true = mengikuti deteksi otomatis (user belum memilih sendiri).
  static bool get isAuto => _override == null;

  /// RAM total HP (GB), 0 kalau tidak terbaca.
  static double get ramGb => _ramGb;

  /// Panggil sekali di main() sebelum runApp.
  static Future<void> load() async {
    _ramGb = await _readRamGb();
    _auto = _ramGb > 0 && _ramGb <= _autoRamGb;
    try {
      final p = await SharedPreferences.getInstance();
      _override = p.getBool(_prefKey);
    } catch (_) {}
    _apply();
  }

  /// [value] null = kembali ke otomatis.
  static Future<void> set(bool? value) async {
    _override = value;
    _apply();
    try {
      final p = await SharedPreferences.getInstance();
      if (value == null) {
        await p.remove(_prefKey);
      } else {
        await p.setBool(_prefKey, value);
      }
    } catch (_) {}
  }

  static void _apply() {
    final cache = PaintingBinding.instance.imageCache;
    if (enabled) {
      cache.maximumSizeBytes = 50 << 20;
      cache.maximumSize = 250;
    } else {
      cache.maximumSizeBytes = 100 << 20;
      cache.maximumSize = 1000;
    }
    notifier.value = enabled;
  }

  /// Batas sisi decode gambar (px fisik).
  static int get decodeCap => enabled ? 720 : 1080;

  /// Ukuran decode (px fisik) untuk gambar yang tampil selebar [logical] dp.
  static int px(BuildContext context, double logical) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final v = (logical * dpr).round();
    return v.clamp(32, decodeCap);
  }

  static Future<double> _readRamGb() async {
    if (kIsWeb || !Platform.isAndroid) return 0;
    try {
      final lines = await File('/proc/meminfo').readAsLines();
      for (final l in lines) {
        if (!l.startsWith('MemTotal:')) continue;
        final kb = int.tryParse(RegExp(r'\d+').firstMatch(l)?.group(0) ?? '');
        if (kb != null) return kb / 1024 / 1024;
      }
    } catch (_) {}
    return 0;
  }
}
