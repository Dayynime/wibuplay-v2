import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/anime_item.dart';
import 'net_image.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Port AnimePosterCard (Cards.kt): poster 2:3, badge status/tipe kanan atas,
/// views kiri bawah, rank opsional, efek tekan 0.96.
class AnimePosterCard extends StatefulWidget {
  const AnimePosterCard({
    super.key,
    required this.anime,
    required this.onTap,
    this.width = 140,
    this.showRank,
  });

  final AnimeItem anime;
  final VoidCallback onTap;
  final double width;
  final int? showRank;

  @override
  State<AnimePosterCard> createState() => _AnimePosterCardState();
}

class _AnimePosterCardState extends State<AnimePosterCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    final badgeText = anime.status ?? anime.type;
    final subtext = anime.genre ?? anime.year;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: AppShapes.card,
                  child: ColoredBox(
                    color: AppColors.surfaceCard,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(anime.posterUrl),
                        // Gradien bawah
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 60,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xCC1E1B2E)],
                              ),
                            ),
                          ),
                        ),
                        // Badge status / tipe kanan atas
                        if (!_blank(badgeText))
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xCC1E1B2E),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badgeText!,
                                style: const TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        // Views kiri bawah
                        if (!_blank(anime.views))
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.visibility_outlined,
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  anime.views!,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Rank opsional
                        if (widget.showRank != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: AppColors.accentViolet,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${widget.showRank}',
                                style: const TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                anime.title ?? 'Anime',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 17 / 13,
                ),
              ),
              if (!_blank(subtext)) ...[
                const SizedBox(height: 2),
                Text(
                  subtext!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Port ContinueWatchingCard: thumbnail 220x124, tombol play, bar progres.
class ContinueWatchingCard extends StatefulWidget {
  const ContinueWatchingCard({
    super.key,
    required this.title,
    required this.episodeText,
    required this.posterUrl,
    required this.progress,
    required this.onTap,
  });

  final String title;
  final String episodeText;
  final String posterUrl;
  final double progress;
  final VoidCallback onTap;

  @override
  State<ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<ContinueWatchingCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 124,
                child: ClipRRect(
                  borderRadius: AppShapes.card,
                  child: ColoredBox(
                    color: AppColors.surfaceCard,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(widget.posterUrl),
                        // Overlay gelap + tombol play
                        ColoredBox(
                          color: const Color(0x55000000),
                          child: Center(
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.accentViolet.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: AppColors.textWhite,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        // Bar progres di bawah
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 3.5,
                          child: LinearProgressIndicator(
                            value: widget.progress.clamp(0.05, 1.0).toDouble(),
                            color: AppColors.accentViolet,
                            backgroundColor: AppColors.surfaceElevated,
                            minHeight: 3.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                widget.episodeText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.accentViolet,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
