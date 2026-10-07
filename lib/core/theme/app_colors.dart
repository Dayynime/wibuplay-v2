import 'package:flutter/material.dart';

/// Palet Zenime "Crimson Dark" (port Color.kt Zenime): aksen merah crimson
/// #E4344A di atas navy-black #0B0E14.
///
/// Catatan nama: konstanta `accentViolet*` dipertahankan sebagai nama supaya
/// ratusan pemakaiannya tidak perlu diubah, tapi nilainya sekarang crimson
/// (aksen utama). Semua warna aksen/latar di app berasal dari sini, jadi
/// mengganti palet cukup di satu file ini.
class AppColors {
  AppColors._();

  // Latar & permukaan (navy gelap Zenime).
  static const Color backgroundDark = Color(0xFF0B0E14); // ZenimeBackgroundDark
  static const Color backgroundDarkSecondary = Color(0xFF080B10);
  static const Color surfaceDark = Color(0xFF151A23); // ZenimeSurfaceDark
  static const Color surfaceVariantDark = Color(0xFF1C222E); // ZenimeSurfaceVariantDark
  static const Color surfaceElevated = Color(0xFF262D3B);
  static const Color surfaceCard = Color(0xFF181E29);

  // Aksen utama (crimson Zenime #E4344A) + varian terang/gelap.
  static const Color accentViolet = Color(0xFFE4344A); // ZenimePrimary
  static const Color accentVioletLight = Color(0xFFEE5B6D);
  static const Color accentVioletDark = Color(0xFFC42A3E);
  static const Color accentVioletSubtle = Color(0x33E4344A);

  // Teks.
  static const Color textWhite = Color(0xFFF5F5F7); // ZenimeOnSurfaceDark
  static const Color textSecondary = Color(0xFF9AA0AC); // ZenimeOnSurfaceVariantDark
  static const Color textMuted = Color(0xFF6E7584);

  // Status.
  static const Color successGreen = Color(0xFF10B981); // StatusOngoing
  static const Color errorRed = Color(0xFFFF6B6B);
  static const Color warningAmber = Color(0xFFF59E0B);

  // Overlay / gradient ke warna latar.
  static const Color overlayDark = Color(0xCC0B0E14);
  static const Color gradientDarkStart = Color(0x000B0E14);
  static const Color gradientDarkEnd = Color(0xFF0B0E14);
}
