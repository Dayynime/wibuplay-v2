import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/entities.dart';
import 'net_image.dart';

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
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 10, 10),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.accentViolet,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Riwayat Tontonan',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(100),
                  onTap: onSeeAll,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lihat semua',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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

  static const double height = 100;
  static const double width = 272;

  final WatchHistoryEntity entry;
  final VoidCallback onTap;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _pressed = false;

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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Container(
          width: _HistoryCard.width,
          height: _HistoryCard.height,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x0FFFFFFF)),
          ),
          child: Row(
            children: [
              // Poster kecil 2:3
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 84,
                  child: ColoredBox(
                    color: AppColors.surfaceCard,
                    child: NetImage(h.moviePoster, alignment: Alignment.topCenter),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.movieTitle.isEmpty ? 'Tanpa judul' : h.movieTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _episodeLabel,
                              style: const TextStyle(
                                color: AppColors.accentVioletLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (ago.isNotEmpty)
                              TextSpan(
                                text: '  ·  $ago',
                                style: const TextStyle(color: AppColors.textMuted),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      const Spacer(),
                      // Bar progres tipis
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: SizedBox(
                          width: double.infinity,
                          height: 4,
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: ColoredBox(color: AppColors.surfaceElevated),
                              ),
                              FractionallySizedBox(
                                widthFactor: progress == 0 ? 0.03 : progress,
                                heightFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: done
                                          ? const [AppColors.successGreen, AppColors.successGreen]
                                          : const [AppColors.accentVioletDark, AppColors.accentVioletLight],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _remainingLabel,
                        style: TextStyle(
                          color: done ? AppColors.successGreen : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Tombol lanjut
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.accentVioletSubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  done ? Icons.replay_rounded : Icons.play_arrow_rounded,
                  color: AppColors.accentVioletLight,
                  size: 22,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
