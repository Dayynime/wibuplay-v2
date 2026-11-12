import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/image_cache.dart';
import '../../../core/lite_mode.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/api/moviebox_network.dart';
import '../../../data/models/moviebox_models.dart';
import '../../components/shimmer.dart';

/// Poster film MovieBox. Pakai di tempat yang ukurannya sudah pasti.
class MovieBoxImage extends StatelessWidget {
  const MovieBoxImage(this.url, {super.key, this.fit = BoxFit.cover});

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return const SizedBox.expand();
    return LayoutBuilder(builder: (context, c) {
      final bw = c.maxWidth.isFinite ? c.maxWidth : 0.0;
      final bh = c.maxHeight.isFinite ? c.maxHeight : 0.0;
      final tall = bh >= bw;
      return CachedNetworkImage(
        cacheManager: AppImageCache.images,
        imageUrl: u,
        httpHeaders: MovieBoxNetwork.imageHeaders,
        memCacheWidth: bw > 0 && !tall ? LiteMode.px(context, bw) : null,
        memCacheHeight: bh > 0 && tall ? LiteMode.px(context, bh) : null,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => const SizedBox.expand(child: ShimmerBox(borderRadius: BorderRadius.zero)),
        errorWidget: (_, __, ___) => const ColoredBox(
          color: AppColors.surfaceCard,
          child: Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
        ),
      );
    });
  }
}

/// Kartu poster film (2:3) + judul + tahun. Lebar ditentukan parent.
class MovieBoxCard extends StatelessWidget {
  const MovieBoxCard({super.key, required this.item, required this.onTap});

  final MbItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rating = item.rating;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: AppColors.surfaceDark),
                  MovieBoxImage(item.cover),
                  if (rating != null && rating != '0' && rating != '0.0')
                    Positioned(top: 6, left: 6, child: _Chip('★ $rating')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (item.title ?? '').trim().isEmpty ? 'Tanpa Judul' : item.title!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 17 / 12.5,
            ),
          ),
          if (item.year != null)
            Text(item.year!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFFFC107), fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class MbCenterMessage extends StatelessWidget {
  const MbCenterMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }
}

/// Chip aksi di bawah video (sama dengan player donghua).
class MbActionChip extends StatelessWidget {
  const MbActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: highlight ? AppColors.accentVioletSubtle : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: highlight ? AppColors.accentViolet.withValues(alpha: 0.6) : AppColors.surfaceElevated,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: highlight ? AppColors.accentVioletLight : Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: highlight ? AppColors.accentVioletLight : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
