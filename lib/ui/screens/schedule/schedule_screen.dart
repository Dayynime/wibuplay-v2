import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/anime_item.dart';
import '../../components/common_components.dart';
import '../../components/net_image.dart';
import '../../components/poster_holder.dart';
import '../../components/shimmer.dart';
import 'schedule_controller.dart';

const Color _outline = AppColors.surfaceVariantDark;
const Color _timeColor = Color(0xFFFFC107);

// Tinggi tiap baris dibuat tetap supaya posisi scroll tiap hari bisa dihitung
// langsung (dipakai tombol navigasi hari & penanda hari di atas).
const double _entryHeight = 122;
const double _emptyHeight = 56;
const double _navHeight = 64;
const double _gutter = 56;

sealed class _Row {
  const _Row(this.day);
  final int day;
  double get height;
}

class _Entry extends _Row {
  const _Entry(this.anime, super.day, this.isFirstOfDay);
  final AnimeItem anime;
  final bool isFirstOfDay;
  @override
  double get height => _entryHeight;
}

class _Empty extends _Row {
  const _Empty(super.day);
  @override
  double get height => _emptyHeight;
}

class _Nav extends _Row {
  const _Nav(super.day);
  @override
  double get height => _navHeight;
}

/// Port ScheduleScreen.kt (versi timeline Zenime).
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key, required this.onAnimeClick});

  final ValueChanged<String> onAnimeClick;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<int> _currentDay = ValueNotifier<int>(0);

  List<DaySection>? _builtFor;
  List<_Row> _rows = const [];
  List<double> _offsets = const []; // offset awal tiap baris
  final Map<int, double> _dayStart = {};
  bool _didInitialJump = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _currentDay.dispose();
    super.dispose();
  }

  void _build(List<DaySection> sections) {
    if (identical(_builtFor, sections)) return;
    _builtFor = sections;
    final rows = <_Row>[];
    for (var s = 0; s < sections.length; s++) {
      final section = sections[s];
      if (section.anime.isEmpty) {
        rows.add(_Empty(section.dayIndex));
      } else {
        for (var i = 0; i < section.anime.length; i++) {
          rows.add(_Entry(section.anime[i], section.dayIndex, i == 0));
        }
      }
      if (s != sections.length - 1) rows.add(_Nav(section.dayIndex));
    }
    final offsets = <double>[];
    var y = 4.0; // padding atas list
    _dayStart.clear();
    for (final r in rows) {
      offsets.add(y);
      if ((r is _Entry && r.isFirstOfDay) || r is _Empty) {
        _dayStart.putIfAbsent(r.day, () => y);
      }
      y += r.height;
    }
    _rows = rows;
    _offsets = offsets;
  }

  int _dayAtOffset(double offset) {
    if (_rows.isEmpty) return 0;
    var lo = 0, hi = _rows.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_offsets[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _rows[lo].day;
  }

  void _onScroll() {
    if (!_scroll.hasClients || _rows.isEmpty) return;
    final p = _scroll.position;
    final day = p.pixels >= p.maxScrollExtent - 1
        ? _rows.last.day
        : _dayAtOffset(p.pixels);
    if (_currentDay.value != day) _currentDay.value = day;
  }

  void _jumpToDay(int day, {bool animate = true}) {
    final target = _dayStart[day];
    if (target == null || !_scroll.hasClients) return;
    final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
    _currentDay.value = day;
    if (animate) {
      _scroll.animateTo(
        clamped,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(clamped);
    }
  }

  void _scheduleInitialJump(int todayIndex) {
    if (_didInitialJump) return;
    _didInitialJump = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _jumpToDay(todayIndex, animate: false);
      _onScroll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(scheduleControllerProvider);
    final notifier = ref.read(scheduleControllerProvider.notifier);

    final Widget body;
    if (ui.isLoading) {
      body = const _ScheduleLoadingSkeleton();
    } else if (ui.error != null) {
      body = Center(
        child: ErrorState(message: ui.error!, onRetry: notifier.loadFullWeek),
      );
    } else if (ui.sections.every((s) => s.anime.isEmpty)) {
      body = const Center(
        child: EmptyState(
          title: 'Tidak Ada Rilis',
          subtitle: 'Belum ada anime yang terjadwal minggu ini.',
          icon: Icons.calendar_today_outlined,
        ),
      );
    } else {
      _build(ui.sections);
      _scheduleInitialJump(ui.todayIndex);
      body = Column(
        children: [
          _DayHeader(current: _currentDay, sections: ui.sections),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 4, 16, 135),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final row = _rows[i];
                return SizedBox(
                  height: row.height,
                  child: switch (row) {
                    _Entry() => _TimelineEntry(
                        anime: row.anime,
                        onTap: () {
                          final id = row.anime.id;
                          if (id != null) widget.onAnimeClick(id);
                        },
                      ),
                    _Empty() => _EmptyDayRow(
                        name: ScheduleController.dayNames[row.day],
                      ),
                    _Nav() => _DayNavRow(
                        prev: row.day - 1 >= 0
                            ? ScheduleController.dayNames[row.day - 1]
                            : null,
                        next: row.day + 1 < ScheduleController.dayNames.length
                            ? ScheduleController.dayNames[row.day + 1]
                            : null,
                        onPrev: () => _jumpToDay(row.day - 1),
                        onNext: () => _jumpToDay(row.day + 1),
                      ),
                  },
                );
              },
            ),
          ),
        ],
      );
    }

    return ColoredBox(
      color: AppColors.backgroundDark,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Jadwal Rilis',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Jadwal penayangan episode baru setiap harinya',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Pil hari yang sedang terlihat + jumlah anime. Ikut berubah saat di-scroll.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.current, required this.sections});

  final ValueNotifier<int> current;
  final List<DaySection> sections;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: current,
      builder: (context, day, _) {
        final i = day.clamp(0, sections.length - 1);
        final count = sections[i].anime.length;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: const BoxDecoration(
                  color: AppColors.accentViolet,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.all(Radius.circular(100)),
                ),
                child: Text(
                  sections[i].dayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: _outline),
                ),
                child: Text(
                  '$count Anime',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.anime, required this.onTap});

  final AnimeItem anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = formatKeyTime(anime.keyTime);
    final noTime = time == '--:--';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _gutter,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(
                child: Align(
                  child: Container(width: 2, color: _outline),
                ),
              ),
              Column(
                children: [
                  const SizedBox(height: 6),
                  Text(
                    time,
                    style: TextStyle(
                      color: noTime ? AppColors.textSecondary : _timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: AppColors.accentViolet,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ScheduleAnimeCard(anime: anime, onTap: onTap),
          ),
        ),
      ],
    );
  }
}

class _EmptyDayRow extends StatelessWidget {
  const _EmptyDayRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _gutter,
          child: Center(
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: _outline,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Tidak ada rilis hari $name',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _DayNavRow extends StatelessWidget {
  const _DayNavRow({
    required this.prev,
    required this.next,
    required this.onPrev,
    required this.onNext,
  });

  final String? prev;
  final String? next;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: _gutter, top: 4, bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (prev != null)
            _NavPill(
              label: prev!,
              icon: Icons.arrow_back,
              iconFirst: true,
              filled: false,
              onTap: onPrev,
            )
          else
            const SizedBox(width: 1),
          if (next != null)
            _NavPill(
              label: next!,
              icon: Icons.arrow_forward,
              iconFirst: false,
              filled: true,
              onTap: onNext,
            )
          else
            const SizedBox(width: 1),
        ],
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.label,
    required this.icon,
    required this.iconFirst,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool iconFirst;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Icon(icon, color: Colors.white, size: 14),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ];
    return Material(
      color: filled ? AppColors.accentViolet : AppColors.surfaceCard,
      shape: StadiumBorder(
        side: filled ? BorderSide.none : const BorderSide(color: _outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: iconFirst ? children : children.reversed.toList(),
          ),
        ),
      ),
    );
  }
}

/// Port ScheduleHorizontalCard (Zenime).
class ScheduleAnimeCard extends StatelessWidget {
  const ScheduleAnimeCard({super.key, required this.anime, required this.onTap});

  final AnimeItem anime;
  final VoidCallback onTap;

  bool _has(String? s) => s != null && s.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: _outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          PosterTransitionHolder.url = anime.posterUrl;
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: AppColors.surfaceVariantDark,
                      child: NetImage(anime.posterUrl),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title ?? 'Tanpa Judul',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (_has(anime.type)) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentViolet,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              anime.type!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (_has(anime.status))
                          Flexible(
                            child: Text(
                              anime.status!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_has(anime.time)) ...[
                      const SizedBox(height: 2),
                      Text(
                        anime.time!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleLoadingSkeleton extends StatelessWidget {
  const _ScheduleLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 8),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        return Row(
          children: [
            const SizedBox(width: _gutter),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _outline),
                ),
                child: Row(
                  children: [
                    ShimmerBox(
                      width: 60,
                      height: 90,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.9,
                            child: ShimmerBox(
                              height: 16,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ShimmerBox(
                            width: 60,
                            height: 12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
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
}
