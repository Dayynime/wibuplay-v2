import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/image_cache.dart';
import '../../../core/lite_mode.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/chat_wallpaper_cache.dart';
import '../../components/net_image.dart';
import '../../components/rarity_chip.dart';

/// Bubble chat berlatar wallpaper yang dipasang pengirim (sama dengan
/// wallpaper komentar / banner profil):
///  - wallpaper memenuhi bubble, digelapkan dari kiri supaya teks terbaca,
///    sisi kanan tetap memperlihatkan gambarnya;
///  - garis tepi + cahaya tipis berwarna rarity;
///  - badge di pojok kanan bawah: thumbnail + rarity (+ nama kalau ada).
class WallpaperBubble extends StatelessWidget {
  const WallpaperBubble({
    super.key,
    required this.wallpaper,
    required this.width,
    required this.child,
    this.highlighted = false,
  });

  final ChatWallpaper wallpaper;
  final double width;
  final bool highlighted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = wallpaper.wallpaper;
    final rc = w.rarity.color;
    final radius = AppShapes.card;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: width,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: highlighted ? AppColors.accentViolet : rc.withValues(alpha: 0.85),
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: rc.withValues(alpha: 0.28), blurRadius: 18, spreadRadius: -6, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                cacheManager: AppImageCache.images,
                imageUrl: w.url,
                httpHeaders: netImageHeaders,
                memCacheWidth: LiteMode.px(context, width),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceCard),
                errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceCard),
              ),
            ),
            // Gelap di kiri (tempat teks), makin bening ke kanan.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xE00B0E14), Color(0x9E0B0E14), Color(0x470B0E14)],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            if (highlighted) const Positioned.fill(child: ColoredBox(color: Color(0x33E4344A))),
            Padding(
              // Ruang bawah untuk badge (di bawah baris "jam · Balas · Hapus").
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
              child: child,
            ),
            Positioned(
              right: 8,
              bottom: 7,
              child: IgnorePointer(child: _WallpaperBadge(wallpaper: wallpaper)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WallpaperBadge extends StatelessWidget {
  const _WallpaperBadge({required this.wallpaper});

  final ChatWallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    final w = wallpaper.wallpaper;
    final name = wallpaper.name;
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 4, 3),
      decoration: BoxDecoration(
        color: const Color(0xB80B0E14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: w.rarity.color.withValues(alpha: 0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(width: 16, height: 16, child: NetImage(w.url)),
          ),
          const SizedBox(width: 4),
          RarityChip(rarity: w.rarity, fontSize: 9),
          if (name != null) ...[
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }
}
