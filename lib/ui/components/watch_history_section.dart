import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/entities.dart';
import 'net_image.dart';
import '../redesign/z_kit.dart';
import 'common_components.dart';

/// Section "Riwayat Tontonan" di Beranda (menggantikan section Cuplix).
///
/// Satu kartu per anime (episode terakhir yang ditonton), urut dari yang
/// paling baru. Kartu ringkas horizontal: poster kecil, judul, episode +
/// waktu tonton, bar progres tipis, dan tombol lanjut.
class WatchHistorySection extends StatelessWidget {
  const WatchHistorySection({
    super.key,
    required this.history,
    required this.onResume,
    required this.onSeeAll,
    this.maxItems = 10,
  });

  /// Riwayat dari LocalStore (sudah urut lastWatchedTime terbaru dulu).
  final List<WatchHistoryEntity> history;
  final void Function(WatchHistoryEntity entry) onResume;
  final VoidCallback onSeeAll;
  final int maxItems;

  /// Ambil entri terbaru per anime supaya satu judul tidak muncul berkali-kali.
  static List<WatchHistoryEntity> latestPerAnime(List<WatchHistoryEntity> all, int max) {
    final seen = <String>{};
    final out = <WatchHistoryEntity>[];
    for (final h in all) {
      if (h.movieId.isEmpty || !seen.add(h.movieId)) continue;
      out.add(h);
      if (out.length >= max) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final items = latestPerAnime(history, maxItems);
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        SectionHeader(title: 'Riwayat Tontonan', actionText: 'Lihat semua', onActionClick: onSeeAll),
        const SizedBox(height: 10),
        SizedBox(
          height: _HistoryCard.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _HistoryCard(
              key: ValueKey(items[i].id),
              entry: items[i],
              onTap: () => onResume(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatefulWidget {
  const _HistoryCard({super.key, required this.entry, required this.onTap});

  // Thumbnail 16:9 (236 x 133) + judul + label sisa waktu.
  static const double width = 236;
  static const double height = 133 + 50;

  final WatchHistoryEntity entry;
  final VoidCallback onTap;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {

  String get _episodeLabel {
    final h = widget.entry;
    final t = h.episodeTitle.trim();
    final lower = t.toLowerCase();
    if (t.isNotEmpty && (lower.startsWith('episode') || lower.startsWith('eps') || lower.startsWith('ep '))) {
      return t;
    }
    final idx = h.episodeIndex.trim();
    return idx.isEmpty ? 'Lanjutkan' : 'Episode $idx';
  }

  static String _timeAgo(int millis) {
    if (millis <= 0) return '';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7} mgg lalu';
    return '${diff.inDays ~/ 30} bln lalu';
  }

  String get _remainingLabel {
    final h = widget.entry;
    if (h.durationMs <= 0) return 'Lanjutkan';
    if (h.progressFraction >= 0.95) return 'Selesai';
    final left = Duration(milliseconds: h.durationMs - h.playbackPositionMs);
    final m = left.inMinutes;
    return m < 1 ? 'Sisa < 1 mnt' : 'Sisa $m mnt';
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.entry;
    final ago = _timeAgo(h.lastWatchedTime);
    final progress = h.progressFraction;
    final done = progress >= 0.95;

    // Kartu "Lanjut Nonton" gaya preview: thumbnail lebar, chip episode,
    // tombol play putih, bar progres di dasar gambar.
    return ZPress(
      onTap: widget.onTap,
      child: SizedBox(
        width: _HistoryCard.width,
        height: _HistoryCard.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: _HistoryCard.width,
                height: 133,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: AppColors.surfaceCard,
                      child: NetImage(h.moviePoster, alignment: const Alignment(0, -0.4)),
                    ),
                    const ZScreentone(opacity: 0.12),
                    const DecoratedBox(decoration: BoxDecoration(gradient: zBottomShade)),
                    Positioned(top: 9, right: 9, child: ZChip(_episodeLabel, tone: ZTone.scrim)),
                    Positioned(
                      left: 10,
                      bottom: 12,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(color: Color(0xEBFFFFFF), shape: BoxShape.circle),
                        child: Icon(
                          done ? Icons.replay_rounded : Icons.play_arrow_rounded,
                          color: AppColors.backgroundDark,
                          size: 20,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 4,
                      child: Stack(
                        children: [
                          const Positioned.fill(child: ColoredBox(color: Color(0x2EFFFFFF))),
                          FractionallySizedBox(
                            widthFactor: progress == 0 ? 0.03 : progress.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: ColoredBox(color: done ? AppColors.successGreen : AppColors.accentViolet),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              h.movieTitle.isEmpty ? 'Tanpa judul' : h.movieTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            Text(
              ago.isEmpty ? _remainingLabel : '$_remainingLabel  ·  $ago',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: done ? AppColors.successGreen : AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
