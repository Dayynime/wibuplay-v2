import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../components/net_image.dart';

enum TimelineKind { watch, comment }

/// Satu kejadian di timeline (nonton episode atau komentar).
class TimelineEntry {
  const TimelineEntry({
    required this.time,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.posterUrl,
    this.progress,
    this.onTap,
  });

  final DateTime time;
  final TimelineKind kind;
  final String title;
  final String subtitle;
  final String? posterUrl;

  /// 0..1, cuma untuk [TimelineKind.watch].
  final double? progress;
  final VoidCallback? onTap;
}

/// Timeline vertikal: aktivitas dikelompokkan per hari (Hari ini / Kemarin /
/// tanggal), garis tipis di kiri, node kotak, item muncul bertahap.
/// Semua sudut kotak (tanpa border radius).
class ProfileTimeline extends StatelessWidget {
  const ProfileTimeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  static const _bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  static String _dayLabel(DateTime t, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    return '${t.day} ${_bulan[t.month - 1]} ${t.year}';
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final children = <Widget>[];
    String? lastLabel;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final label = _dayLabel(e.time, now);
      final isFirstInDay = label != lastLabel;
      lastLabel = label;
      final isLast = i == entries.length - 1;
      children.add(_AnimatedIn(
        index: i,
        child: _TimelineRow(
          entry: e,
          dayLabel: isFirstInDay ? label : null,
          time: _hm(e.time),
          isLast: isLast,
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _AnimatedIn extends StatelessWidget {
  const _AnimatedIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ms = 320 + (index > 10 ? 10 : index) * 70;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.dayLabel,
    required this.time,
    required this.isLast,
  });

  final TimelineEntry entry;
  final String? dayLabel;
  final String time;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isWatch = entry.kind == TimelineKind.watch;
    final nodeColor = isWatch ? AppColors.accentViolet : AppColors.accentVioletLight;
    final hasPoster = entry.posterUrl != null && entry.posterUrl!.isNotEmpty;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Stack(
              children: [
                Positioned(
                  left: 4,
                  top: dayLabel != null ? 6 : 0,
                  bottom: isLast ? null : 0,
                  height: isLast ? 14 : null,
                  child: Container(width: 1, color: const Color(0x26FFFFFF)),
                ),
                Positioned(
                  left: 0,
                  top: dayLabel != null ? 22 : 8,
                  child: Container(width: 9, height: 9, color: nodeColor),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dayLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        dayLabel!,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: entry.onTap,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasPoster) ...[
                          SizedBox(
                            width: 46,
                            height: 64,
                            child: ClipRect(child: NetImage(entry.posterUrl!)),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isWatch ? Icons.play_arrow : Icons.chat_bubble_outline,
                                    size: 13,
                                    color: nodeColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isWatch ? 'Nonton' : 'Komentar',
                                    style: TextStyle(
                                      color: nodeColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    time,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                entry.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              if (entry.progress != null) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 2,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween<double>(begin: 0, end: entry.progress!),
                                    duration: const Duration(milliseconds: 900),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, v, _) => LinearProgressIndicator(
                                      value: v,
                                      minHeight: 2,
                                      color: AppColors.accentViolet,
                                      backgroundColor: Colors.white12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
