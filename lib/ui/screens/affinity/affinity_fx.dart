import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/affinity_models.dart';

/// Gaya kanji cap (Noto Serif JP via google_fonts, aman kalau gagal).
TextStyle affinityKanjiStyle({required Color color, required double size}) {
  final base = TextStyle(color: color, fontSize: size, height: 1, fontWeight: FontWeight.w900);
  try {
    return GoogleFonts.getFont('Noto Serif JP', textStyle: base);
  } catch (_) {
    return base;
  }
}

/// Animasi dimatikan kalau sistem minta kurangi gerakan.
bool affinityReduceMotion(BuildContext context) => MediaQuery.disableAnimationsOf(context);

// ---------------------------------------------------------------------------
// Muncul berurutan (sekali saat halaman dibuka)
// ---------------------------------------------------------------------------

class AffinityRise extends StatefulWidget {
  const AffinityRise({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<AffinityRise> createState() => _AffinityRiseState();
}

class _AffinityRiseState extends State<AffinityRise> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: const Cubic(0.2, 0.8, 0.2, 1));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: 70 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (affinityReduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - _a.value)), child: child),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cap kanji (hanko): dicap -> membal -> tinta merembes. Opsi detak & kilatan.
// ---------------------------------------------------------------------------

class AffinitySeal extends StatefulWidget {
  const AffinitySeal({
    super.key,
    required this.type,
    this.size = 22,
    this.delay = Duration.zero,
    this.stamp = true,
    this.beat = false,
    this.clash = false,
  });

  final AffinityType type;
  final double size;
  final Duration delay;

  /// Animasi dicap saat muncul.
  final bool stamp;

  /// Detak jantung berulang (Soulmate).
  final bool beat;

  /// Kilatan pedang bersilang sesekali (Rival).
  final bool clash;

  @override
  State<AffinitySeal> createState() => _AffinitySealState();
}

class _AffinitySealState extends State<AffinitySeal> with TickerProviderStateMixin {
  late final AnimationController _stamp =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  AnimationController? _loop;

  @override
  void initState() {
    super.initState();
    if (!widget.stamp) {
      _stamp.value = 1;
      _startLoop(rebuild: false);
    } else {
      Future<void>.delayed(widget.delay, () {
        if (!mounted) return;
        _stamp.forward().whenComplete(_startLoop);
      });
    }
  }

  void _startLoop({bool rebuild = true}) {
    if (!mounted || _loop != null || (!widget.beat && !widget.clash)) return;
    _loop = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.beat ? 2400 : 4000),
    )..repeat();
    if (rebuild) setState(() {});
  }

  @override
  void dispose() {
    _stamp.dispose();
    _loop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.type.color;
    final s = widget.size;
    final seal = Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: s >= 40 ? 2 : 1.5)),
      child: Text(
        widget.type.kanji,
        style: affinityKanjiStyle(color: c, size: s * 0.5),
      ),
    );
    if (affinityReduceMotion(context)) return seal;

    final loop = _loop;
    return AnimatedBuilder(
      animation: Listenable.merge([_stamp, if (loop != null) loop]),
      builder: (_, __) {
        // 0..0.45 = cap jatuh & membal, 0.35..1 = tinta merembes.
        final t = _stamp.value;
        final p = (t / 0.45).clamp(0.0, 1.0);
        double scale;
        double rot;
        if (p < 0.6) {
          final k = Curves.easeIn.transform(p / 0.6);
          scale = 1.9 - (1.9 - 0.88) * k;
          rot = -0.31 + (0.31 + 0.05) * k;
        } else {
          final k = Curves.easeOut.transform((p - 0.6) / 0.4);
          scale = 0.88 + 0.12 * k;
          rot = 0.05 * (1 - k);
        }
        final opacity = (p * 3).clamp(0.0, 1.0);
        final ink = ((t - 0.35) / 0.65).clamp(0.0, 1.0);

        var beat = 1.0;
        var clash = 0.0;
        if (loop != null) {
          final v = loop.value;
          if (widget.beat) {
            // lub-dub
            if (v < 0.08) {
              beat = 1 + 0.18 * math.sin(v / 0.08 * math.pi);
            } else if (v > 0.16 && v < 0.24) {
              beat = 1 + 0.1 * math.sin((v - 0.16) / 0.08 * math.pi);
            }
          }
          if (widget.clash && v < 0.12) clash = v < 0.04 ? v / 0.04 : 1 - (v - 0.04) / 0.08;
        }

        return SizedBox(
          width: s,
          height: s,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (ink > 0 && ink < 1)
                Transform.scale(
                  scale: 1 + 0.9 * Curves.easeOut.transform(ink),
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.withValues(alpha: 0.7 * (1 - ink)), width: 1.5),
                    ),
                  ),
                ),
              Opacity(
                opacity: opacity,
                child: Transform.rotate(
                  angle: rot,
                  child: Transform.scale(scale: (t == 0 ? 1.9 : scale) * beat, child: seal),
                ),
              ),
              if (clash > 0) ...[
                for (final a in const [-0.61, 0.61])
                  Transform.rotate(
                    angle: a,
                    child: Container(
                      width: s * 1.4,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.white.withValues(alpha: clash), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Cincin level di sekitar avatar: tergambar memutar sesuai progres.
// ---------------------------------------------------------------------------

class AffinityLevelRing extends StatefulWidget {
  const AffinityLevelRing({
    super.key,
    required this.color,
    required this.progress,
    required this.size,
    required this.child,
    this.delay = Duration.zero,
  });

  final Color color;
  final double progress;
  final double size;
  final Widget child;
  final Duration delay;

  @override
  State<AffinityLevelRing> createState() => _AffinityLevelRingState();
}

class _AffinityLevelRingState extends State<AffinityLevelRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = affinityReduceMotion(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(
                  painter: _RingPainter(
                    color: widget.color,
                    progress: widget.progress *
                        (reduce ? 1 : const Cubic(0.3, 0.7, 0.2, 1).transform(_c.value)),
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.06),
    );
    if (progress <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

// ---------------------------------------------------------------------------
// Slot kosong: lingkaran putus-putus berputar pelan.
// ---------------------------------------------------------------------------

class AffinityEmptySlot extends StatefulWidget {
  const AffinityEmptySlot({super.key, required this.size});

  final double size;

  @override
  State<AffinityEmptySlot> createState() => _AffinityEmptySlotState();
}

class _AffinityEmptySlotState extends State<AffinityEmptySlot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (affinityReduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: RotationTransition(
                turns: _c,
                child: const CustomPaint(painter: _DashedCirclePainter()),
              ),
            ),
          ),
          const Icon(Icons.add_rounded, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.16);
    const n = 22;
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, math.pi * 2 / n * 0.5, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Kelopak sakura jatuh pelan (baris Senpai · Kouhai).
// ---------------------------------------------------------------------------

class AffinitySakura extends StatefulWidget {
  const AffinitySakura({super.key, this.color = const Color(0xFFE8A0B0)});

  final Color color;

  @override
  State<AffinitySakura> createState() => _AffinitySakuraState();
}

class _AffinitySakuraState extends State<AffinitySakura> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!affinityReduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (affinityReduceMotion(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _SakuraPainter(_c, widget.color)),
      ),
    );
  }
}

class _SakuraPainter extends CustomPainter {
  _SakuraPainter(this.anim, this.color) : super(repaint: anim);

  final Animation<double> anim;
  final Color color;

  static const _n = 7;

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k < _n; k++) {
      final period = 0.5 + (k % 3) * 0.13; // bagian siklus 12 dtk
      final offset = k * 0.075;
      final t = ((anim.value - offset) % 1.0) / period;
      if (t < 0 || t > 1) continue;
      final x0 = size.width * (0.08 + k * 0.13);
      final drift = (k.isOdd ? -1 : 1) * (18.0 + k * 4) * t + math.sin(t * math.pi * 2) * 6;
      final y = -12 + (size.height + 24) * t;
      final op = t < 0.1 ? t / 0.1 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
      canvas.save();
      canvas.translate(x0 + drift, y);
      canvas.rotate(t * math.pi * 2.3);
      final path = Path()
        ..moveTo(0, -3)
        ..quadraticBezierTo(4, -3, 4, 0)
        ..quadraticBezierTo(0, 0, 0, 3)
        ..quadraticBezierTo(-4, 3, -4, 0)
        ..quadraticBezierTo(0, 0, 0, -3)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.7 * op));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SakuraPainter old) => false;
}

// ---------------------------------------------------------------------------
// Benang merah takdir (Soulmate): garis putus-putus yang mengalir.
// ---------------------------------------------------------------------------

class AffinityRedThread extends StatefulWidget {
  const AffinityRedThread({super.key, this.color = const Color(0xFFE4344A)});

  final Color color;

  @override
  State<AffinityRedThread> createState() => _AffinityRedThreadState();
}

class _AffinityRedThreadState extends State<AffinityRedThread> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!affinityReduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(child: CustomPaint(painter: _ThreadPainter(_c, widget.color))),
    );
  }
}

class _ThreadPainter extends CustomPainter {
  _ThreadPainter(this.anim, this.color) : super(repaint: anim);

  final Animation<double> anim;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.16, h * 0.96)
      ..cubicTo(w * 0.33, h * 1.24, w * 0.67, h * 1.24, w * 0.84, h * 0.96);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.85);
    const dash = 3.0;
    const gap = 5.0;
    final shift = anim.value * (dash + gap);
    for (final m in path.computeMetrics()) {
      var d = -shift;
      while (d < m.length) {
        final s = d.clamp(0.0, m.length);
        final e = (d + dash).clamp(0.0, m.length);
        if (e > s) canvas.drawPath(m.extractPath(s, e), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThreadPainter old) => false;
}

/// Dua avatar yang pelan-pelan saling mendekat (Soulmate).
class AffinityLean extends StatefulWidget {
  const AffinityLean({super.key, required this.left, required this.right, required this.size, required this.overlap});

  final Widget left;
  final Widget right;

  /// Ukuran tiap avatar.
  final double size;
  final double overlap;

  @override
  State<AffinityLean> createState() => _AffinityLeanState();
}

class _AffinityLeanState extends State<AffinityLean> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!affinityReduceMotion(context) && !_c.isAnimating) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2 - widget.overlap + 6,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final d = 3 * Curves.easeInOut.transform(_c.value);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: d, top: 0, child: widget.left),
              Positioned(left: s - widget.overlap + 6 - d, top: 0, child: widget.right),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bar progres: terisi saat muncul + kilau lewat sesekali.
// ---------------------------------------------------------------------------

class AffinitySheenBar extends StatefulWidget {
  const AffinitySheenBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 3,
    this.delay = Duration.zero,
  });

  final double value;
  final Color color;
  final double height;
  final Duration delay;

  @override
  State<AffinitySheenBar> createState() => _AffinitySheenBarState();
}

class _AffinitySheenBarState extends State<AffinitySheenBar> with TickerProviderStateMixin {
  late final AnimationController _fill =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  late final AnimationController _sheen =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      _fill.forward();
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        if (mounted && !affinityReduceMotion(context)) _sheen.repeat();
      });
    });
  }

  @override
  void dispose() {
    _fill.dispose();
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = affinityReduceMotion(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0x14FFFFFF))),
            AnimatedBuilder(
              animation: Listenable.merge([_fill, _sheen]),
              builder: (_, __) {
                final f = reduce ? 1.0 : const Cubic(0.3, 0.7, 0.2, 1).transform(_fill.value);
                final s = _sheen.value;
                return FractionallySizedBox(
                  widthFactor: (widget.value * f).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: (s > 0 && s < 0.4) ? null : widget.color,
                      gradient: s > 0 && s < 0.4
                          ? LinearGradient(
                              colors: [widget.color, Colors.white.withValues(alpha: 0.7), widget.color],
                              stops: [
                                ((s / 0.4) - 0.2).clamp(0.0, 1.0),
                                (s / 0.4).clamp(0.0, 1.0),
                                ((s / 0.4) + 0.2).clamp(0.0, 1.0),
                              ],
                            )
                          : null,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Angka yang menghitung naik saat muncul.
class AffinityCountUp extends StatelessWidget {
  const AffinityCountUp({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (affinityReduceMotion(context)) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text('${v.round()}', style: style),
    );
  }
}

/// Efek tekan kecil (avatar mengecil saat ditekan).
class AffinityTap extends StatefulWidget {
  const AffinityTap({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<AffinityTap> createState() => _AffinityTapState();
}

class _AffinityTapState extends State<AffinityTap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
