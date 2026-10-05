import 'package:flutter/material.dart';

import '../../../core/premium_access.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/stream_data.dart';

/// Tag, warna, dan kalimat penjelas per kualitas -- gaya "Pilihan Kualitas
/// Video" di Zenime (port qualityTag/qualityAccentColor/qualityDescription).
String qualityTag(String? quality) {
  final v = qualityValueP(quality);
  if (v == null) return 'Alternatif';
  if (v >= 1080) return 'Premium';
  if (v >= 720) return 'Bagus';
  if (v >= 480) return 'Standar';
  return 'Hemat';
}

Color qualityAccentColor(String? quality) {
  final v = qualityValueP(quality);
  if (v == null) return Colors.white;
  if (v >= 1080) return const Color(0xFFFFC107);
  if (v >= 720) return const Color(0xFFFF7043);
  if (v >= 480) return const Color(0xFF66BB6A);
  return const Color(0xD9FFFFFF);
}

String qualityDescription(String? quality) {
  final v = qualityValueP(quality);
  if (v == null) return 'Kualitas alternatif buat nonton episode ini.';
  if (v >= 1080) {
    return 'Kualitas paling tinggi untuk tampilan maksimal, terbaik di jaringan cepat.';
  }
  if (v >= 720) {
    return 'Gambar lebih tajam dan nyaman ditonton jika internet kamu cukup stabil.';
  }
  if (v >= 480) return 'Pilihan aman untuk harian, cukup jernih dan tetap hemat data.';
  return 'Ringan untuk kuota dan cepat diputar di koneksi yang tidak stabil.';
}

/// Bottom sheet "Pilihan Kualitas Video". Kualitas di atas batas non-premium
/// tampil dengan gembok dan memanggil [onLocked] saat diketuk.
///
/// Padding bawah memakai inset bar navigasi HP (viewPadding.bottom). Tanpa
/// itu, item terakhir tertutup tombol navigasi karena layar edge-to-edge dan
/// `useSafeArea` tidak menyentuh sisi bawah.
Future<void> showQualityPickerSheet(
  BuildContext context, {
  required List<StreamServer> servers,
  required StreamServer? selected,
  required bool isPremium,
  required ValueChanged<StreamServer> onSelect,
  required VoidCallback onLocked,
}) {
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 2),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x40FFFFFF),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Text(
                      'Pilihan Kualitas Video',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (servers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        'Tidak ada server video alternatif.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    )
                  else
                    for (final server in servers)
                      _QualityRow(
                        server: server,
                        isSelected: identical(server, selected),
                        isLocked: isQualityLocked(server.quality, isPremium),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          if (isQualityLocked(server.quality, isPremium)) {
                            onLocked();
                          } else {
                            onSelect(server);
                          }
                        },
                      ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.server,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
  });

  final StreamServer server;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quality = server.quality ?? '720p';
    final name = server.name;
    final desc = qualityDescription(quality);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? AppColors.accentViolet.withValues(alpha: 0.10)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$quality (${qualityTag(quality)})',
                    style: TextStyle(
                      color: isLocked
                          ? const Color(0x66FFFFFF)
                          : qualityAccentColor(quality),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (name != null && name.isNotEmpty) ? '$name \u2022 $desc' : desc,
                    style: const TextStyle(color: Color(0x8CFFFFFF), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isLocked)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.lock, size: 18, color: AppColors.accentViolet),
              )
            else if (isSelected)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check, size: 20, color: AppColors.accentViolet),
              ),
          ],
        ),
      ),
    );
  }
}
