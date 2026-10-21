import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/wallpaper_models.dart';

/// Banner Event Limited di atas layar Spin: hitung mundur selesai (event
/// berjalan) atau mulai (event akan datang). Jam diambil dari server lewat
/// [clockOffset], jadi mengubah jam HP tidak berpengaruh.
///
/// [onBoundary] dipanggil saat event mulai/selesai supaya pool dimuat ulang.
class WallpaperEventBanner extends StatefulWidget {
  const WallpaperEventBanner({
    super.key,
    required this.events,
    required this.clockOffset,
    this.onBoundary,
  });

  final List<WallpaperEvent> events;
  final Duration clockOffset;
  final VoidCallback? onBoundary;

  @override
  State<WallpaperEventBanner> createState() => _WallpaperEventBannerState();
}

class _WallpaperEventBannerState extends State<WallpaperEventBanner> with SingleTickerProviderStateMixin {
  Timer? _tick;
  bool _fired = false;

  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  DateTime get _now => DateTime.now().toUtc().add(widget.clockOffset);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void didUpdateWidget(WallpaperEventBanner old) {
    super.didUpdateWidget(old);
    if (old.events != widget.events) _fired = false;
  }

  void _onTick() {
    if (!mounted) return;
    final now = _now;
    // lewat batas mulai/selesai -> minta muat ulang sekali (beri jeda 2 dtk
    // supaya server pasti sudah melewati batas yang sama)
    final crossed = widget.events.any((e) =>
        (now.isAfter(e.startsAt.add(const Duration(seconds: 2))) &&
            now.isBefore(e.startsAt.add(const Duration(seconds: 4)))) ||
        (now.isAfter(e.endsAt.add(const Duration(seconds: 2))) &&
            now.isBefore(e.endsAt.add(const Duration(seconds: 4)))));
    if (crossed && !_fired) {
      _fired = true;
      widget.onBoundary?.call();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final visible = widget.events.where((e) => now.isBefore(e.endsAt)).toList()
      ..sort((a, b) {
        // yang berjalan dulu, lalu yang paling cepat mulai
        final ra = a.isRunning(now) ? 0 : 1;
        final rb = b.isRunning(now) ? 0 : 1;
        if (ra != rb) return ra - rb;
        return a.startsAt.compareTo(b.startsAt);
      });
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final e in visible.take(2))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _card(e, now),
          ),
      ],
    );
  }

  Widget _card(WallpaperEvent e, DateTime now) {
    final running = e.isRunning(now);
    final countdown = formatEventCountdown(running ? e.endsAt.difference(now) : e.startsAt.difference(now));
    const ink = Color(0xFF1C2230);
    const limited = WallpaperRarity.limited;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: running ? const [BoxShadow(color: Color(0x55E8ECF2), blurRadius: 18)] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: running
                        ? limited.gradient
                        : const LinearGradient(colors: [AppColors.surfaceVariantDark, AppColors.surfaceElevated]),
                  ),
                ),
              ),
              if (running)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _shine,
                    builder: (_, __) {
                      final t = (_shine.value / 0.55).clamp(0.0, 1.0);
                      final x = -1.6 + t * 3.2;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(x - 0.6, -1),
                            end: Alignment(x + 0.6, 1),
                            colors: const [Color(0x00FFFFFF), Color(0xB3FFFFFF), Color(0x00FFFFFF)],
                            stops: const [0.4, 0.5, 0.6],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running ? const Color(0x331C2230) : const Color(0x14FFFFFF),
                      ),
                      child: Icon(
                        running ? Icons.auto_awesome : Icons.schedule_rounded,
                        color: running ? ink : const Color(0xFFD7DCE4),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            running ? 'EVENT LIMITED BERLANGSUNG' : 'EVENT LIMITED SEGERA',
                            style: TextStyle(
                              color: running ? ink.withValues(alpha: 0.75) : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: running ? ink : AppColors.textWhite,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            running
                                ? '${e.itemCount} wallpaper Limited • sampai ${formatEventTime(e.endsAt)}'
                                : 'Mulai ${formatEventTime(e.startsAt)}',
                            style: TextStyle(
                              color: running ? ink.withValues(alpha: 0.7) : AppColors.textMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          running ? 'Berakhir' : 'Mulai dalam',
                          style: TextStyle(
                            color: running ? ink.withValues(alpha: 0.7) : AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          countdown,
                          style: TextStyle(
                            color: running ? ink : AppColors.textWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
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
