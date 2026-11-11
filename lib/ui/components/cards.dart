import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/entities.dart';
import '../../data/models/anime_item.dart';
import '../../data/models/episode_item.dart';
import 'net_image.dart';
import 'poster_holder.dart';
import '../redesign/z_kit.dart';

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
    this.episodeLabel,
    this.showNewBadge = false,
  });

  final AnimeItem anime;
  final VoidCallback onTap;
  final double width;
  final int? showRank;

  /// Dipakai "Episode Baru": label nomor episode di kiri bawah poster.
  final String? episodeLabel;

  /// Dipakai "Judul Baru": badge "New" di kiri atas poster.
  final bool showNewBadge;

  @override
  State<AnimePosterCard> createState() => _AnimePosterCardState();
}

class _AnimePosterCardState extends State<AnimePosterCard> {
  // Kartu poster redesain Samudra (sama dengan preview): sudut 14, tekstur
  // screentone, chip EP / Baru / status di atas, views di kiri bawah.
  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    final badgeText = anime.status ?? anime.type;
    final subtext = anime.genre ?? anime.year;
    final hasEp = !_blank(widget.episodeLabel);

    return ZPress(
      onTap: () {
        PosterTransitionHolder.url = widget.anime.posterUrl;
        widget.onTap();
      },
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ColoredBox(
                  color: AppColors.surfaceCard,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImage(anime.posterUrl),
                      const ZScreentone(opacity: 0.12),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 56,
                        child: DecoratedBox(decoration: BoxDecoration(gradient: zBottomShade)),
                      ),
                      // Kiri atas: peringkat atau label episode.
                      if (widget.showRank != null)
                        Positioned(top: 7, left: 7, child: ZChip('#${widget.showRank}', tone: ZTone.brand))
                      else if (hasEp)
                        Positioned(
                          top: 7,
                          left: 7,
                          right: widget.showNewBadge ? 52 : 7,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ZChip(widget.episodeLabel!.trim(), tone: ZTone.scrim),
                          ),
                        ),
                      // Kanan atas: "Baru" atau status/tipe.
                      if (widget.showNewBadge)
                        const Positioned(top: 7, right: 7, child: ZChip('Baru', tone: ZTone.brand))
                      else if (!_blank(badgeText) && !hasEp)
                        Positioned(top: 7, right: 7, child: ZChip(badgeText!.trim(), tone: ZTone.scrim)),
                      // Kiri bawah: jumlah ditonton.
                      if (!_blank(anime.views))
                        Positioned(
                          left: 7,
                          bottom: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xB80B0E14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.visibility_rounded, size: 11, color: AppColors.accentVioletLight),
                                const SizedBox(width: 3),
                                Text(
                                  anime.views!,
                                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                                ),
                              ],
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
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            if (!_blank(subtext)) ...[
              const SizedBox(height: 2),
              Text(
                subtext!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ],
          ],
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
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: AppColors.surfaceCard,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(widget.posterUrl),
                        const DecoratedBox(decoration: BoxDecoration(gradient: zBottomShade)),
                        // Tombol play putih kiri bawah (gaya preview)
                        Positioned(
                          left: 10,
                          bottom: 12,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(color: Color(0xEBFFFFFF), shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow_rounded, color: AppColors.backgroundDark, size: 20),
                          ),
                        ),
                        // Bar progres di bawah
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 4,
                          child: LinearProgressIndicator(
                            value: widget.progress.clamp(0.05, 1.0).toDouble(),
                            color: AppColors.accentViolet,
                            backgroundColor: const Color(0x2EFFFFFF),
                            minHeight: 4,
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

/// Port EpisodeListItem (Cards.kt).
class EpisodeListItem extends StatelessWidget {
  const EpisodeListItem({
    super.key,
    required this.episode,
    required this.onTap,
    this.isLocked = false,
    this.download,
    this.onDownloadTap,
  });

  final EpisodeItem episode;
  final VoidCallback onTap;

  /// Status download episode ini (null = belum pernah). Tombol download hanya
  /// tampil kalau [onDownloadTap] diisi dan episode tidak terkunci.
  final DownloadedEpisodeEntity? download;
  final VoidCallback? onDownloadTap;

  /// Episode terbaru khusus Premium (ikon gembok menggantikan ikon play).
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    final index = episode.index ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: AppShapes.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: AppColors.surfaceCard,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NetImage(episode.imageUrl),
                          ColoredBox(
                            color: isLocked ? const Color(0x99000000) : const Color(0x44000000),
                            child: Center(
                              child: Icon(
                                isLocked ? Icons.lock : Icons.play_arrow,
                                color: AppColors.textWhite,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Episode $index',
                        style: const TextStyle(
                          color: AppColors.accentViolet,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        episode.title ?? 'Episode $index',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_blank(episode.views))
                        Text(
                          '${episode.views} tayangan',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                        ),
                    ],
                  ),
                ),
                if (onDownloadTap != null && !isLocked)
                  _DownloadButton(entry: download, onTap: onDownloadTap!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ikon status download di kanan item episode: belum ada / progres / selesai / gagal.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.entry, required this.onTap});

  final DownloadedEpisodeEntity? entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final Widget icon;
    if (e == null) {
      icon = const Icon(Icons.download_outlined, color: AppColors.textMuted, size: 22);
    } else if (e.isActive) {
      final p = e.totalBytes > 0 ? (e.downloadedBytes / e.totalBytes).clamp(0.0, 1.0) : null;
      icon = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          value: p,
          strokeWidth: 2.2,
          color: AppColors.accentViolet,
        ),
      );
    } else if (e.isCompleted) {
      icon = const Icon(Icons.download_done, color: Color(0xFF4CAF50), size: 22);
    } else {
      icon = const Icon(Icons.error_outline, color: Color(0xFFE57373), size: 22);
    }
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(padding: const EdgeInsets.all(8), child: icon),
    );
  }
}
