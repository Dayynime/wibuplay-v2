import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/clan_models.dart';
import '../../data/models/support_models.dart';
import '../../data/models/xp_models.dart';
import 'game_badges.dart';
import '../screens/profile/public_profile_screen.dart';

// =============================================================================
// Slide leaderboard di carousel Beranda (Top XP / Top Clan, Top Support,
// Top Giver).
//
// Gaya: panel "liquid glass" di atas pemandangan berwarna (warna ikut slide),
// isinya disajikan seperti dashboard data, bukan dekorasi:
//  - Top XP / Clan : angka bergulir per digit (odometer) + bar perbandingan
//                    terhadap peringkat 1, toggle XP | Clan berbentuk lensa cair.
//  - Top Support   : satu bar bertumpuk (porsi tiap donatur) + total.
//  - Top Giver     : grid kotak, 1 kotak = N hari Premium yang dibagikan,
//                    terisi seperti gelombang diagonal.
// Semua animasi masuk diputar ulang tiap slide kelihatan, dan mati kalau HP
// diset "hapus animasi".
// =============================================================================

const Color heroGold = Color(0xFFFFC107);
const Color heroPink = Color(0xFFFF5C8A);
const Color heroTeal = Color(0xFF2DD4BF);

const Color _silver = Color(0xFFC7CDD8);
const Color _bronze = Color(0xFFCE8946);
const Color _ink = Color(0xFF15213B);
const Color _xpBlue = Color(0xFF6CB8FF);
const Color _clanOrange = Color(0xFFFF8A65);
const Color _rose = Color(0xFFFF6F91);
const Color _mint = Color(0xFF34D3B5);
const Color _mintText = Color(0xFF5EEAD4);
const Color _muted = Color(0xFF9AA0AC);

const List<Color> _roseTones = [Color(0xFFFF6F91), Color(0xFFC2577A), Color(0xFF8A4565)];

/// Kurva keluar cepat lalu mendarat halus (dipakai hampir semua gerak).
const Curve _outExpo = Cubic(0.16, 1, 0.3, 1);

/// Kurva pegas: melewati target sedikit lalu kembali (lensa cair).
const Curve _spring = Cubic(0.34, 1.56, 0.64, 1);

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

/// 12500 -> "12.500".
String _groupInt(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

Color _rankColor(int rank) => switch (rank) {
      1 => heroGold,
      2 => _silver,
      3 => _bronze,
      _ => const Color(0xFF2B3550),
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
///  - `loop` : animasi ambient berulang (kilau kaca yang bergeser pelan).
/// Keduanya cuma jalan selama slide kelihatan ([active]) supaya hemat baterai,
/// dan mati kalau HP diset "hapus animasi".
class _SlideMotion extends StatefulWidget {
  const _SlideMotion({
    super.key,
    required this.active,
    required this.builder,
    this.enterDuration = const Duration(milliseconds: 1500),
    this.loopDuration = const Duration(seconds: 9),
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

/// Muncul bertahap: fade + geser, mengikuti potongan [start]..[end] dari
/// timeline [t].
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.t,
    required this.start,
    required this.end,
    required this.child,
    this.dx = 0,
    this.dy = 10,
  });

  final Animation<double> t;
  final double start;
  final double end;
  final double dx;
  final double dy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) {
        final v = _seg(t.value, start, math.min(1.0, end), _outExpo);
        return Opacity(
          opacity: v.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(offset: Offset(dx * (1 - v), dy * (1 - v)), child: child),
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
    this.pressedScale = 0.96,
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

// ---------------------------------------------------------------------------
// Panggung kaca: pemandangan berwarna + panel liquid glass di atasnya
// ---------------------------------------------------------------------------

class _ScenePalette {
  const _ScenePalette(this.sky, this.moon, this.far, this.near, this.moonX);

  final Color sky;
  final Color moon;
  final Color far;
  final Color near;

  /// Posisi bulan (0 = kiri, 1 = kanan).
  final double moonX;
}

const _ScenePalette _sceneXp =
    _ScenePalette(Color(0xFF122047), Color(0xFF6CB8FF), Color(0xFF1E3A78), Color(0xFF0B1430), 0.78);
const _ScenePalette _sceneSupport =
    _ScenePalette(Color(0xFF3A1426), Color(0xFFFF6F91), Color(0xFF6B2340), Color(0xFF1E0B14), 0.22);
const _ScenePalette _sceneGiver =
    _ScenePalette(Color(0xFF0D3A3D), Color(0xFF5EEAD4), Color(0xFF145457), Color(0xFF082224), 0.55);

/// Pemandangan sederhana (langit, bulan, dua lapis bukit) yang dibiaskan kaca.
class _ScenePainter extends CustomPainter {
  const _ScenePainter(this.p);

  final _ScenePalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = p.sky);
    canvas.drawCircle(Offset(w * p.moonX, h * 0.3), h * 0.26, Paint()..color = p.moon);
    final far = Path()
      ..moveTo(0, h * 0.70)
      ..lineTo(w * 0.20, h * 0.46)
      ..lineTo(w * 0.38, h * 0.62)
      ..lineTo(w * 0.62, h * 0.38)
      ..lineTo(w, h * 0.66)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = p.far);
    final near = Path()
      ..moveTo(0, h * 0.83)
      ..lineTo(w * 0.28, h * 0.62)
      ..lineTo(w * 0.49, h * 0.78)
      ..lineTo(w * 0.74, h * 0.64)
      ..lineTo(w, h * 0.79)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, Paint()..color = p.near);
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.p != p;
}

class _GlassStage extends StatelessWidget {
  const _GlassStage({
    required this.palette,
    required this.accent,
    required this.loop,
    required this.child,
    this.pageOffset,
    this.onTap,
  });

  final _ScenePalette palette;
  final Color accent;
  final Animation<double> loop;
  final Widget child;
  final ValueListenable<double>? pageOffset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Pemandangan sedikit lebih lebar dari kartu supaya parallax tidak
          // memperlihatkan tepi kosong.
          Positioned(
            left: -60,
            right: -60,
            top: 0,
            bottom: 0,
            child: _ParallaxLayer(
              offset: pageOffset,
              depth: 0.22,
              child: RepaintBoundary(child: CustomPaint(painter: _ScenePainter(palette))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: _ParallaxLayer(
              offset: pageOffset,
              depth: 0.06,
              fade: true,
              child: _GlassPanel(
                accent: accent,
                loop: loop,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel kaca: blur + isi gelap bening, tepi memantulkan cahaya, dan kilau
/// specular yang mengikuti jari (diam = bergeser pelan sendiri).
class _GlassPanel extends StatefulWidget {
  const _GlassPanel({required this.child, required this.accent, required this.loop});

  final Widget child;
  final Color accent;
  final Animation<double> loop;

  @override
  State<_GlassPanel> createState() => _GlassPanelState();
}

class _GlassPanelState extends State<_GlassPanel> {
  final ValueNotifier<Offset?> _touch = ValueNotifier<Offset?>(null);

  @override
  void dispose() {
    _touch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(16));
    return Listener(
      onPointerDown: (e) => _touch.value = e.localPosition,
      onPointerMove: (e) => _touch.value = e.localPosition,
      onPointerUp: (_) => _touch.value = null,
      onPointerCancel: (_) => _touch.value = null,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x8C161C29), Color(0xA60D111A)],
              ),
            ),
            child: CustomPaint(
              foregroundPainter: _GlassSheenPainter(
                loop: widget.loop,
                touch: _touch,
                accent: widget.accent,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassSheenPainter extends CustomPainter {
  _GlassSheenPainter({required this.loop, required this.touch, required this.accent})
      : super(repaint: Listenable.merge([loop, touch]));

  final Animation<double> loop;
  final ValueListenable<Offset?> touch;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    // Kilau specular: ikut jari, kalau tidak disentuh bergeser pelan.
    final a = loop.value * 2 * math.pi;
    final center = touch.value ??
        Offset(size.width * (0.32 + 0.22 * math.sin(a)), size.height * (0.12 + 0.06 * math.cos(a)));
    final sheen = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(Rect.fromCircle(center: center, radius: 160));
    canvas.drawRRect(rrect, sheen);

    // Tepi kaca: terang di kiri atas, redup di tengah, sedikit aksen di kanan bawah.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.38),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.03),
          accent.withValues(alpha: 0.30),
        ],
        stops: const [0, 0.35, 0.7, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.5), edge);

    // Garis kilap tipis di tepi atas (kaca tebal memantulkan cahaya).
    final shine = Paint()
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.45),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(14, 0, size.width - 28, 1));
    canvas.drawLine(const Offset(14, 1), Offset(size.width - 14, 1), shine);
  }

  @override
  bool shouldRepaint(_GlassSheenPainter old) => old.accent != accent;
}

// ---------------------------------------------------------------------------
// Komponen kecil
// ---------------------------------------------------------------------------

/// Angka yang bergulir per digit seperti odometer. Karakter selain angka
/// (titik, huruf, "Rp") tampil diam.
class _Odometer extends StatelessWidget {
  const _Odometer({
    required this.text,
    required this.style,
    required this.t,
    required this.start,
    this.span = 0.5,
    this.stagger = 0.035,
  });

  final String text;
  final TextStyle style;
  final Animation<double> t;
  final double start;
  final double span;
  final double stagger;

  @override
  Widget build(BuildContext context) {
    final s = style.copyWith(
      height: 1.2,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final h = (s.fontSize ?? 14) * 1.2;
    final children = <Widget>[];
    var k = 0;
    for (final ch in text.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        final digit = code - 48;
        final a = math.min(0.95, start + k * stagger);
        k++;
        children.add(
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 0.1,
              child: AnimatedBuilder(
                animation: t,
                builder: (context, child) {
                  final p = _seg(t.value, a, math.min(1.0, a + span), _outExpo);
                  return Transform.translate(offset: Offset(0, -h * digit * p), child: child);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var d = 0; d < 10; d++) SizedBox(height: h, child: Text('$d', style: s)),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        children.add(SizedBox(height: h, child: Text(ch, style: s)));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Bar tipis yang tergambar dari kiri sampai [ratio] (0..1).
class _Bar extends StatelessWidget {
  const _Bar({required this.ratio, required this.color, required this.t, required this.start});

  final double ratio;
  final Color color;
  final Animation<double> t;
  final double start;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: ColoredBox(
          color: const Color(0x1AFFFFFF),
          child: AnimatedBuilder(
            animation: t,
            builder: (context, _) {
              final p = _seg(t.value, start, math.min(1.0, start + 0.5), _outExpo);
              return Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: (ratio * p).clamp(0.0, 1.0).toDouble(),
                  heightFactor: 1,
                  child: ColoredBox(color: color),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

Widget _rankBadge(int rank, {double size = 14}) {
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _rankColor(rank),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFF10141D), width: 1.5),
    ),
    child: Text(
      '$rank',
      style: TextStyle(
        color: rank <= 3 ? _ink : const Color(0xBFFFFFFF),
        fontSize: size * 0.58,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );
}

/// Foto profil + badge peringkat di pojok kiri bawah (seperti versi lama).
Widget _avatarWithRank({required Widget avatar, required double size, required int rank}) {
  return SizedBox(
    width: size,
    height: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(left: -4, bottom: -3, child: _rankBadge(rank)),
      ],
    ),
  );
}

Widget _titleBlock(String title, String subtitle) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textWhite,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 1),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _muted, fontSize: 11, height: 1.2),
      ),
    ],
  );
}

const Widget _empty = Center(
  child: Text('Belum ada data', style: TextStyle(color: Color(0x66FFFFFF), fontSize: 11)),
);

/// Toggle dua pilihan dengan lensa kaca yang meluncur, melar lalu memantul
/// seperti tetesan cairan saat pindah.
class _LiquidSegment extends StatefulWidget {
  const _LiquidSegment({required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<_LiquidSegment> createState() => _LiquidSegmentState();
}

class _LiquidSegmentState extends State<_LiquidSegment> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 1,
  );
  late int _from = widget.index;

  static const double _segW = 50;
  static const double _h = 34;
  static const double _pad = 3;

  @override
  void didUpdateWidget(_LiquidSegment old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = old.index;
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

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    return Container(
      width: _segW * n + _pad * 2,
      height: _h,
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: const Color(0x47000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final x = ui.lerpDouble(_from * _segW, widget.index * _segW, _spring.transform(t))!;
              final w = math.sin(math.pi * t);
              return Positioned(
                left: x,
                top: 0,
                bottom: 0,
                width: _segW,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(1 + 0.24 * w, 1 - 0.16 * w, 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0x38FFFFFF)),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x42FFFFFF), Color(0x1AFFFFFF)],
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i == widget.index) return;
                    HapticFeedback.selectionClick();
                    widget.onChanged(i);
                  },
                  child: SizedBox(
                    width: _segW,
                    height: _h - _pad * 2,
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          color: i == widget.index ? Colors.white : _muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                        child: Text(widget.labels[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide Top XP / Top Clan
// ---------------------------------------------------------------------------

class HeroLeaderboardSlide extends StatefulWidget {
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

  /// Tap panel saat mode Clan (buka halaman Clan). Null = tidak bisa di-tap.
  final VoidCallback? onClanTap;

  /// true = slide sedang kelihatan (animasi masuk + loop jalan).
  final bool active;

  /// Posisi slide relatif ke tengah pager (-1..1) untuk efek parallax.
  final ValueListenable<double>? pageOffset;

  @override
  State<HeroLeaderboardSlide> createState() => _HeroLeaderboardSlideState();
}

class _HeroLeaderboardSlideState extends State<HeroLeaderboardSlide> {
  bool _clanMode = false;

  @override
  Widget build(BuildContext context) {
    final hasXp = widget.entries.isNotEmpty;
    final hasClan = widget.clans.isNotEmpty;
    final clan = hasXp ? (_clanMode && hasClan) : hasClan;
    final accent = clan ? _clanOrange : _xpBlue;

    return _SlideMotion(
      active: widget.active,
      enterDuration: const Duration(milliseconds: 1600),
      builder: (context, enter, loop) {
        return _GlassStage(
          palette: _sceneXp,
          accent: accent,
          loop: loop,
          pageOffset: widget.pageOffset,
          onTap: clan ? widget.onClanTap : widget.onTap,
          child: Column(
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Expanded(
                      child: _Reveal(
                        t: enter,
                        start: 0,
                        end: 0.3,
                        dy: -6,
                        child: _titleBlock(
                          clan ? 'Top Clan' : 'Top XP',
                          clan ? 'Level clan' : 'Bulan ini',
                        ),
                      ),
                    ),
                    if (hasXp && hasClan)
                      _LiquidSegment(
                        labels: const ['XP', 'Clan'],
                        index: clan ? 1 : 0,
                        onChanged: (i) => setState(() => _clanMode = i == 1),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Daftar punya controller sendiri (di-key per mode) supaya ganti
              // XP <-> Clan memutar ulang odometer & bar dari awal.
              Expanded(
                child: _SlideMotion(
                  key: ValueKey<bool>(clan),
                  active: widget.active,
                  enterDuration: const Duration(milliseconds: 1500),
                  builder: (context, rowsIn, _) =>
                      clan ? _clanRows(rowsIn, accent) : _xpRows(context, rowsIn, accent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _xpRows(BuildContext context, Animation<double> t, Color accent) {
    final list = widget.entries.take(4).toList();
    if (list.isEmpty) return _empty;
    final max = list.map((e) => e.xp).fold<int>(1, math.max);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < list.length; i++)
          _row(
            i: i,
            t: t,
            accent: accent,
            avatar: UserAvatar(
              username: list[i].username,
              url: list[i].avatarUrl,
              size: 26,
              frameUid: list[i].firebaseUid,
            ),
            name: list[i].username,
            ratio: list[i].xp / max,
            value: '${_compactCount(list[i].xp)} XP',
            onTap: () => openPublicProfile(context, list[i].firebaseUid),
          ),
      ],
    );
  }

  Widget _clanRows(Animation<double> t, Color accent) {
    final list = widget.clans.take(4).toList();
    if (list.isEmpty) return _empty;
    final max = list.map((e) => e.level).fold<int>(1, math.max);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < list.length; i++)
          _row(
            i: i,
            t: t,
            accent: accent,
            avatar: UserAvatar(username: list[i].tag, url: list[i].photoUrl, size: 26),
            name: list[i].tag,
            ratio: list[i].level / max,
            value: 'Lv ${list[i].level}',
          ),
      ],
    );
  }

  Widget _row({
    required int i,
    required Animation<double> t,
    required Color accent,
    required Widget avatar,
    required String name,
    required double ratio,
    required String value,
    VoidCallback? onTap,
  }) {
    final start = 0.06 + i * 0.08;
    return _Reveal(
      t: t,
      start: start,
      end: start + 0.32,
      dx: -12,
      dy: 0,
      child: _Pressable(
        onTap: onTap,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 31,
          child: Row(
            children: [
              _avatarWithRank(avatar: avatar, size: 26, rank: i + 1),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _Bar(
                      ratio: ratio,
                      color: accent.withValues(alpha: i == 0 ? 1 : 0.55),
                      t: t,
                      start: start + 0.06,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _Odometer(
                text: value,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                t: t,
                start: start + 0.04,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide Top Support
// ---------------------------------------------------------------------------

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
    final total = top.fold<int>(0, (a, s) => a + s.totalAmount);
    return _SlideMotion(
      active: active,
      enterDuration: const Duration(milliseconds: 1800),
      builder: (context, enter, loop) {
        return _GlassStage(
          palette: _sceneSupport,
          accent: _rose,
          loop: loop,
          pageOffset: pageOffset,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Reveal(
                        t: enter,
                        start: 0,
                        end: 0.3,
                        dy: -6,
                        child: _titleBlock('Top Support', 'Donatur teratas'),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _Odometer(
                          text: _compactRupiah(total),
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                          t: enter,
                          start: 0.04,
                          span: 0.55,
                        ),
                        Text(
                          'total ${top.length} teratas',
                          style: const TextStyle(color: _muted, fontSize: 10.5, height: 1.1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (top.isEmpty)
                const Expanded(child: _empty)
              else ...[
                _StackedBar(values: [for (final s in top) s.totalAmount], t: enter),
                const SizedBox(height: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < top.length; i++)
                        _supportRow(context, i, top[i], total, enter),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _supportRow(BuildContext context, int i, TopSupporter s, int total, Animation<double> t) {
    final uid = s.firebaseUid;
    final share = total > 0 ? s.totalAmount / total : 0.0;
    final start = 0.22 + i * 0.14;
    return _Reveal(
      t: t,
      start: start,
      end: start + 0.3,
      dx: -10,
      dy: 0,
      child: _Pressable(
        onTap: (uid == null || uid.isEmpty) ? null : () => openPublicProfile(context, uid),
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _roseTones[i % _roseTones.length],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 9),
              _avatarWithRank(
                avatar: UserAvatar(username: s.name, url: s.avatarUrl, size: 22, frameUid: uid),
                size: 22,
                rank: s.rank,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(share * 100).round()}%',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11.5,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 60),
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1,
                  child: _Odometer(
                    text: _compactRupiah(s.totalAmount),
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                    t: t,
                    start: start + 0.04,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Satu bar bertumpuk: tiap segmen = porsi donatur dari total, terisi berurutan.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.values, required this.t});

  final List<int> values;
  final Animation<double> t;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<int>(0, (a, v) => a + v);
    const gap = 3.0;
    return SizedBox(
      height: 10,
      child: LayoutBuilder(
        builder: (context, c) {
          final avail = math.max(0.0, c.maxWidth - gap * (values.length - 1));
          return AnimatedBuilder(
            animation: t,
            builder: (context, _) {
              return Row(
                children: [
                  for (var i = 0; i < values.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Container(
                      width: total > 0
                          ? avail *
                              (values[i] / total) *
                              _seg(t.value, 0.08 + i * 0.16, 0.48 + i * 0.16, _outExpo)
                          : 0.0,
                      decoration: BoxDecoration(
                        color: _roseTones[i % _roseTones.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide Top Giver
// ---------------------------------------------------------------------------

/// Slide "Top Giver" (total hari Premium yang dibagikan, sepanjang masa).
class HeroGiverSlide extends StatelessWidget {
  const HeroGiverSlide({
    super.key,
    required this.givers,
    this.clanTags = const {},
    this.onTap,
    this.active = true,
    this.pageOffset,
  });

  final List<TopGiver> givers;
  final Map<String, String> clanTags;
  final VoidCallback? onTap;
  final bool active;
  final ValueListenable<double>? pageOffset;

  @override
  Widget build(BuildContext context) {
    final g = givers;
    final lead = g.isNotEmpty ? g.first : null;
    final rest = g.skip(1).take(4).toList();
    return _SlideMotion(
      active: active,
      enterDuration: const Duration(milliseconds: 1800),
      builder: (context, enter, loop) {
        return _GlassStage(
          palette: _sceneGiver,
          accent: _mint,
          loop: loop,
          pageOffset: pageOffset,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Expanded(
                      child: _Reveal(
                        t: enter,
                        start: 0,
                        end: 0.3,
                        dy: -6,
                        child: _titleBlock('Top Giver', 'Hari Premium yang dibagikan'),
                      ),
                    ),
                    if (onTap != null)
                      const Icon(Icons.chevron_right_rounded, size: 20, color: _muted),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: lead == null
                    ? _empty
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 122, child: _lead(context, lead, enter)),
                          if (rest.isNotEmpty) ...[
                            Container(
                              width: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              color: const Color(0x1FFFFFFF),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  for (var i = 0; i < rest.length; i++)
                                    _giverRow(context, i, rest[i], enter),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _lead(BuildContext context, TopGiver x, Animation<double> t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Reveal(
          t: t,
          start: 0.04,
          end: 0.34,
          dy: 8,
          child: _Pressable(
            onTap: x.firebaseUid.isEmpty ? null : () => openPublicProfile(context, x.firebaseUid),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                _avatarWithRank(
                  avatar: UserAvatar(
                    username: x.username,
                    url: x.avatarUrl,
                    size: 30,
                    frameUid: x.firebaseUid,
                  ),
                  size: 30,
                  rank: x.rank,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        x.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      _Odometer(
                        text: '${_groupInt(x.days)} hari',
                        style: const TextStyle(
                          color: _mintText,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                        t: t,
                        start: 0.1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _DayGrid(days: x.days, t: t)),
      ],
    );
  }

  Widget _giverRow(BuildContext context, int i, TopGiver x, Animation<double> t) {
    final clan = clanTags[x.firebaseUid];
    final start = 0.3 + i * 0.08;
    return _Reveal(
      t: t,
      start: start,
      end: start + 0.3,
      dx: 0,
      dy: 6,
      child: _Pressable(
        onTap: x.firebaseUid.isEmpty ? null : () => openPublicProfile(context, x.firebaseUid),
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              SizedBox(
                width: 12,
                child: Text(
                  '${x.rank}',
                  style: const TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              UserAvatar(username: x.username, url: x.avatarUrl, size: 20),
              const SizedBox(width: 7),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        x.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if ((clan ?? '').isNotEmpty) ...[
                      const SizedBox(width: 5),
                      ClanRainbowBadge(text: clan!, height: 14),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_groupInt(x.days)} hari',
                style: const TextStyle(
                  color: Color(0xFFC7CBD3),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid 9 x 5 kotak. 1 kotak = [unit] hari Premium (unit naik kalau hari
/// yang dibagikan lebih dari 45). Kotak terisi seperti gelombang diagonal.
class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.days, required this.t});

  final int days;
  final Animation<double> t;

  static const int _cols = 9;
  static const int _rows = 5;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    const cells = _cols * _rows;
    final unit = math.max(1, (days / cells).ceil());
    final filled = math.min(cells, (days / unit).ceil());
    return LayoutBuilder(
      builder: (context, c) {
        final cell = (c.maxWidth - _gap * (_cols - 1)) / _cols;
        final gridH = cell * _rows + _gap * (_rows - 1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: c.maxWidth,
              height: gridH,
              child: CustomPaint(painter: _DayGridPainter(t: t, filled: filled, cell: cell)),
            ),
            const SizedBox(height: 4),
            Text(
              '1 kotak = $unit hari',
              maxLines: 1,
              style: const TextStyle(color: _muted, fontSize: 10, height: 1.1),
            ),
          ],
        );
      },
    );
  }
}

class _DayGridPainter extends CustomPainter {
  _DayGridPainter({required this.t, required this.filled, required this.cell}) : super(repaint: t);

  final Animation<double> t;
  final int filled;
  final double cell;

  static const Color _off = Color(0x17FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < _DayGrid._cols * _DayGrid._rows; i++) {
      final r = i ~/ _DayGrid._cols;
      final c = i % _DayGrid._cols;
      final on = i < filled;
      final start = 0.18 + (r + c) * 0.035;
      final p = on ? _seg(t.value, start, math.min(1.0, start + 0.22), _outExpo) : 0.0;
      final scale = on ? 0.55 + 0.45 * p : 1.0;
      final s = cell * scale;
      final cx = c * (cell + _DayGrid._gap) + cell / 2;
      final cy = r * (cell + _DayGrid._gap) + cell / 2;
      paint.color = Color.lerp(_off, _mint, p)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: s, height: s),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DayGridPainter old) => old.filled != filled || old.cell != cell;
}
