import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/xp_models.dart';

/// Badge level beranimasi dengan sistem tier: warna & efek makin "mewah"
/// seiring naik level.
///
/// ```dart
/// LevelStyledBadge(level: 42, style: LevelBadgeStyle.hexCore, height: 20)
/// LevelStyledBadge.fromXp(level: xp.level, totalXp: xp.totalXp, style: LevelBadgeStyle.energyPill)
/// ```
///
/// Semua digambar CustomPainter, satu AnimationController per badge,
/// RepaintBoundary, dan berhenti kalau "reduce motion" aktif.

// ===================================================================== tier

class LevelTier {
  const LevelTier._(this.index, this.name, this.minLevel, this.c1, this.c2, this.c3, this.glow);

  final int index;
  final String name;
  final int minLevel;

  /// c1 terang, c2 utama, c3 gelap, glow untuk cahaya.
  final Color c1, c2, c3, glow;

  bool get isLegend => index == 6;

  /// 0..1, dipakai untuk mengatur kuatnya efek.
  double get fx => index / 6;

  static const List<LevelTier> all = [
    LevelTier._(0, 'Perunggu', 1, Color(0xFFF3C49B), Color(0xFFC47A43), Color(0xFF6E3B1C), Color(0xFFE08A4A)),
    LevelTier._(1, 'Perak', 10, Color(0xFFF4F7FB), Color(0xFFAAB4C3), Color(0xFF59616E), Color(0xFFC9D6E8)),
    LevelTier._(2, 'Emas', 20, Color(0xFFFFE9A3), Color(0xFFE8A317), Color(0xFF7A5508), Color(0xFFFFC93C)),
    LevelTier._(3, 'Platinum', 30, Color(0xFFDFFBF7), Color(0xFF6FD6CB), Color(0xFF1E6E6A), Color(0xFF5FF0DF)),
    LevelTier._(4, 'Berlian', 50, Color(0xFFDDF1FF), Color(0xFF5AA8FF), Color(0xFF1B3F8F), Color(0xFF6FC3FF)),
    LevelTier._(5, 'Mitik', 75, Color(0xFFFFB8C8), Color(0xFFE0245E), Color(0xFF4A0A22), Color(0xFFFF3D6E)),
    LevelTier._(6, 'Legenda', 100, Color(0xFFFFFFFF), Color(0xFFB98CFF), Color(0xFF2A1050), Color(0xFFFFFFFF)),
  ];

  static LevelTier of(int level) {
    for (final t in all.reversed) {
      if (level >= t.minLevel) return t;
    }
    return all.first;
  }
}

const List<Color> _rainbow = [
  Color(0xFFFF5E7E),
  Color(0xFFFFB45E),
  Color(0xFFFFF27A),
  Color(0xFF5EFFB1),
  Color(0xFF5EC8FF),
  Color(0xFFB98CFF),
  Color(0xFFFF5E7E),
];

// ==================================================================== style

enum LevelBadgeStyle {
  // --- Futuristik
  hexCore('hex_core', 'Hex Core', Duration(milliseconds: 2800)),
  energyPill('energy_pill', 'Energy Bar', Duration(milliseconds: 2200)),
  digitalLcd('digital_lcd', 'Digital LCD', Duration(milliseconds: 3200)),
  // --- Rank game
  chevronShield('chevron_shield', 'Perisai Pangkat', Duration(milliseconds: 3000)),
  wingCrest('wing_crest', 'Sayap', Duration(milliseconds: 2400)),
  flameAura('flame_aura', 'Api Aura', Duration(milliseconds: 1600)),
  // --- Jepang
  obiBelt('obi_belt', 'Sabuk Obi', Duration(milliseconds: 3000)),
  hankoStamp('hanko_stamp', 'Cap Hanko', Duration(milliseconds: 3400));

  const LevelBadgeStyle(this.id, this.label, this.period);

  final String id;
  final String label;
  final Duration period;

  static LevelBadgeStyle fromId(String? id) => LevelBadgeStyle.values.firstWhere(
        (s) => s.id == id,
        orElse: () => LevelBadgeStyle.hexCore,
      );

  (double, double) get _pad => switch (this) {
        hexCore => (0.6, 0.6),
        energyPill => (0.5, 0.5),
        digitalLcd => (0.78, 0.45),
        chevronShield => (1.05, 0.5),
        wingCrest => (0.95, 0.95),
        flameAura => (0.5, 0.65),
        obiBelt => (1.0, 0.45),
        hankoStamp => (0.5, 0.5),
      };
}

// =================================================================== widget

class LevelStyledBadge extends StatefulWidget {
  const LevelStyledBadge({
    super.key,
    required this.level,
    this.style = LevelBadgeStyle.hexCore,
    this.height = 20,
    this.progress,
    this.onTap,
  });

  /// Hitung progress XP otomatis dari [XpLevelFormula].
  factory LevelStyledBadge.fromXp({
    Key? key,
    required int level,
    required int totalXp,
    LevelBadgeStyle style = LevelBadgeStyle.hexCore,
    double height = 20,
    VoidCallback? onTap,
  }) =>
      LevelStyledBadge(
        key: key,
        level: level,
        style: style,
        height: height,
        progress: XpLevelFormula.progress(totalXp, level).fraction,
        onTap: onTap,
      );

  final int level;
  final LevelBadgeStyle style;
  final double height;

  /// Progress XP ke level berikutnya (0..1). Dipakai Hex Core & Energy Bar;
  /// null = penuh.
  final double? progress;
  final VoidCallback? onTap;

  @override
  State<LevelStyledBadge> createState() => _LevelStyledBadgeState();
}

class _LevelStyledBadgeState extends State<LevelStyledBadge> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.style.period);
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _c.stop();
      _c.value = 0.3;
      _intro.value = 1;
    } else {
      if (!_c.isAnimating) _c.repeat();
      if (_intro.value == 0) _intro.forward();
    }
  }

  @override
  void didUpdateWidget(covariant LevelStyledBadge old) {
    super.didUpdateWidget(old);
    final tierChanged = LevelTier.of(old.level) != LevelTier.of(widget.level);
    if (old.style != widget.style) _c.duration = widget.style.period;
    if ((old.style != widget.style || tierChanged) && !_reduceMotion) {
      _c.repeat();
      _intro.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final tier = LevelTier.of(widget.level);
    final (pl, pr) = widget.style._pad;
    final progress = (widget.progress ?? 1.0).clamp(0.0, 1.0);

    final badge = RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_c, _intro]),
        builder: (context, _) {
          final t = _c.value;
          final r = Curves.easeOutCubic.transform(_intro.value);
          Widget body = CustomPaint(
            painter: _LevelBadgePainter(widget.style, tier, t, r, progress),
            child: SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.only(left: h * pl, right: h * pr),
                child: Center(widthFactor: 1, child: _label(tier, t)),
              ),
            ),
          );
          if (widget.style == LevelBadgeStyle.hankoStamp) {
            // Efek "dicap": turun dari besar ke ukuran normal.
            body = Opacity(
              opacity: r.clamp(0.0, 1.0),
              child: Transform.scale(scale: 1 + 0.6 * (1 - r), child: body),
            );
          }
          return body;
        },
      ),
    );

    return Tooltip(
      message: 'Level ${widget.level} · ${tier.name}',
      child: GestureDetector(onTap: widget.onTap, child: badge),
    );
  }

  Widget _label(LevelTier tier, double t) {
    final h = widget.height;
    String? family;
    var color = Colors.white;
    var spacing = 0.4;
    List<Shadow>? shadows;
    var opacity = 1.0;
    final dark = Color.lerp(tier.c3, Colors.black, 0.35)!;

    switch (widget.style) {
      case LevelBadgeStyle.hexCore:
        color = tier.c1;
        shadows = [Shadow(color: tier.glow.withValues(alpha: 0.4 + 0.5 * tier.fx), blurRadius: h * 0.3)];
      case LevelBadgeStyle.energyPill:
        shadows = const [Shadow(color: Color(0xAA000000), blurRadius: 2, offset: Offset(0, 1))];
      case LevelBadgeStyle.digitalLcd:
        family = 'monospace';
        color = tier.glow;
        spacing = 1.0;
        shadows = [Shadow(color: tier.glow.withValues(alpha: 0.8), blurRadius: h * 0.3)];
        if (t > 0.47 && t < 0.49) opacity = 0.45;
      case LevelBadgeStyle.chevronShield:
        color = tier.c1;
      case LevelBadgeStyle.wingCrest:
        color = dark;
      case LevelBadgeStyle.flameAura:
        shadows = [Shadow(color: tier.c2, blurRadius: h * 0.35)];
      case LevelBadgeStyle.obiBelt:
        color = tier.index <= 2 ? const Color(0xFF1A1A1A) : Colors.white;
        spacing = 0.8;
      case LevelBadgeStyle.hankoStamp:
        family = 'serif';
        color = const Color(0xFFB3121E);
        spacing = 0.6;
    }

    if (tier.isLegend && widget.style != LevelBadgeStyle.wingCrest &&
        widget.style != LevelBadgeStyle.obiBelt && widget.style != LevelBadgeStyle.hankoStamp) {
      // Legenda: teks pelangi mengalir.
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (b) => LinearGradient(
          colors: _rainbow,
          tileMode: TileMode.repeated,
          transform: _Slide(t),
        ).createShader(b),
        child: _rich(h, Colors.white, family, spacing, shadows),
      );
    }
    final txt = _rich(h, color, family, spacing, shadows);
    return opacity < 1 ? Opacity(opacity: opacity, child: txt) : txt;
  }

  Widget _rich(double h, Color color, String? family, double spacing, List<Shadow>? shadows) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: 'LV ',
          style: TextStyle(fontSize: h * 0.38, fontWeight: FontWeight.w800, color: color.withValues(alpha: 0.8)),
        ),
        TextSpan(text: '${widget.level}'),
      ]),
      maxLines: 1,
      style: TextStyle(
        fontFamily: family,
        fontSize: h * 0.6,
        fontWeight: FontWeight.w900,
        letterSpacing: spacing,
        height: 1.1,
        color: color,
        shadows: shadows,
      ),
    );
  }
}

// ================================================================== painter

class _LevelBadgePainter extends CustomPainter {
  _LevelBadgePainter(this.style, this.tier, this.t, this.reveal, this.progress);

  final LevelBadgeStyle style;
  final LevelTier tier;
  final double t;
  final double reveal;
  final double progress;

  static const _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size s) {
    switch (style) {
      case LevelBadgeStyle.hexCore:
        _hexCore(canvas, s);
      case LevelBadgeStyle.energyPill:
        _energyPill(canvas, s);
      case LevelBadgeStyle.digitalLcd:
        _digitalLcd(canvas, s);
      case LevelBadgeStyle.chevronShield:
        _chevronShield(canvas, s);
      case LevelBadgeStyle.wingCrest:
        _wingCrest(canvas, s);
      case LevelBadgeStyle.flameAura:
        _flameAura(canvas, s);
      case LevelBadgeStyle.obiBelt:
        _obiBelt(canvas, s);
      case LevelBadgeStyle.hankoStamp:
        _hankoStamp(canvas, s);
    }
  }

  Paint _glow(Color c, double width, double sigma) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = c
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

  Shader _rainbowShader(Rect r, {double shift = 0}) => LinearGradient(
        colors: _rainbow,
        tileMode: TileMode.repeated,
        transform: _Slide(shift),
      ).createShader(r);

  // ------------------------------------------------------------ 1 hex core
  void _hexCore(Canvas c, Size s) {
    final h = s.height, w = s.width;
    final p = _hexPath(Offset.zero, s, h * 0.45);
    final pulse = 0.5 + 0.5 * math.sin(t * _tau);

    c.drawPath(p, _glow(tier.glow.withValues(alpha: (0.15 + 0.4 * tier.fx) * (0.6 + 0.4 * pulse)), 2.4, h * 0.2));
    c.drawPath(
      p,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(tier.c3, Colors.black, 0.45)!, Color.lerp(tier.c3, Colors.black, 0.78)!],
        ).createShader(Offset.zero & s),
    );
    c.drawPath(
      _hexPath(const Offset(2.2, 2.2), Size(w - 4.4, h - 4.4), (h - 4.4) * 0.45),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = tier.c2.withValues(alpha: 0.35),
    );

    final sw = math.max(1.4, h * 0.09);
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    for (final m in p.computeMetrics()) {
      final end = m.length * progress;
      if (end > 0.5) {
        c.drawPath(
          m.extractPath(0, end),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = tier.c1
            ..shader = tier.isLegend ? _rainbowShader(Offset.zero & s, shift: t) : null,
        );
        final tip = m.getTangentForOffset(end)?.position;
        if (tip != null && progress < 1) {
          c.drawCircle(
            tip,
            sw * (1.2 + 0.6 * pulse),
            Paint()
              ..color = tier.glow
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw),
          );
        }
      }
      if (tier.index >= 3) {
        _comet(c, m, t, 0.14, Colors.white, sw * 0.8);
      }
    }
  }

  // ---------------------------------------------------------- 2 energy bar
  void _energyPill(Canvas c, Size s) {
    final h = s.height, w = s.width;
    final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(h / 2));
    c.drawRRect(rr, _glow(tier.glow.withValues(alpha: 0.15 + 0.45 * tier.fx), 2.4, h * 0.2));
    c.drawRRect(rr, Paint()..color = Color.lerp(tier.c3, Colors.black, 0.62)!);

    c.save();
    c.clipRRect(rr);
    final fw = w * progress;
    if (fw > 0.5) {
      final amp = h * 0.08;
      final liquid = Path()..moveTo(0, 0);
      for (double y = 0; y <= h; y += 1) {
        liquid.lineTo(fw + amp * math.sin(y / h * _tau + t * _tau) - amp, y);
      }
      liquid
        ..lineTo(0, h)
        ..close();
      final r = Rect.fromLTWH(0, 0, math.max(fw, 1), h);
      c.drawPath(
        liquid,
        Paint()
          ..shader = tier.isLegend
              ? _rainbowShader(r, shift: t)
              : LinearGradient(colors: [tier.c3, tier.c2, tier.c1]).createShader(r),
      );
      c.drawRect(Rect.fromLTWH(0, h * 0.08, fw, h * 0.28), Paint()..color = Colors.white.withValues(alpha: 0.2));
      if (tier.index >= 2) {
        const bubbles = [(0.15, 0.0), (0.38, 0.45), (0.62, 0.2), (0.82, 0.7)];
        for (final (fx, ph) in bubbles) {
          final bx = fw * fx;
          final by = h - ((t + ph) % 1) * h * 1.1;
          c.drawCircle(Offset(bx, by), h * 0.055, Paint()..color = Colors.white.withValues(alpha: 0.5));
        }
      }
    }
    c.restore();
    c.drawRRect(
      rr.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = tier.c2.withValues(alpha: 0.9),
    );
  }

  // ---------------------------------------------------------- 3 digital lcd
  void _digitalLcd(Canvas c, Size s) {
    final h = s.height, w = s.width, k = h * 0.22;
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(w - k, 0)
      ..lineTo(w, k)
      ..lineTo(w, h)
      ..lineTo(k, h)
      ..lineTo(0, h - k)
      ..close();
    final dim = (t > 0.47 && t < 0.49) ? 0.5 : 1.0;

    c.drawPath(p, _glow(tier.glow.withValues(alpha: (0.2 + 0.4 * tier.fx) * dim), 2, h * 0.18));
    c.drawPath(p, Paint()..color = const Color(0xFF05080C));
    c.save();
    c.clipPath(p);
    c.drawRect(Offset.zero & s, Paint()..color = tier.c3.withValues(alpha: 0.28));
    final sl = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    for (double y = 1; y < h; y += 2) {
      c.drawLine(Offset(0, y), Offset(w, y), sl);
    }
    final ry = ((t * 3) % 1) * h;
    c.drawRect(Rect.fromLTWH(0, ry, w, h * 0.12), Paint()..color = tier.glow.withValues(alpha: 0.12));
    c.restore();

    // bar sinyal = tier
    final lit = ((tier.index + 1) * 4 / 7).ceil();
    for (var i = 0; i < 4; i++) {
      final bh = h * 0.55 * (0.3 + 0.7 * i / 3);
      final x = h * 0.16 + i * h * 0.13;
      c.drawRect(
        Rect.fromLTWH(x, h * 0.78 - bh, h * 0.09, bh),
        Paint()..color = i < lit ? tier.glow.withValues(alpha: dim) : Colors.white.withValues(alpha: 0.12),
      );
    }
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = tier.glow.withValues(alpha: 0.6 * dim),
    );
  }

  // ------------------------------------------------------- 4 chevron shield
  void _chevronShield(Canvas c, Size s) {
    final h = s.height, w = s.width, sw = h * 0.85;

    final body = Path()
      ..moveTo(sw * 0.6, h * 0.14)
      ..lineTo(w, h * 0.14)
      ..lineTo(w - h * 0.18, h * 0.86)
      ..lineTo(sw * 0.6, h * 0.86)
      ..close();
    c.drawPath(body, Paint()..color = Color.lerp(tier.c3, Colors.black, 0.55)!);
    c.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = tier.c2.withValues(alpha: 0.8),
    );

    final shield = Path()
      ..moveTo(0, 0)
      ..lineTo(sw, 0)
      ..lineTo(sw, h * 0.55)
      ..quadraticBezierTo(sw, h * 0.85, sw / 2, h)
      ..quadraticBezierTo(0, h * 0.85, 0, h * 0.55)
      ..close();
    final sr = Rect.fromLTWH(0, 0, sw, h);
    if (tier.index >= 2) {
      final pulse = 0.5 + 0.5 * math.sin(t * _tau);
      c.drawPath(shield, _glow(tier.glow.withValues(alpha: 0.3 + 0.4 * tier.fx * pulse), 2.4, h * 0.18));
    }
    c.drawPath(
      shield,
      Paint()
        ..shader = tier.isLegend
            ? SweepGradient(colors: _rainbow, transform: GradientRotation(t * _tau)).createShader(sr)
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tier.c1, tier.c2, tier.c3],
              ).createShader(sr),
    );
    c.save();
    c.clipPath(shield);
    if (t < 0.5) {
      final x = -h * 0.5 + (t / 0.5) * (sw + h);
      c.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + h * 0.25, 0)
          ..lineTo(x - h * 0.15, h)
          ..lineTo(x - h * 0.4, h)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }
    c.restore();
    c.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Color.lerp(tier.c3, Colors.black, 0.3)!,
    );

    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, h * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Color.lerp(tier.c3, Colors.black, 0.35)!;
    final star = tier.index >= 5;
    final count = star ? 2 : (tier.index <= 1 ? 1 : (tier.index <= 3 ? 2 : 3));
    final startY = star ? h * 0.44 : h * (0.5 - (count - 1) * 0.08);
    for (var i = 0; i < count; i++) {
      final y = startY + i * h * 0.16;
      c.drawPath(
        Path()
          ..moveTo(sw / 2 - sw * 0.28, y - h * 0.06)
          ..lineTo(sw / 2, y + h * 0.06)
          ..lineTo(sw / 2 + sw * 0.28, y - h * 0.06),
        ink,
      );
    }
    if (star) {
      c.drawPath(_starPath(Offset(sw / 2, h * 0.24), h * 0.13, h * 0.055), Paint()..color = ink.color);
    }
  }

  // ------------------------------------------------------------- 5 wings
  void _wingCrest(Canvas c, Size s) {
    final h = s.height, w = s.width;
    final n = 2 + tier.index ~/ 2;
    final flap = math.sin(t * _tau) * 0.09;
    final feather = Paint()
      ..shader = tier.isLegend
          ? _rainbowShader(Offset.zero & s, shift: t)
          : LinearGradient(colors: [tier.c2, tier.c1]).createShader(Rect.fromLTWH(0, 0, h, h));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = tier.c3.withValues(alpha: 0.6);

    void wing() {
      for (var i = 0; i < n; i++) {
        final k = n == 1 ? 0.0 : i / (n - 1);
        final a = math.pi + (-0.62 + 1.05 * k) + flap * (1 - k);
        final len = h * 0.74 * (1 - 0.22 * k);
        c.save();
        c.rotate(a);
        final leaf = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(len * 0.5, -h * 0.13, len, 0)
          ..quadraticBezierTo(len * 0.5, h * 0.13, 0, 0)
          ..close();
        c.drawPath(leaf, feather);
        c.drawPath(leaf, edge);
        c.restore();
      }
    }

    c.save();
    c.translate(h * 0.85, h * 0.5);
    wing();
    c.restore();
    c.save();
    c.translate(w - h * 0.85, h * 0.5);
    c.scale(-1, 1);
    wing();
    c.restore();

    final body = RRect.fromLTRBR(h * 0.72, h * 0.08, w - h * 0.72, h * 0.92, Radius.circular(h * 0.25));
    if (tier.index >= 2) {
      c.drawRRect(body, _glow(tier.glow.withValues(alpha: 0.25 + 0.45 * tier.fx), 2.4, h * 0.2));
    }
    c.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: tier.isLegend ? const [Colors.white, Color(0xFFE7DBFF)] : [tier.c1, tier.c2],
        ).createShader(body.outerRect),
    );
    c.save();
    c.clipRRect(body);
    final x = body.left - h + ((t * 1.0) % 1) * (body.width + h * 2);
    c.drawRect(
      Rect.fromLTWH(x, 0, h * 0.35, h),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
    c.restore();
    c.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = tier.c3.withValues(alpha: 0.7),
    );

    if (tier.index >= 4) {
      const spots = [(0.06, 0.2, 0.0), (0.94, 0.25, 0.4), (0.12, 0.85, 0.65), (0.9, 0.8, 0.2)];
      for (final (fx, fy, ph) in spots) {
        final k = math.max(0.0, math.sin((t + ph) * _tau));
        if (k > 0.01) _sparkle(c, Offset(w * fx, h * fy), h * 0.18 * k);
      }
    }
  }

  // --------------------------------------------------------- 6 flame aura
  void _flameAura(Canvas c, Size s) {
    final h = s.height, w = s.width;
    final p = Path()
      ..moveTo(h * 0.28, 0)
      ..lineTo(w - h * 0.42, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w - h * 0.42, h)
      ..lineTo(h * 0.28, h)
      ..lineTo(0, h / 2)
      ..close();
    final pulse = 0.5 + 0.5 * math.sin(t * _tau * 2);
    c.drawPath(p, _glow(tier.c2.withValues(alpha: (0.25 + 0.5 * tier.fx) * (0.7 + 0.3 * pulse)), 2.6, h * 0.22));
    c.drawPath(
      p,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF0D0A0A), Color.lerp(tier.c3, Colors.black, 0.55)!],
        ).createShader(Offset.zero & s),
    );

    c.save();
    c.clipPath(p);
    final step = h * 0.34;
    final strength = 0.45 + 0.35 * tier.fx;
    for (var layer = 0; layer < 2; layer++) {
      final inner = layer == 1;
      final col = inner ? tier.c1 : tier.c2;
      for (var k = 0; k * step < w + step; k++) {
        final x = k * step + (inner ? step * 0.5 : 0);
        final wob = math.sin(t * _tau * 2 + k * 1.7) * 0.5 + math.sin(t * _tau * 3 + k * 0.9) * 0.5;
        final fh = h * strength * (inner ? 0.6 : 1.0) * (0.7 + 0.3 * wob);
        final bw = h * (inner ? 0.15 : 0.22);
        final sway = h * 0.06 * math.sin(t * _tau * 2 + k);
        final tongue = Path()
          ..moveTo(x - bw, h)
          ..quadraticBezierTo(x - bw * 0.8, h - fh * 0.5, x + sway, h - fh)
          ..quadraticBezierTo(x + bw * 0.8, h - fh * 0.5, x + bw, h)
          ..close();
        c.drawPath(
          tongue,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [col.withValues(alpha: 0.9), col.withValues(alpha: 0)],
            ).createShader(Rect.fromLTRB(x - bw, h - fh, x + bw, h)),
        );
      }
    }
    if (tier.index >= 2) {
      for (var i = 0; i < 5; i++) {
        final ph = i / 5;
        final y = h - ((t * 1.3 + ph) % 1) * h * 1.1;
        final x = w * (0.15 + 0.17 * i) + math.sin((t + ph) * _tau) * h * 0.1;
        c.drawCircle(Offset(x, y), h * 0.04, Paint()..color = tier.c1.withValues(alpha: 0.85));
      }
    }
    c.restore();
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = tier.isLegend ? _rainbowShader(Offset.zero & s, shift: t) : null
        ..color = tier.c2.withValues(alpha: 0.85),
    );
  }

  // ------------------------------------------------------------- 7 obi belt
  static const _beltColors = [
    Color(0xFFF2F0EA),
    Color(0xFFF5C518),
    Color(0xFFF28C28),
    Color(0xFF2FA44F),
    Color(0xFF2D6CDF),
    Color(0xFF6B3E26),
    Color(0xFF15161A),
  ];

  void _obiBelt(Canvas c, Size s) {
    final h = s.height, w = s.width;
    final base = _beltColors[tier.index];
    final light = Color.lerp(base, Colors.white, 0.22)!;
    final dark = Color.lerp(base, Colors.black, 0.28)!;
    const gold = Color(0xFFD4AF37);
    final knot = Offset(h * 0.5, h * 0.5);

    // ekor sabuk (bergoyang)
    final sway = math.sin(t * _tau) * 0.12;
    for (final (ang, len) in [(math.pi / 2 + 0.55, h * 0.55), (math.pi / 2 + 0.12, h * 0.5)]) {
      c.save();
      c.translate(knot.dx, knot.dy);
      c.rotate(ang + sway - math.pi / 2);
      final tail = Rect.fromLTWH(-h * 0.12, 0, h * 0.24, len);
      c.drawRect(tail, Paint()..color = dark);
      if (tier.isLegend) {
        c.drawRect(Rect.fromLTWH(-h * 0.12, len - h * 0.1, h * 0.24, h * 0.05), Paint()..color = gold);
      }
      c.restore();
    }

    final band = RRect.fromLTRBAndCorners(
      h * 0.55,
      h * 0.18,
      w,
      h * 0.82,
      topRight: Radius.circular(h * 0.08),
      bottomRight: Radius.circular(h * 0.08),
    );
    c.drawRRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, base, dark],
        ).createShader(band.outerRect),
    );
    final stitch = Paint()
      ..color = tier.isLegend
          ? gold.withValues(alpha: 0.85)
          : (tier.index <= 2 ? Colors.black.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.3))
      ..strokeWidth = math.max(0.6, h * 0.035);
    for (final y in [h * 0.27, h * 0.73]) {
      for (double x = h * 0.65; x < w - h * 0.1; x += h * 0.2) {
        c.drawLine(Offset(x, y), Offset(x + h * 0.12, y), stitch);
      }
    }
    if (t < 0.5) {
      c.save();
      c.clipRRect(band);
      final x = -h + (t / 0.5) * (w + h * 2);
      c.drawRect(Rect.fromLTWH(x, 0, h * 0.4, h), Paint()..color = Colors.white.withValues(alpha: 0.22));
      c.restore();
    }

    final kr = RRect.fromRectAndRadius(
      Rect.fromCenter(center: knot, width: h * 0.5, height: h * 0.64),
      Radius.circular(h * 0.1),
    );
    c.drawRRect(kr, Paint()..color = Color.lerp(base, Colors.black, 0.12)!);
    c.drawLine(
      Offset(kr.left + h * 0.08, kr.top + h * 0.1),
      Offset(kr.right - h * 0.08, kr.bottom - h * 0.1),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..strokeWidth = math.max(0.6, h * 0.04),
    );
    c.drawRRect(
      kr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = Colors.black.withValues(alpha: 0.3),
    );
  }

  // ---------------------------------------------------------- 8 hanko stamp
  void _hankoStamp(Canvas c, Size s) {
    final h = s.height, w = s.width;
    const ink = Color(0xFFB3121E);
    final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(h * 0.12));
    final pulse = 0.5 + 0.5 * math.sin(t * _tau);

    if (tier.index >= 4) {
      c.drawRRect(rr, _glow(tier.glow.withValues(alpha: 0.3 + 0.4 * pulse), 2.4, h * 0.2));
    }
    c.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7EEDD), Color(0xFFEEDFC4)],
        ).createShader(Offset.zero & s),
    );
    if (tier.index >= 1) {
      c.drawRRect(
        rr.deflate(0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, h * 0.07)
          ..shader = tier.isLegend ? _rainbowShader(Offset.zero & s, shift: t) : null
          ..color = tier.c2,
      );
    }

    // bingkai tinta kasar (jitter deterministik, jadi stabil antar frame)
    final inset = h * 0.17;
    final rect = Rect.fromLTRB(inset, inset, w - inset, h - inset);
    final rough = Path();
    final per = (rect.width + rect.height) * 2;
    final n = (per / 2.5).ceil();
    for (var i = 0; i <= n; i++) {
      final d = per * i / n;
      final pt = _rectPoint(rect, d);
      final j = (math.sin(i * 12.9898) * 43758.5453) % 1 * h * 0.03;
      final q = Offset(pt.dx + j, pt.dy - j);
      i == 0 ? rough.moveTo(q.dx, q.dy) : rough.lineTo(q.dx, q.dy);
    }
    rough.close();
    c.drawPath(
      rough,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, h * 0.075)
        ..strokeJoin = StrokeJoin.round
        ..color = ink.withValues(alpha: 0.92),
    );
    c.drawRect(
      rect.deflate(h * 0.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, h * 0.025)
        ..color = ink.withValues(alpha: 0.55),
    );
    // kilau tinta basah
    c.save();
    c.clipRRect(rr);
    final x = -h + t * (w + h * 2);
    c.drawRect(Rect.fromLTWH(x, 0, h * 0.5, h), Paint()..color = Colors.white.withValues(alpha: 0.18));
    c.restore();
  }

  // ------------------------------------------------------------- helpers

  Path _hexPath(Offset o, Size s, double tip) => Path()
    ..moveTo(o.dx + tip, o.dy)
    ..lineTo(o.dx + s.width - tip, o.dy)
    ..lineTo(o.dx + s.width, o.dy + s.height / 2)
    ..lineTo(o.dx + s.width - tip, o.dy + s.height)
    ..lineTo(o.dx + tip, o.dy + s.height)
    ..lineTo(o.dx, o.dy + s.height / 2)
    ..close();

  Offset _rectPoint(Rect r, double d) {
    final w = r.width, h = r.height;
    if (d < w) return Offset(r.left + d, r.top);
    d -= w;
    if (d < h) return Offset(r.right, r.top + d);
    d -= h;
    if (d < w) return Offset(r.right - d, r.bottom);
    d -= w;
    return Offset(r.left, r.bottom - math.min(d, h));
  }

  Path _starPath(Offset o, double outer, double inner) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? outer : inner;
      final pt = o + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  void _comet(Canvas c, ui.PathMetric m, double pos, double frac, Color color, double width) {
    final len = m.length, seg = len * frac, head = pos * len;
    const n = 6;
    for (var i = 0; i < n; i++) {
      final a = head - seg + seg * i / n;
      final b = head - seg + seg * (i + 1) / n;
      final start = a % len;
      final end = start + (b - a);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = color.withValues(alpha: 0.7 * (i + 1) / n);
      if (end <= len) {
        c.drawPath(m.extractPath(start, end), paint);
      } else {
        c.drawPath(m.extractPath(start, len), paint);
        c.drawPath(m.extractPath(0, end - len), paint);
      }
    }
  }

  void _sparkle(Canvas c, Offset o, double r) {
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
      ..close();
    c.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LevelBadgePainter old) =>
      old.t != t ||
      old.reveal != reveal ||
      old.style != style ||
      old.tier != tier ||
      old.progress != progress;
}

class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(-bounds.width * t, 0, 0);
}

// ================================================================== gallery

/// Layar uji: tiap gaya di semua tier.
class LevelBadgeGallery extends StatelessWidget {
  const LevelBadgeGallery({super.key, this.onPick});

  final ValueChanged<LevelBadgeStyle>? onPick;

  static const _sample = [5, 15, 25, 40, 60, 85, 120];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D14),
      appBar: AppBar(title: const Text('Gaya Badge Level')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: LevelBadgeStyle.values.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, i) {
          final st = LevelBadgeStyle.values[i];
          return InkWell(
            onTap: onPick == null ? null : () => onPick!(st),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141826),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(st.label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 12,
                    children: [
                      for (final lv in _sample)
                        LevelStyledBadge(level: lv, style: st, height: 24, progress: 0.65),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
