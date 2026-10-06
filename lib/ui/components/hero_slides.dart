import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/clan_models.dart';
import '../../data/models/support_models.dart';
import '../../data/models/xp_models.dart';
import 'game_badges.dart';
import '../screens/profile/public_profile_screen.dart';

const Color heroGold = Color(0xFFFFC107);
const Color heroPink = Color(0xFFFF5C8A);
const Color _silver = Color(0xFFC7CDD8);
const Color _bronze = Color(0xFFCE8946);
const Color _ink = Color(0xFF15213B);
const Color _xpBlue = Color(0xFF4FC3F7);
const Color _clanPurple = Color(0xFFB57BFF);

String _compactCount(int v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
  return '$v';
}

String _compactRupiah(int v) {
  if (v >= 1000000) return 'Rp${(v / 1000000).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')}jt';
  if (v >= 1000) return 'Rp${(v / 1000).round()}rb';
  return 'Rp$v';
}

Color _rankColor(int rank) => switch (rank) {
      1 => heroGold,
      2 => _silver,
      3 => _bronze,
      _ => const Color(0x1FFFFFFF),
    };

/// Ambil potongan [start]..[end] dari timeline [t] (0..1) lalu lewatkan lewat
/// [curve]. Hasil 0 sebelum [start], 1 setelah [end].
double _seg(double t, double start, double end, [Curve curve = Curves.easeOutCubic]) {
  if (t <= start) return 0;
  if (t >= end) return 1;
  return curve.transform((t - start) / (end - start));
}

// ---------------------------------------------------------------------------
// Infrastruktur animasi
// ---------------------------------------------------------------------------

/// Pemilik dua controller untuk satu slide:
///  - `enter`: animasi masuk sekali jalan (stagger), main tiap slide aktif.
///  - `loop` : animasi ambient berulang (glow, ring, kilau, partikel).
/// Keduanya cuma jalan selama slide kelihatan ([active]) supaya hemat baterai,
/// dan mati kalau HP diset "hapus animasi".
class _SlideMotion extends StatefulWidget {
  const _SlideMotion({
    required this.active,
    required this.builder,
    this.enterDuration = const Duration(milliseconds: 1500),
    this.loopDuration = const Duration(seconds: 6),
  });

  final bool active;
  final Duration enterDuration;
  final Duration loopDuration;
  final Widget Function(BuildContext context, Animation<double> enter, Animation<double> loop) builder;

  @override
  State<_SlideMotion> createState() => _SlideMotionState();
}

class _SlideMotionState extends State<_SlideMotion> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: widget.enterDuration);
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: widget.loopDuration);
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(_SlideMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (!widget.active) {
      // Slide sudah di luar layar: reset supaya animasi masuk main lagi nanti.
      _enter.value = 0;
      _loop.stop();
      return;
    }
    if (_reduce) {
      _enter.value = 1;
      _loop.stop();
      return;
    }
    if (_enter.status == AnimationStatus.dismissed) _enter.forward();
    if (!_loop.isAnimating) _loop.repeat();
  }

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _enter, _loop);
}

/// Muncul bertahap: fade + geser + (opsional) zoom, mengikuti potongan
/// [start]..[end] dari timeline [t].
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.t,
    required this.start,
    required this.end,
    required this.child,
    this.dx = 0,
    this.dy = 14,
    this.scaleFrom = 1,
    this.curve = Curves.easeOutCubic,
  });

  final Animation<double> t;
  final double start;
  final double end;
  final double dx;
  final double dy;
  final double scaleFrom;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) {
        final v = _seg(t.value, start, end, curve);
        final o = v.clamp(0.0, 1.0).toDouble();
        Widget w = child!;
        if (scaleFrom != 1) {
          w = Transform.scale(scale: scaleFrom + (1 - scaleFrom) * v, child: w);
        }
        return Opacity(
          opacity: o,
          child: Transform.translate(offset: Offset(dx * (1 - v), dy * (1 - v)), child: w),
        );
      },
    );
  }
}

/// Efek tekan: mengecil sedikit + agak pudar selama jari menempel.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.onTap,
    required this.child,
    this.pressedScale = 0.95,
    this.alignment = Alignment.center,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double pressedScale;
  final Alignment alignment;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        alignment: widget.alignment,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Parallax saat geser antar slide: lapisan ini bergerak lebih lambat dari
/// kartunya ([depth] = fraksi lebar). Struktur widget sengaja tetap supaya
/// state anak tidak ke-reset waktu offset melewati 0.
class _ParallaxLayer extends StatelessWidget {
  const _ParallaxLayer({
    required this.offset,
    required this.depth,
    required this.child,
    this.fade = false,
  });

  final ValueListenable<double>? offset;
  final double depth;
  final bool fade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final o = offset;
    if (o == null) return child;
    return ValueListenableBuilder<double>(
      valueListenable: o,
      child: child,
      builder: (context, d, child) {
        final opacity = fade ? (1 - d.abs() * 0.6).clamp(0.0, 1.0).toDouble() : 1.0;
        return Opacity(
          opacity: opacity,
          child: FractionalTranslation(translation: Offset(d * depth, 0), child: child),
        );
      },
    );
  }
}

/// Teks dengan kilau yang lewat sesekali (satu sapuan per siklus loop).
class _ShimmerText extends StatelessWidget {
  const _ShimmerText(
    this.text, {
    required this.style,
    required this.base,
    required this.highlight,
    required this.loop,
    this.delay = 0.0,
  });

  final String text;
  final TextStyle style;
  final Color base;
  final Color highlight;
  final Animation<double> loop;
  final double delay;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        final p = (loop.value - delay) / 0.35;
        final s = (p < 0 || p > 1) ? -1.0 : -0.8 + 1.6 * Curves.easeInOut.transform(p);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
            transform: _SlidingGradientTransform(s),
          ).createShader(bounds),
          child: Text(text, style: style.copyWith(color: Colors.white)),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slide);

  final double slide;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * slide, 0, 0);
}

// ---------------------------------------------------------------------------
// Dekorasi: glow, kilau kartu, ring berputar, mahkota, partikel hati
// ---------------------------------------------------------------------------

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, this.alpha = 0.16});

  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Dua glow besar yang melayang pelan (loop mulus karena pakai sin/cos).
class _DriftingGlows extends StatelessWidget {
  const _DriftingGlows({required this.loop, required this.top, required this.bottom});

  final Animation<double> loop;
  final Color top;
  final Color bottom;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        final t = loop.value * 2 * math.pi;
        return Stack(
          children: [
            Positioned(
              right: -50 + math.sin(t) * 20,
              top: -60 + math.cos(t) * 14,
              child: _Glow(color: top, size: 170),
            ),
            Positioned(
              left: -60 + math.cos(t) * 22,
              bottom: -80 + math.sin(t) * 12,
              child: _Glow(color: bottom, size: 190),
            ),
          ],
        );
      },
    );
  }
}

/// Garis kilau diagonal yang menyapu kartu sekali per siklus.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.loop});

  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final p = loop.value / 0.3;
          if (p > 1) return const SizedBox.shrink();
          final e = Curves.easeInOut.transform(p);
          return Align(
            alignment: Alignment(-2.1 + 4.2 * e, 0),
            child: FractionallySizedBox(
              widthFactor: 0.35,
              heightFactor: 1,
              child: Transform(
                transform: Matrix4.skewX(-0.3),
                alignment: Alignment.center,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x00FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Ring emas dengan highlight putih yang berputar (buat juara 1).
class _SweepRingPainter extends CustomPainter {
  _SweepRingPainter({
    required this.loop,
    required this.color,
    required this.width,
    this.turns = 2,
  }) : super(repaint: loop);

  final Animation<double> loop;
  final Color color;
  final double width;
  final int turns;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.25),
          color,
          Colors.white,
          color,
          color.withValues(alpha: 0.25),
        ],
        stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
        transform: GradientRotation(loop.value * turns * 2 * math.pi),
      ).createShader(rect);
    canvas.drawCircle(rect.center, (size.width - width) / 2, paint);
  }

  @override
  bool shouldRepaint(_SweepRingPainter old) =>
      old.color != color || old.width != width || old.turns != turns;
}

class _Crown extends StatelessWidget {
  const _Crown({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height), painter: const _CrownPainter());
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFE9A6), heroGold, Color(0xFFFF9800)],
    ).createShader(Offset.zero & size);

    final path = Path()
      ..moveTo(w * 0.04, h)
      ..lineTo(w * 0.04, h * 0.38)
      ..lineTo(w * 0.27, h * 0.62)
      ..lineTo(w * 0.5, h * 0.06)
      ..lineTo(w * 0.73, h * 0.62)
      ..lineTo(w * 0.96, h * 0.38)
      ..lineTo(w * 0.96, h)
      ..close();

    final fill = Paint()..shader = shader;
    final edge = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, fill);
    canvas.drawPath(path, edge);

    final jewel = Paint()..color = const Color(0xFFFFF3C4);
    final r = w * 0.08;
    canvas.drawCircle(Offset(w * 0.04, h * 0.34), r, jewel);
    canvas.drawCircle(Offset(w * 0.5, h * 0.04), r, jewel);
    canvas.drawCircle(Offset(w * 0.96, h * 0.34), r, jewel);
  }

  @override
  bool shouldRepaint(_CrownPainter old) => false;
}

class _HeartSpec {
  const _HeartSpec(this.x, this.phase, this.size, this.sway, this.alpha, this.sparkle);

  final double x;
  final double phase;
  final double size;
  final double sway;
  final double alpha;
  final bool sparkle;
}

const List<_HeartSpec> _heartSpecs = [
  _HeartSpec(0.06, 0.00, 5, 7, 0.30, false),
  _HeartSpec(0.17, 0.38, 7, 9, 0.24, false),
  _HeartSpec(0.29, 0.71, 4, 6, 0.34, true),
  _HeartSpec(0.41, 0.15, 6, 8, 0.22, false),
  _HeartSpec(0.55, 0.55, 8, 10, 0.20, false),
  _HeartSpec(0.66, 0.90, 4, 6, 0.34, true),
  _HeartSpec(0.77, 0.30, 6, 8, 0.26, false),
  _HeartSpec(0.88, 0.62, 5, 7, 0.30, false),
  _HeartSpec(0.95, 0.08, 7, 9, 0.20, false),
];

/// Hati (dan kilau emas) kecil yang naik pelan sambil memudar.
class _HeartsPainter extends CustomPainter {
  _HeartsPainter(this.loop) : super(repaint: loop);

  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    final t = loop.value;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final h in _heartSpecs) {
      final u = (t + h.phase) % 1.0;
      final fade = math.sin(u * math.pi);
      final cx = size.width * h.x + math.sin((u * 1.5 + h.phase) * 2 * math.pi) * h.sway;
      final cy = size.height * (1.05 - 1.1 * u);
      paint.color = (h.sparkle ? heroGold : heroPink).withValues(alpha: h.alpha * fade);
      canvas.drawPath(
        h.sparkle ? _sparkle(cx, cy, h.size * 1.2) : _heart(cx, cy, h.size),
        paint,
      );
    }
  }

  Path _heart(double cx, double cy, double s) {
    return Path()
      ..moveTo(cx, cy + s * 0.9)
      ..cubicTo(cx - s * 1.6, cy - s * 0.1, cx - s * 0.7, cy - s * 1.2, cx, cy - s * 0.35)
      ..cubicTo(cx + s * 0.7, cy - s * 1.2, cx + s * 1.6, cy - s * 0.1, cx, cy + s * 0.9)
      ..close();
  }

  Path _sparkle(double cx, double cy, double r) {
    return Path()
      ..moveTo(cx, cy - r)
      ..quadraticBezierTo(cx, cy, cx + r, cy)
      ..quadraticBezierTo(cx, cy, cx, cy + r)
      ..quadraticBezierTo(cx, cy, cx - r, cy)
      ..quadraticBezierTo(cx, cy, cx, cy - r)
      ..close();
  }

  @override
  bool shouldRepaint(_HeartsPainter old) => false;
}

/// Denyut jantung "lub-dub": 0..1 untuk satu siklus [p] (0..1).
double _heartbeat(double p) {
  if (p < 0.16) return math.sin(p / 0.16 * math.pi);
  if (p >= 0.22 && p < 0.42) return 0.7 * math.sin((p - 0.22) / 0.20 * math.pi);
  return 0;
}

// ---------------------------------------------------------------------------
// Slide TOP LEADERBOARD
// ---------------------------------------------------------------------------

/// Slide "TOP LEADERBOARD" di carousel Beranda: dua panel kaca (TOP XP dan
/// TOP CLAN) di atas kartu navy dengan glow yang melayang pelan.
///
/// Animasi: header turun, panel naik bergantian, tiap baris masuk dari kiri
/// berurutan sambil angkanya menghitung naik; juara 1 punya ring emas
/// berputar + mahkota; kilau menyapu kartu sesekali; isi slide bergeser
/// parallax waktu di-swipe. [active] mengatur kapan animasi jalan (diisi oleh
/// HeroBanner), [pageOffset] = posisi slide relatif ke tengah (-1..1).
///
/// Panel TOP XP bisa di-tap ke leaderboard XP, panel TOP CLAN ke halaman Clan.
class HeroLeaderboardSlide extends StatelessWidget {
  const HeroLeaderboardSlide({
    super.key,
    required this.entries,
    required this.clans,
    required this.onTap,
    this.onClanTap,
    this.active = true,
    this.pageOffset,
  });

  final List<UserXpDisplay> entries;
  final List<ClanSummary> clans;
  final VoidCallback onTap;

  /// Tap panel TOP CLAN (buka halaman Clan). Null = panel tidak bisa di-tap.
  final VoidCallback? onClanTap;

  /// true = slide sedang kelihatan (animasi masuk + loop jalan).
  final bool active;

  /// Posisi slide relatif ke tengah pager (-1..1) untuk efek parallax.
  final ValueListenable<double>? pageOffset;

  @override
  Widget build(BuildContext context) {
    return _SlideMotion(
      active: active,
      builder: (context, enter, loop) {
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A2646), Color(0xFF0B1324)],
            ),
            border: Border.all(color: const Color(0x14FFFFFF)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: _ParallaxLayer(
                  offset: pageOffset,
                  depth: 0.45,
                  child: RepaintBoundary(
                    child: _DriftingGlows(loop: loop, top: heroGold, bottom: _clanPurple),
                  ),
                ),
              ),
              Positioned.fill(child: RepaintBoundary(child: _Sheen(loop: loop))),
              Positioned.fill(
                child: _ParallaxLayer(
                  offset: pageOffset,
                  depth: 0.18,
                  fade: true,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _Reveal(
                          t: enter,
                          start: 0,
                          end: 0.28,
                          dy: -10,
                          child: _LeaderboardHeader(loop: loop),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: _Reveal(
                                  t: enter,
                                  start: 0.08,
                                  end: 0.5,
                                  dy: 22,
                                  scaleFrom: 0.95,
                                  child: _Panel(
                                    icon: Icons.bolt_rounded,
                                    label: 'TOP XP',
                                    color: _xpBlue,
                                    onTap: onTap,
                                    loop: loop,
                                    rows: [
                                      for (var i = 0; i < entries.length && i < 4; i++)
                                        _BoardRow(
                                          rank: i + 1,
                                          avatar: UserAvatar(
                                            username: entries[i].username,
                                            url: entries[i].avatarUrl,
                                            size: 24,
                                          ),
                                          title: entries[i].username,
                                          valueAt: (p) =>
                                              '${_compactCount((entries[i].xp * p).round())} XP',
                                          enter: enter,
                                          loop: loop,
                                          start: 0.22 + i * 0.07,
                                          onTap: () => openPublicProfile(
                                              context, entries[i].firebaseUid),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _Reveal(
                                  t: enter,
                                  start: 0.18,
                                  end: 0.6,
                                  dy: 22,
                                  scaleFrom: 0.95,
                                  child: _Panel(
                                    icon: Icons.shield_rounded,
                                    label: 'TOP CLAN',
                                    color: _clanPurple,
                                    onTap: onClanTap,
                                    loop: loop,
                                    rows: [
                                      for (var i = 0; i < clans.length && i < 4; i++)
                                        _BoardRow(
                                          rank: i + 1,
                                          avatar: UserAvatar(
                                            username: clans[i].tag,
                                            url: clans[i].photoUrl,
                                            size: 24,
                                          ),
                                          title: clans[i].tag,
                                          valueAt: (p) => 'Lv${(clans[i].level * p).round()}',
                                          enter: enter,
                                          loop: loop,
                                          start: 0.32 + i * 0.07,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

class _LeaderboardHeader extends StatelessWidget {
  const _LeaderboardHeader({required this.loop});

  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          AnimatedBuilder(
            animation: loop,
            builder: (context, _) {
              final g = 0.5 + 0.5 * math.sin(loop.value * 2 * math.pi);
              return Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: heroGold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: [
                    BoxShadow(
                      color: heroGold.withValues(alpha: 0.08 + 0.16 * g),
                      blurRadius: 5 + 7 * g,
                    ),
                  ],
                ),
                child: const Icon(Icons.emoji_events_rounded, size: 14, color: heroGold),
              );
            },
          ),
          const SizedBox(width: 8),
          _ShimmerText(
            'TOP LEADERBOARD',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
            base: heroGold,
            highlight: const Color(0xFFFFF3C4),
            loop: loop,
          ),
        ],
      ),
    );
  }
}

/// Satu panel kolom: header (ikon + label + chevron yang bergeser pelan kalau
/// bisa di-tap) dan maksimal 4 baris yang disebar rata supaya selalu rapi.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.label,
    required this.color,
    required this.rows,
    required this.loop,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final List<Widget> rows;
  final Animation<double> loop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x17FFFFFF), Color(0x08FFFFFF)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 16,
              child: Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    AnimatedBuilder(
                      animation: loop,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(1.6 * math.sin(loop.value * 4 * math.pi), 0),
                        child: child,
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: color.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada data',
                        style: TextStyle(color: Color(0x66FFFFFF), fontSize: 11),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: rows,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris leaderboard (tinggi tetap 28): avatar ber-ring + badge rank di
/// pojok kiri bawah, nama di atas, nilai emas di bawah nama. Masuk dari kiri
/// pada [start], nilainya menghitung naik dari 0.
class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.rank,
    required this.avatar,
    required this.title,
    required this.valueAt,
    required this.enter,
    required this.loop,
    required this.start,
    this.onTap,
  });

  final int rank;
  final Widget avatar;
  final String title;

  /// Teks nilai untuk progres hitung-naik 0..1.
  final String Function(double progress) valueAt;
  final Animation<double> enter;
  final Animation<double> loop;
  final double start;

  /// Tap baris = buka profil publik user (null = ikut tap panel).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final end = math.min(1.0, start + 0.33);
    final countEnd = math.min(1.0, end + 0.12);

    final row = SizedBox(
      height: 28,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _AvatarRing(rank: rank, loop: loop, avatar: avatar),
              if (rank == 1)
                Positioned(
                  right: -5,
                  top: -7,
                  child: Transform.rotate(
                    angle: 0.35,
                    child: const _Crown(width: 11, height: 8),
                  ),
                ),
              Positioned(left: -4, bottom: -3, child: _RankBadge(rank: rank)),
            ],
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xEBFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                AnimatedBuilder(
                  animation: enter,
                  builder: (context, _) => Text(
                    valueAt(_seg(enter.value, start + 0.04, countEnd)),
                    maxLines: 1,
                    style: const TextStyle(
                      color: heroGold,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return _Reveal(
      t: enter,
      start: start,
      end: end,
      dx: -16,
      dy: 0,
      child: _Pressable(
        onTap: onTap,
        alignment: Alignment.centerLeft,
        child: row,
      ),
    );
  }
}

/// Ring avatar 28px: juara 1 = ring emas berputar, 2/3 = perak/perunggu,
/// sisanya tipis.
class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.rank, required this.loop, required this.avatar});

  final int rank;
  final Animation<double> loop;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    if (rank == 1) {
      return SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: const Size.square(28),
                painter: _SweepRingPainter(loop: loop, color: heroGold, width: 1.8),
              ),
            ),
            ClipOval(child: avatar),
          ],
        ),
      );
    }
    final ring = rank <= 3 ? _rankColor(rank) : const Color(0x26FFFFFF);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.5),
      ),
      child: ClipOval(child: avatar),
    );
  }
}

/// Badge angka rank kecil (14) dengan tepi gelap supaya "terpotong" rapi dari
/// ring avatar.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: rank <= 3 ? _rankColor(rank) : const Color(0xFF2B3550),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF111B31), width: 1.5),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: rank <= 3 ? _ink : const Color(0xB3FFFFFF),
          fontSize: 8,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide TOP SUPPORT
// ---------------------------------------------------------------------------

/// Slide "TOP SUPPORT" (podium 3 donatur teratas).
///
/// Animasi: balok podium tumbuh bergantian (juara 1 duluan) sambil avatar
/// ikut terangkat dan nominalnya menghitung naik; juara 1 dapat halo emas
/// berdenyut, ring berputar, dan mahkota yang melayang; kilau lewat di tiap
/// balok; hati & kilau kecil naik di latar; ikon hati berdenyut "lub-dub".
class HeroSupportSlide extends StatelessWidget {
  const HeroSupportSlide({
    super.key,
    required this.supporters,
    this.onTap,
    this.active = true,
    this.pageOffset,
  });

  final List<TopSupporter> supporters;

  /// Tap slide = buka halaman Top Support. Null = tidak bisa di-tap.
  final VoidCallback? onTap;

  /// true = slide sedang kelihatan (animasi masuk + loop jalan).
  final bool active;

  /// Posisi slide relatif ke tengah pager (-1..1) untuk efek parallax.
  final ValueListenable<double>? pageOffset;

  @override
  Widget build(BuildContext context) {
    final top = supporters.take(3).toList();
    return _SlideMotion(
      active: active,
      enterDuration: const Duration(milliseconds: 1700),
      loopDuration: const Duration(seconds: 8),
      builder: (context, enter, loop) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3A1A2C), Color(0xFF1E1B2E)],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _ParallaxLayer(
                    offset: pageOffset,
                    depth: 0.45,
                    child: RepaintBoundary(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: loop,
                              builder: (context, _) {
                                final t = loop.value * 2 * math.pi;
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: -40 + math.sin(t) * 24,
                                      top: -70 + math.cos(t) * 10,
                                      child: const _Glow(color: heroPink, size: 230, alpha: 0.22),
                                    ),
                                    Positioned(
                                      right: -60 + math.cos(t) * 18,
                                      bottom: -90,
                                      child: const _Glow(color: heroGold, size: 210, alpha: 0.10),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(painter: _HeartsPainter(loop)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _ParallaxLayer(
                    offset: pageOffset,
                    depth: 0.18,
                    fade: true,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Reveal(
                            t: enter,
                            start: 0,
                            end: 0.25,
                            dy: -8,
                            child: Row(
                              children: [
                                AnimatedBuilder(
                                  animation: loop,
                                  builder: (context, child) {
                                    final p = ((loop.value * 8) % 1.6) / 1.6;
                                    return Transform.scale(
                                      scale: 1 + 0.22 * _heartbeat(p),
                                      child: child,
                                    );
                                  },
                                  child: const Icon(Icons.favorite, size: 18, color: heroPink),
                                ),
                                const SizedBox(width: 7),
                                _ShimmerText(
                                  'TOP SUPPORT',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                  base: heroPink,
                                  highlight: const Color(0xFFFFD6E0),
                                  loop: loop,
                                ),
                                const Spacer(),
                                if (onTap != null) _SeeAll(loop: loop),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          _Reveal(
                            t: enter,
                            start: 0.05,
                            end: 0.3,
                            dy: -6,
                            child: const Text(
                              'Donatur teratas',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (top.length > 1)
                                  Expanded(
                                    child: _Podium(
                                      rank: 2,
                                      s: top[1],
                                      bar: 38,
                                      order: 1,
                                      enter: enter,
                                      loop: loop,
                                    ),
                                  ),
                                if (top.isNotEmpty)
                                  Expanded(
                                    child: _Podium(
                                      rank: 1,
                                      s: top[0],
                                      bar: 56,
                                      order: 0,
                                      enter: enter,
                                      loop: loop,
                                    ),
                                  ),
                                if (top.length > 2)
                                  Expanded(
                                    child: _Podium(
                                      rank: 3,
                                      s: top[2],
                                      bar: 24,
                                      order: 2,
                                      enter: enter,
                                      loop: loop,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.loop});

  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Lihat semua',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        AnimatedBuilder(
          animation: loop,
          builder: (context, child) => Transform.translate(
            offset: Offset(1.8 * math.sin(loop.value * 4 * math.pi), 0),
            child: child,
          ),
          child: const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({
    required this.rank,
    required this.s,
    required this.bar,
    required this.order,
    required this.enter,
    required this.loop,
  });

  final int rank;
  final TopSupporter s;
  final double bar;

  /// Urutan muncul: 0 = pertama (juara 1), 1, 2.
  final int order;
  final Animation<double> enter;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    final color = _rankColor(rank);
    final avatarSize = rank == 1 ? 40.0 : 32.0;
    final start = 0.10 + order * 0.12;
    final countEnd = math.min(1.0, start + 0.7);
    final uid = s.firebaseUid;

    return _Pressable(
      onTap: (uid == null || uid.isEmpty) ? null : () => openPublicProfile(context, uid),
      pressedScale: 0.94,
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Reveal(
              t: enter,
              start: start + 0.08,
              end: start + 0.42,
              dy: 0,
              scaleFrom: 0.3,
              curve: Curves.easeOutBack,
              child: _PodiumAvatar(
                rank: rank,
                size: avatarSize,
                name: s.name,
                url: s.avatarUrl,
                enter: enter,
                loop: loop,
                crownStart: start + 0.4,
              ),
            ),
            const SizedBox(height: 4),
            _Reveal(
              t: enter,
              start: start + 0.2,
              end: start + 0.5,
              dy: 6,
              child: Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            AnimatedBuilder(
              animation: enter,
              builder: (context, _) {
                final p = _seg(enter.value, start + 0.2, countEnd);
                return Text(
                  _compactRupiah((s.totalAmount * p).round()),
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                );
              },
            ),
            const SizedBox(height: 4),
            // Balok podium tumbuh dari bawah, juara 1 duluan.
            AnimatedBuilder(
              animation: enter,
              builder: (context, _) {
                final h = bar * _seg(enter.value, start, start + 0.42);
                return _PodiumBar(rank: rank, height: h, order: order, loop: loop);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PodiumAvatar extends StatelessWidget {
  const _PodiumAvatar({
    required this.rank,
    required this.size,
    required this.name,
    required this.url,
    required this.enter,
    required this.loop,
    required this.crownStart,
  });

  final int rank;
  final double size;
  final String name;
  final String? url;
  final Animation<double> enter;
  final Animation<double> loop;
  final double crownStart;

  @override
  Widget build(BuildContext context) {
    final color = _rankColor(rank);
    final avatar = UserAvatar(username: name, url: url, size: size);

    if (rank != 1) {
      return Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: avatar,
      );
    }

    final box = size + 8;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Halo emas berdenyut.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: loop,
              builder: (context, _) {
                final pulse = 0.5 + 0.5 * math.sin(loop.value * 4 * math.pi);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.16 + 0.16 * pulse),
                        blurRadius: 12 + 8 * pulse,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: SizedBox.square(dimension: box - 4),
                );
              },
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              size: Size.square(box),
              painter: _SweepRingPainter(loop: loop, color: color, width: 2.2),
            ),
          ),
          avatar,
          // Mahkota jatuh masuk lalu melayang naik-turun pelan.
          Positioned(
            top: -12,
            left: 0,
            right: 0,
            child: Center(
              child: _Reveal(
                t: enter,
                start: crownStart,
                end: math.min(1.0, crownStart + 0.3),
                dy: -14,
                scaleFrom: 0.5,
                curve: Curves.easeOutBack,
                child: AnimatedBuilder(
                  animation: loop,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, -1.6 * math.sin(loop.value * 4 * math.pi)),
                    child: child,
                  ),
                  child: Transform.rotate(
                    angle: -0.12,
                    child: const _Crown(width: 18, height: 13),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PodiumBar extends StatelessWidget {
  const _PodiumBar({
    required this.rank,
    required this.height,
    required this.order,
    required this.loop,
  });

  final int rank;
  final double height;
  final int order;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    final color = _rankColor(rank);
    return Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0.55)],
        ),
        boxShadow: (rank == 1 && height > 6)
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, -2),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _BarShimmer(loop: loop, delay: order * 0.06)),
          if (height > 14)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kilau putih yang lewat di balok podium (satu sapuan per siklus).
class _BarShimmer extends StatelessWidget {
  const _BarShimmer({required this.loop, required this.delay});

  final Animation<double> loop;
  final double delay;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final p = (loop.value - delay) / 0.2;
          if (p < 0 || p > 1) return const SizedBox.shrink();
          final e = Curves.easeInOut.transform(p);
          return Align(
            alignment: Alignment(-3 + 6 * e, 0),
            child: const FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x00FFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
