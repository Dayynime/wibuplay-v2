import 'package:flutter/material.dart';

/// Palet Zenime "Samudra": latar navy laut pekat #06111D dengan aksen biru
/// cerah #1FB6F5 (tema utama hasil redesain Nov 2026).
///
/// Catatan nama: konstanta `accentViolet*` dipertahankan sebagai nama supaya
/// ratusan pemakaiannya tidak perlu diubah, tapi nilainya sekarang biru
/// Samudra (aksen utama). Semua warna aksen/latar di app berasal dari sini,
/// jadi mengganti palet cukup di satu file ini. Warna badge, border avatar,
/// dan rarity punya palet sendiri dan sengaja tidak ikut berubah.
class AppColors {
  AppColors._();

  // Latar & permukaan (navy laut).
  static const Color backgroundDark = Color(0xFF06111D);
  static const Color backgroundDarkSecondary = Color(0xFF040B14);
  static const Color surfaceDark = Color(0xFF0D1C2D);
  static const Color surfaceVariantDark = Color(0xFF13273D);
  static const Color surfaceElevated = Color(0xFF1D3853);
  static const Color surfaceCard = Color(0xFF0F2034);

  // Aksen utama (biru Samudra) + varian terang/gelap.
  static const Color accentViolet = Color(0xFF1FB6F5);
  static const Color accentVioletLight = Color(0xFF6AD3FF);
  static const Color accentVioletDark = Color(0xFF0B87C4);
  static const Color accentVioletSubtle = Color(0x331FB6F5);

  /// Aksen kedua untuk ujung gradien (biru ke toska).
  static const Color accentTeal = Color(0xFF4BE3C1);

  // Teks.
  static const Color textWhite = Color(0xFFEEF6FC);
  static const Color textSecondary = Color(0xFFA3BBD0);
  static const Color textMuted = Color(0xFF627D96);

  // Status.
  static const Color successGreen = Color(0xFF10B981); // StatusOngoing
  static const Color errorRed = Color(0xFFFF6B6B);
  static const Color warningAmber = Color(0xFFF59E0B);

  // Overlay / gradient ke warna latar.
  static const Color overlayDark = Color(0xCC06111D);
  static const Color gradientDarkStart = Color(0x0006111D);
  static const Color gradientDarkEnd = Color(0xFF06111D);
}
