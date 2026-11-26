import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anime_item.dart';
import '../redesign/z_kit.dart';
import 'net_image.dart';
import 'poster_holder.dart';

/// Kartu "Tayang berikutnya" di atas Jadwal Hari Ini: hitung mundur ke jam
/// tayang terdekat, angkanya berputar seperti papan split-flap stasiun.
///
/// Jam diambil dari keyTime ("yyyy-MM-dd HH:mm:ss"); yang dipakai cuma
/// HH:mm (sama seperti halaman Jadwal), dianggap jam hari ini. Kalau semua
/// sudah lewat, kartu tidak tampil.
class NextAiringBoard extends StatefulWidget {
  const NextAiringBoard({super.key, required this.items, required this.onAnimeClick});

  final List<AnimeItem> items;
  final ValueChanged<String> onAnimeClick;

  @override
  State<NextAiringBoard> createState() => _NextAiringBoardState();
}

class _NextAiringBoardState extends State<NextAiringBoard> {
  Timer? _timer;
  AnimeItem? _next;
  DateTime? _at;

  @override
  void initState() {
    super.initState();
    _pick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_at != null && DateTime.now().isAfter(_at!)) _pick();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(NextAiringBoard old) {
    super.didUpdateWidget(old);
    if (!identical(old.items, widget.items)) _pick();
  }

  void _pick() {
    final now = DateTime.now();
    AnimeItem? best;
    DateTime? bestAt;
    for (final a in widget.items) {
      final k = a.keyTime ?? '';
      final i = k.indexOf(' ');
      if (i < 0 || k.length < i + 6) continue;
      final hh = int.tryParse(k.substring(i + 1, i + 3));
      final mm = int.tryParse(k.substring(i + 4, i + 6));
      if (hh == null || mm == null) continue;
      final at = DateTime(now.year, now.month, now.day, hh, mm);
      if (!at.isAfter(now)) continue;
      if (bestAt == null || at.isBefore(bestAt)) {
        best = a;
        bestAt = at;
      }
    }
    _next = best;
    _at = bestAt;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _next, at = _at;
    if (a == null || at == null) return const SizedBox.shrink();
    final left = at.difference(DateTime.now());
    final secs = math.max(0, left.inSeconds);
    String two(int v) => v.toString().padLeft(2, '0');
    final clock = '${two(secs ~/ 3600)}:${two(secs ~/ 60 % 60)}:${two(secs % 60)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ZPress(
        onTap: () {
          final id = a.id;
          if (id == null) return;
          PosterTransitionHolder.url = a.posterUrl;
          widget.onAnimeClick(id);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x0FFFFFFF)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 54,
                  height: 76,
                  child: ColoredBox(color: AppColors.surfaceVariantDark, child: NetImage(a.posterUrl)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title ?? 'Anime',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        _Pulse(),
                        SizedBox(width: 6),
                        Text('Tayang berikutnya',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          for (var i = 0; i < clock.length; i++)
                            clock[i] == ':'
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 3),
                                    child: Text(':',
                                        style: TextStyle(color: AppColors.textMuted, fontSize: 16, fontWeight: FontWeight.w800)),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.only(right: 3),
                                    child: FlapDigit(clock[i], key: ValueKey('flap-$i')),
                                  ),
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
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.25).animate(_c),
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(color: AppColors.accentViolet, shape: BoxShape.circle),
        ),
      );
}

/// Satu keping papan split-flap: saat karakternya berubah, keping atas
/// melipat turun (karakter lama) lalu keping baru membuka.
class FlapDigit extends StatefulWidget {
  const FlapDigit(this.char, {super.key});

  final String char;

  @override
  State<FlapDigit> createState() => _FlapDigitState();
}

class _FlapDigitState extends State<FlapDigit> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 340), value: 1);
  late String _old = widget.char;

  @override
  void didUpdateWidget(FlapDigit old) {
    super.didUpdateWidget(old);
    if (old.char != widget.char) {
      _old = old.char;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const TextStyle _style = TextStyle(
    color: AppColors.textWhite,
    fontSize: 17,
    fontWeight: FontWeight.w800,
    fontFamily: 'monospace',
    height: 1,
  );

  Widget _face(String c) => Container(
        width: 21,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF0F131B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0x12FFFFFF)),
        ),
        child: Text(c, style: _style),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final showOld = t < 0.5;
        final angle = showOld ? -t * 2 * (math.pi / 2) : (1 - t) * 2 * (math.pi / 2);
        return Stack(
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.006)
                ..rotateX(angle),
              child: _face(showOld ? _old : widget.char),
            ),
            // Garis belahan papan.
            Positioned(
              left: 0,
              right: 0,
              top: 14.5,
              child: Container(height: 1, color: const Color(0xCC000000)),
            ),
          ],
        );
      },
    );
  }
}
