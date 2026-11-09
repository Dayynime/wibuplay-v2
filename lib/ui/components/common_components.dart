import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Judul section (redesain Samudra): label Jepang kecil di atas judul tebal,
/// tombol aksi abu-abu dengan panah. Label Jepang otomatis untuk judul yang
/// dikenal ([_eyebrows]), atau isi sendiri lewat [eyebrow].
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onActionClick,
    this.eyebrow,
  });

  final String title;
  final String? actionText;
  final VoidCallback? onActionClick;

  /// Label kecil di atas judul (mis. 新着エピソード). null = cari di [_eyebrows].
  final String? eyebrow;

  static const Map<String, String> _eyebrows = {
    'Episode Baru': '新着エピソード',
    'Sedang Hangat': '人気上昇',
    'Jadwal Hari Ini': '今日の放送',
    'Judul Baru': '新作',
    'Terpopuler': 'ランキング',
    'Jas Por Yu': 'おすすめ',
    'Paling Dinanti': '期待作',
    'Riwayat Tontonan': '視聴履歴',
    'Lanjut Nonton': '続きから',
    'Komik Terbaru': '最新マンガ',
    'Komik': 'マンガ',
    'Donghua': 'ドンファ',
    'Genre': 'ジャンル',
    'Musim Ini': '今期',
  };

  @override
  Widget build(BuildContext context) {
    final label = eyebrow ?? _eyebrows[title];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppColors.accentVioletLight,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        height: 1.2,
                      ),
                    ),
                  ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          if (actionText != null && onActionClick != null)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onActionClick,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionText!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Port GenreChip.
class GenreChip extends StatelessWidget {
  const GenreChip({super.key, required this.text, this.isSelected = false, this.onTap});

  final String text;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.accentViolet : AppColors.surfaceDark,
        borderRadius: AppShapes.pill,
        border: Border.all(
          color: isSelected ? AppColors.accentViolet : AppColors.surfaceElevated,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isSelected ? AppColors.textWhite : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppColors.accentViolet, size: 32),
    );
  }
}

/// Port EmptyState.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.subtitle, required this.icon});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _IconCircle(icon),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 18 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Port ErrorState.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _IconCircle(Icons.error_outline),
          const SizedBox(height: 16),
          const Text(
            'Gagal Memuat Konten',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 18 / 13,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentViolet,
              foregroundColor: AppColors.textWhite,
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text(
              'Coba Lagi',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
