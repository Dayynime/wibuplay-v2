import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/decor_tick.dart';

/// Koleksi gaya badge tag clan beranimasi (pengganti / alternatif
/// [ClanRainbowBadge] & [ClanNameTag]).
///
/// Pakai:
/// ```dart
/// ClanStyledBadge(text: clan.tag, style: ClanBadgeStyle.neonHex, height: 20)
/// ClanStyledBadge(text: clan.tag, style: ClanBadgeStyle.fromId(clan.badgeStyle))
/// ```
///
/// Semua digambar pakai CustomPainter (tanpa aset / package tambahan),
/// satu AnimationController per badge, dibungkus RepaintBoundary, dan
/// animasi berhenti kalau "reduce motion" aktif.
enum ClanBadgeStyle {
  // --- Modern / futuristik
  neonHex('neon_hex', 'Neon Hex', Duration(milliseconds: 2600)),
  holoShard('holo_shard', 'Holo Shard', Duration(milliseconds: 3200)),
  cyberHud('cyber_hud', 'Cyber HUD', Duration(milliseconds: 3000)),
  auraOrbit('aura_orbit', 'Aura Orbit', Duration(milliseconds: 2400)),
  crystalPrism('crystal_prism', 'Crystal Prism', Duration(milliseconds: 3600)),
  // --- Shinobi / Jepang
  makimono('makimono', 'Gulungan Makimono', Duration(milliseconds: 4000)),
  ofudaSeal('ofuda_seal', 'Segel Ofuda', Duration(milliseconds: 2800)),
  kamonCrest('kamon_crest', 'Lambang Kamon', Duration(milliseconds: 9000)),
  kunai('kunai', 'Kunai', Duration(milliseconds: 2600));

  const ClanBadgeStyle(this.id, this.label, this.period);

  /// Disimpan di DB (mis. kolom `clans.badge_style`).
  final String id;
  final String label;
  final Duration period;

  static ClanBadgeStyle fromId(String? id) => ClanBadgeStyle.values.firstWhere(
        (s) => s.id == id,
        orElse: () => ClanBadgeStyle.neonHex,
      );

  /// Padding kiri/kanan teks, dalam kelipatan tinggi badge.
  (double, double) get _pad => switch (this) {
        neonHex => (0.55, 0.55),
        holoShard => (0.55, 0.55),
        cyberHud => (0.45, 0.55),
        auraOrbit => (0.55, 0.55),
        crystalPrism => (0.6, 0.6),
        makimono => (0.55, 0.55),
        ofudaSeal => (1.05, 0.42),
        kamonCrest => (1.2, 0.5),
        kunai => (1.25, 0.85),
      };
}

class ClanStyledBadge extends StatefulWidget {
  const ClanStyledBadge({
    super.key,
    required this.text,
    this.style = ClanBadgeStyle.neonHex,
    this.height = 20,
    this.onTap,
  });

  final String text;
  final ClanBadgeStyle style;
  final double height;
  final VoidCallback? onTap;

  @override
  State<ClanStyledBadge> createState() => _ClanStyledBadgeState();
}

class _ClanStyledBadgeState extends State<ClanStyledBadge>
    with TickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.style.period);

  /// Animasi masuk sekali jalan (gulungan terbuka, segel "dicap").
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  /// Loop digambar ulang maks DecorTick.fps; intro tetap tiap frame.
  late final Listenable _tick = Listenable.merge([DecorTick(_c), _intro]);

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
  void didUpdateWidget(covariant ClanStyledBadge old) {
    super.didUpdateWidget(old);
    if (old.style != widget.style) {
      _c.duration = widget.style.period;
      if (!_reduceMotion) {
        _c.repeat();
        _intro.forward(from: 0);
      }
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
    final (pl, pr) = widget.style._pad;
    final badge = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _tick,
        builder: (context, _) {
          final t = _c.value;
          final r = Curves.easeOutCubic.transform(_intro.value);
          return CustomPaint(
            painter: _ClanBadgePainter(widget.style, t, r),
            child: SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.only(left: h * pl, right: h * pr),
                child: Center(
                  widthFactor: 1,
                  child: _label(t, r),
                ),
              ),
            ),
          );
        },
      ),
    );
    return Tooltip(
      message: 'Clan ${widget.text}',
      child: GestureDetector(onTap: widget.onTap, child: badge),
    );
  }

  Widget _label(double t, double r) {
    final h = widget.height;
    final base = TextStyle(
      fontSize: h * 0.55,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.6,
      height: 1.1,
      color: Colors.white,
    );
    Text txt(TextStyle s) => Text(widget.text, maxLines: 1, style: s);

    switch (widget.style) {
      case ClanBadgeStyle.neonHex:
        final p = 0.5 + 0.5 * math.sin(t * math.pi * 4);
        return txt(base.copyWith(shadows: [
          Shadow(color: const Color(0xFF22E5FF).withValues(alpha: 0.6 + 0.4 * p), blurRadius: h * 0.3),
        ]));

      case ClanBadgeStyle.holoShard:
        return txt(base.copyWith(color: const Color(0xFF14143A)));

      case ClanBadgeStyle.cyberHud:
        const green = Color(0xFF3DFF9A);
        final s = base.copyWith(
          color: green,
          letterSpacing: 1.0,
          shadows: [Shadow(color: green.withValues(alpha: 0.7), blurRadius: h * 0.25)],
        );
        final glitch = (t > 0.30 && t < 0.33) || (t > 0.71 && t < 0.735);
        if (!glitch) return txt(s);
        final dx = h * 0.07;
        return Stack(children: [
          Transform.translate(
            offset: Offset(-dx, 0),
            child: txt(s.copyWith(color: const Color(0xCCFF2D55), shadows: const [])),
          ),
          Transform.translate(
            offset: Offset(dx, h * 0.03),
            child: txt(s.copyWith(color: const Color(0xCC22E5FF), shadows: const [])),
          ),
          txt(s),
        ]);

      case ClanBadgeStyle.auraOrbit:
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (b) => LinearGradient(
            colors: const [Color(0xFFFFB8F0), Colors.white, Color(0xFFB8F3FF), Color(0xFFFFB8F0)],
            tileMode: TileMode.repeated,
            transform: _Slide(t),
          ).createShader(b),
          child: txt(base),
        );

      case ClanBadgeStyle.crystalPrism:
        return txt(base.copyWith(color: const Color(0xFF0A2A4F)));

      case ClanBadgeStyle.makimono:
        return Opacity(
          opacity: ((r - 0.45) / 0.55).clamp(0.0, 1.0),
          child: txt(base.copyWith(
            color: const Color(0xFF3A1A0A),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          )),
        );

      case ClanBadgeStyle.ofudaSeal:
        return txt(base.copyWith(color: const Color(0xFFB00D18), letterSpacing: 1.1));

      case ClanBadgeStyle.kamonCrest:
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (b) => LinearGradient(
            colors: const [Color(0xFFFFE9A3), Color(0xFFD4AF37), Color(0xFFFFF3C4), Color(0xFFFFE9A3)],
            tileMode: TileMode.repeated,
            transform: _Slide(t * 3),
          ).createShader(b),
          child: txt(base.copyWith(letterSpacing: 1.0)),
        );

      case ClanBadgeStyle.kunai:
        return txt(base.copyWith(
          color: const Color(0xFFEFF3F8),
          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 2, offset: Offset(0, 1))],
        ));
    }
  }
}

// =================================================================== painter

class _ClanBadgePainter extends CustomPainter {
  _ClanBadgePainter(this.style, this.t, this.reveal);

  final ClanBadgeStyle style;
  final double t;
  final double reveal;

  static const _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size s) {
    switch (style) {
      case ClanBadgeStyle.neonHex:
        _neonHex(canvas, s);
      case ClanBadgeStyle.holoShard:
        _holoShard(canvas, s);
      case ClanBadgeStyle.cyberHud:
        _cyberHud(canvas, s);
      case ClanBadgeStyle.auraOrbit:
        _auraOrbit(canvas, s);
      case ClanBadgeStyle.crystalPrism:
        _crystalPrism(canvas, s);
      case ClanBadgeStyle.makimono:
        _makimono(canvas, s);
      case ClanBadgeStyle.ofudaSeal:
        _ofudaSeal(canvas, s);
      case ClanBadgeStyle.kamonCrest:
        _kamonCrest(canvas, s);
      case ClanBadgeStyle.kunai:
        _kunai(canvas, s);
    }
  }

  // ---------------------------------------------------------------- 1 neon
  void _neonHex(Canvas c, Size s) {
    final h = s.height;
    const cyan = Color(0xFF22E5FF);
    const magenta = Color(0xFFFF3DCB);
    final p = _hexPath(s, h * 0.42);
    final pulse = 0.5 + 0.5 * math.sin(t * _tau * 2);

    c.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF13204A), Color(0xFF070A18)],
        ).createShader(Offset.zero & s),
    );
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = cyan.withValues(alpha: 0.25 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.15),
    );
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = cyan.withValues(alpha: 0.35 + 0.25 * pulse),
    );
    _comet(c, p, t, 0.3, cyan, math.max(1.4, h * 0.08));
    _comet(c, p, (t + 0.5) % 1, 0.3, magenta, math.max(1.4, h * 0.08));
  }

  // ---------------------------------------------------------------- 2 holo
  void _holoShard(Canvas c, Size s) {
    final h = s.height, w = s.width, sk = h * 0.38;
    final r = Offset.zero & s;
    final p = Path()
      ..moveTo(sk, 0)
      ..lineTo(w, 0)
      ..lineTo(w - sk, h)
      ..lineTo(0, h)
      ..close();

    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFF9A8D4).withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.18),
    );

    c.save();
    c.clipPath(p);
    c.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -0.6),
          end: const Alignment(1, 0.6),
          tileMode: TileMode.repeated,
          colors: const [
            Color(0xFF7DF9FF),
            Color(0xFFA78BFA),
            Color(0xFFF9A8D4),
            Color(0xFFFDE68A),
            Color(0xFF7DF9FF),
          ],
          transform: _Slide(t),
        ).createShader(r),
    );
    final sl = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 0.6;
    for (double y = 1; y < h; y += 2.4) {
      c.drawLine(Offset(0, y), Offset(w, y), sl);
    }
    // kilau diagonal (lewat sekali tiap siklus, lalu jeda)
    if (t < 0.55) {
      final x = -h + (t / 0.55) * (w + h * 2);
      final bw = h * 0.6;
      c.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + bw, 0)
          ..lineTo(x + bw - sk, h)
          ..lineTo(x - sk, h)
          ..close(),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.08),
      );
    }
    c.restore();

    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  // ----------------------------------------------------------------- 3 hud
  void _cyberHud(Canvas c, Size s) {
    final h = s.height, w = s.width, k = h * 0.32;
    const green = Color(0xFF3DFF9A);
    final p = Path()
      ..moveTo(k, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - k)
      ..lineTo(w - k, h)
      ..lineTo(0, h)
      ..lineTo(0, k)
      ..close();

    c.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF062A1E), Color(0xFF02110C)],
        ).createShader(Offset.zero & s),
    );

    c.save();
    c.clipPath(p);
    final grid = Paint()
      ..color = green.withValues(alpha: 0.07)
      ..strokeWidth = 0.6;
    for (double x = 2; x < w; x += 4) {
      c.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    final sx = -h + t * (w + h * 2);
    final band = Rect.fromLTWH(sx - h * 0.6, 0, h * 1.2, h);
    c.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(colors: [
          green.withValues(alpha: 0),
          green.withValues(alpha: 0.35),
          green.withValues(alpha: 0),
        ]).createShader(band),
    );
    c.drawLine(
      Offset(sx, 0),
      Offset(sx, h),
      Paint()
        ..color = green.withValues(alpha: 0.8)
        ..strokeWidth = 0.8,
    );
    c.restore();

    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = green.withValues(alpha: 0.45),
    );
    final br = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, h * 0.08)
      ..strokeCap = StrokeCap.square
      ..color = green;
    c.drawPath(
      Path()
        ..moveTo(0, k + h * 0.22)
        ..lineTo(0, k)
        ..lineTo(k, 0)
        ..lineTo(k + h * 0.35, 0),
      br,
    );
    c.drawPath(
      Path()
        ..moveTo(w, h - k - h * 0.22)
        ..lineTo(w, h - k)
        ..lineTo(w - k, h)
        ..lineTo(w - k - h * 0.35, h),
      br,
    );
    if ((t * 4) % 1 < 0.5) {
      c.drawCircle(Offset(w - h * 0.2, h * 0.24), h * 0.07, Paint()..color = green);
    }
  }

  // ---------------------------------------------------------------- 4 aura
  void _auraOrbit(Canvas c, Size s) {
    final h = s.height;
    final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(h / 2));
    final sweep = SweepGradient(
      colors: const [
        Color(0xFFFF4FD8),
        Color(0xFF8B5CF6),
        Color(0xFF22D3EE),
        Color(0x0022D3EE),
        Color(0xFFFF4FD8),
      ],
      stops: const [0, 0.3, 0.55, 0.8, 1],
      transform: GradientRotation(t * _tau),
    ).createShader(Offset.zero & s);

    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.22
        ..shader = sweep
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.2),
    );
    c.drawRRect(
      rr,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.4,
          colors: [Color(0xFF2A1458), Color(0xFF0B0620)],
        ).createShader(Offset.zero & s),
    );
    c.drawRRect(
      rr.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, h * 0.08)
        ..shader = sweep,
    );
    // partikel mengorbit di sepanjang tepi
    final orbit = Path()..addRRect(rr.inflate(h * 0.06));
    for (final m in orbit.computeMetrics()) {
      for (var i = 0; i < 3; i++) {
        final pos = m.getTangentForOffset(((t + i / 3) % 1) * m.length)?.position;
        if (pos == null) continue;
        c.drawCircle(
          pos,
          h * 0.1,
          Paint()
            ..color = Colors.white
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.08),
        );
      }
    }
  }

  // ------------------------------------------------------------- 5 crystal
  void _crystalPrism(Canvas c, Size s) {
    final h = s.height, w = s.width, tip = h * 0.5;
    final p = _hexPath(s, tip);
    final r = Offset.zero & s;

    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF7DD3FC).withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.18),
    );

    c.save();
    c.clipPath(p);
    c.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE0F7FF), Color(0xFF9ADCFF), Color(0xFF5AA8FF), Color(0xFFC9F0FF)],
        ).createShader(r),
    );
    c.drawRect(
      Rect.fromLTWH(0, 0, w, h / 2),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    final facet = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.5);
    c.drawPath(
      Path()
        ..moveTo(tip, 0)
        ..lineTo(tip * 1.7, h / 2)
        ..lineTo(tip, h)
        ..moveTo(w - tip, 0)
        ..lineTo(w - tip * 1.7, h / 2)
        ..lineTo(w - tip, h),
      facet,
    );
    // sapuan prisma (pelangi tipis)
    final x = -h * 1.5 + t * (w + h * 3);
    final band = Rect.fromLTWH(x, 0, h * 1.4, h);
    c.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(colors: [
          Color(0x00FFFFFF),
          Color(0x88FF7AD9),
          Color(0x88FFF27A),
          Color(0x887AFFF4),
          Color(0x00FFFFFF),
        ]).createShader(band),
    );
    c.restore();

    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.95),
    );

    const spots = [(0.16, 0.22, 0.0), (0.58, 0.82, 0.35), (0.86, 0.24, 0.68)];
    for (final (fx, fy, ph) in spots) {
      final k = math.max(0.0, math.sin((t + ph) * _tau));
      if (k <= 0.01) continue;
      _sparkle(c, Offset(w * fx, h * fy), h * 0.24 * k);
    }
  }

  // ------------------------------------------------------------ 6 makimono
  void _makimono(Canvas c, Size s) {
    final h = s.height, w = s.width;
    final rodW = h * 0.34;
    final cx = w / 2;
    final half = (w / 2 - rodW) * reveal;
    final top = h * 0.13, bot = h * 0.87;
    final paper = Rect.fromLTRB(cx - half, top, cx + half, bot);

    if (half > 0.5) {
      c.drawRect(
        paper,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFBF1D9), Color(0xFFEAD3A6), Color(0xFFF6E7C4)],
          ).createShader(paper),
      );
      final ink = Paint()
        ..color = const Color(0xFF9E2A2B)
        ..strokeWidth = math.max(0.8, h * 0.05);
      c.drawLine(Offset(paper.left, top + h * 0.08), Offset(paper.right, top + h * 0.08), ink);
      c.drawLine(Offset(paper.left, bot - h * 0.08), Offset(paper.right, bot - h * 0.08), ink);

      c.save();
      c.clipRect(paper);
      final x = -h + t * (w + h * 2);
      final band = Rect.fromLTWH(x, 0, h * 1.6, h);
      c.drawRect(
        band,
        Paint()
          ..shader = const LinearGradient(colors: [
            Color(0x00FFFFFF),
            Color(0x66FFFFFF),
            Color(0x00FFFFFF),
          ]).createShader(band),
      );
      c.restore();
    }

    for (final x in [cx - half - rodW, cx + half]) {
      final rod = Rect.fromLTWH(x, 0, rodW, h);
      c.drawRRect(
        RRect.fromRectAndRadius(rod, Radius.circular(rodW * 0.45)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF3E2210), Color(0xFF9A6634), Color(0xFF3E2210)],
          ).createShader(rod),
      );
      final cap = Paint()..color = const Color(0xFFC9A227);
      c.drawRect(Rect.fromLTWH(x, h * 0.1, rodW, h * 0.07), cap);
      c.drawRect(Rect.fromLTWH(x, h * 0.83, rodW, h * 0.07), cap);
    }
  }

  // --------------------------------------------------------------- 7 ofuda
  void _ofudaSeal(Canvas c, Size s) {
    final h = s.height;
    const red = Color(0xFFC1121F);
    final pulse = 0.5 + 0.5 * math.sin(t * _tau);
    final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(h * 0.08));

    // aura energi berdenyut
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.18
        ..color = const Color(0xFFFF3B3B).withValues(alpha: 0.25 + 0.4 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * (0.12 + 0.18 * pulse)),
    );
    c.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF6E3), Color(0xFFF1DFB8)],
        ).createShader(Offset.zero & s),
    );
    c.drawRRect(
      rr.deflate(h * 0.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, h * 0.05)
        ..color = red,
    );
    c.drawRRect(
      rr.deflate(h * 0.18),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, h * 0.025)
        ..color = red.withValues(alpha: 0.6),
    );

    // segel kiri: lingkaran + cincin tik berputar
    final o = Offset(h * 0.55, h / 2);
    final stamp = Curves.elasticOut.transform(reveal.clamp(0.0, 1.0));
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(0.4 + 0.6 * stamp);
    c.drawCircle(Offset.zero, h * 0.2, Paint()..color = red);
    c.drawCircle(
      Offset.zero,
      h * 0.1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, h * 0.035)
        ..color = const Color(0xFFFFF1D6),
    );
    c.rotate(t * _tau);
    final tick = Paint()
      ..color = red
      ..strokeWidth = math.max(0.8, h * 0.045)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = i * _tau / 8;
      final d = Offset(math.cos(a), math.sin(a));
      c.drawLine(d * (h * 0.27), d * (h * 0.33), tick);
    }
    c.restore();

    c.drawLine(
      Offset(h * 0.98, h * 0.24),
      Offset(h * 0.98, h * 0.76),
      Paint()
        ..color = red.withValues(alpha: 0.45)
        ..strokeWidth = math.max(0.6, h * 0.03),
    );
  }

  // --------------------------------------------------------------- 8 kamon
  void _kamonCrest(Canvas c, Size s) {
    final h = s.height, w = s.width;
    const gold = Color(0xFFD4AF37);

    final ribbon = RRect.fromLTRBAndCorners(
      h * 0.5,
      h * 0.12,
      w,
      h * 0.88,
      topRight: Radius.circular(h * 0.38),
      bottomRight: Radius.circular(h * 0.38),
    );
    c.drawRRect(
      ribbon,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF242B57), Color(0xFF0F1330)],
        ).createShader(ribbon.outerRect),
    );
    c.drawRRect(
      ribbon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = gold.withValues(alpha: 0.85),
    );

    final o = Offset(h / 2, h / 2);
    final rad = h / 2;
    c.drawCircle(o, rad, Paint()..color = const Color(0xFF0F1330));
    c.drawCircle(
      o,
      rad - h * 0.04,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.08
        ..shader = SweepGradient(
          colors: const [gold, Color(0xFFFFF3C4), gold, Color(0xFF8A6A12), gold],
          transform: GradientRotation(t * _tau * 2),
        ).createShader(Rect.fromCircle(center: o, radius: rad)),
    );

    c.save();
    c.translate(o.dx, o.dy);
    // cincin titik (berputar berlawanan)
    c.save();
    c.rotate(-t * _tau);
    for (var i = 0; i < 12; i++) {
      final a = i * _tau / 12;
      c.drawCircle(
        Offset(math.cos(a), math.sin(a)) * (rad * 0.72),
        h * 0.025,
        Paint()..color = gold.withValues(alpha: i.isEven ? 0.95 : 0.4),
      );
    }
    c.restore();
    // bunga 6 kelopak (motif asanoha)
    c.rotate(t * _tau);
    final petal = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFFFFE9A3), gold])
          .createShader(Rect.fromCircle(center: Offset.zero, radius: rad));
    for (var i = 0; i < 6; i++) {
      final a = i * _tau / 6;
      Offset at(double ang, double rad) => Offset(math.cos(ang), math.sin(ang)) * rad;
      c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(at(a - 0.28, rad * 0.3).dx, at(a - 0.28, rad * 0.3).dy)
          ..lineTo(at(a, rad * 0.58).dx, at(a, rad * 0.58).dy)
          ..lineTo(at(a + 0.28, rad * 0.3).dx, at(a + 0.28, rad * 0.3).dy)
          ..close(),
        petal,
      );
    }
    c.drawCircle(Offset.zero, rad * 0.09, Paint()..color = const Color(0xFF0F1330));
    c.restore();
  }

  // --------------------------------------------------------------- 9 kunai
  void _kunai(Canvas c, Size s) {
    final h = s.height, w = s.width;
    final x0 = h * 1.05;
    const steel = Color(0xFFB8C1CC);

    c.drawCircle(
      Offset(h * 0.27, h / 2),
      h * 0.19,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.08
        ..color = steel,
    );
    final grip = Rect.fromLTRB(h * 0.44, h * 0.33, x0, h * 0.67);
    c.drawRect(grip, Paint()..color = const Color(0xFF2B1A12));
    c.save();
    c.clipRect(grip);
    final wrap = Paint()
      ..color = const Color(0xFF8A2323)
      ..strokeWidth = h * 0.06;
    for (double x = grip.left - h; x < grip.right; x += h * 0.15) {
      c.drawLine(Offset(x, grip.bottom), Offset(x + h * 0.34, grip.top), wrap);
    }
    c.restore();

    final blade = Path()
      ..moveTo(x0, h * 0.2)
      ..lineTo(w - h * 0.7, h * 0.06)
      ..lineTo(w, h * 0.5)
      ..lineTo(w - h * 0.7, h * 0.94)
      ..lineTo(x0, h * 0.8)
      ..close();
    final r = Offset.zero & s;
    c.drawPath(
      blade,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6B7584), Color(0xFF353C47), Color(0xFF1C2027), Color(0xFF465060)],
          stops: [0, 0.45, 0.6, 1],
        ).createShader(r),
    );
    if (t < 0.6) {
      c.save();
      c.clipPath(blade);
      final x = -h + (t / 0.6) * (w + h * 2);
      c.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + h * 0.45, 0)
          ..lineTo(x + h * 0.15, h)
          ..lineTo(x - h * 0.3, h)
          ..close(),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.08),
      );
      c.restore();
    }
    c.drawPath(
      blade,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFFDDE5EE).withValues(alpha: 0.85),
    );
    c.drawRect(
      Rect.fromLTRB(x0 - h * 0.07, h * 0.22, x0 + h * 0.03, h * 0.78),
      Paint()..color = const Color(0xFF8D97A3),
    );
  }

  // ------------------------------------------------------------- helpers

  Path _hexPath(Size s, double tip) => Path()
    ..moveTo(tip, 0)
    ..lineTo(s.width - tip, 0)
    ..lineTo(s.width, s.height / 2)
    ..lineTo(s.width - tip, s.height)
    ..lineTo(tip, s.height)
    ..lineTo(0, s.height / 2)
    ..close();

  /// Cahaya yang berjalan di sepanjang [path], ekor memudar.
  void _comet(Canvas c, Path path, double pos, double frac, Color color, double width) {
    for (final m in path.computeMetrics()) {
      final len = m.length;
      final seg = len * frac;
      final head = pos * len;
      const n = 8;
      for (var i = 0; i < n; i++) {
        final a = head - seg + seg * i / n;
        final b = head - seg + seg * (i + 1) / n;
        _drawSeg(
          c,
          m,
          a,
          b,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width
            ..color = color.withValues(alpha: (i + 1) / n),
        );
      }
      final tip = m.getTangentForOffset(head % len)?.position;
      if (tip != null) {
        c.drawCircle(
          tip,
          width * 1.5,
          Paint()
            ..color = color
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 1.4),
        );
      }
    }
  }

  void _drawSeg(Canvas c, ui.PathMetric m, double a, double b, Paint p) {
    final len = m.length;
    final start = a % len; // % di Dart selalu non-negatif
    final end = start + (b - a);
    if (end <= len) {
      c.drawPath(m.extractPath(start, end), p);
    } else {
      c.drawPath(m.extractPath(start, len), p);
      c.drawPath(m.extractPath(0, end - len), p);
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
    c.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25),
    );
    c.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ClanBadgePainter old) =>
      old.t != t || old.reveal != reveal || old.style != style;
}

/// Geser gradien sebesar [t] x lebar (loop mulus karena TileMode.repeated).
class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(-bounds.width * t, 0, 0);
}

// ================================================================== gallery

/// Layar uji: semua gaya di 3 ukuran (14 / 20 / 32). Bisa dipakai juga
/// sebagai pemilih gaya badge buat leader clan.
class ClanBadgeGallery extends StatelessWidget {
  const ClanBadgeGallery({super.key, this.tag = 'DAY', this.onPick});

  final String tag;
  final ValueChanged<ClanBadgeStyle>? onPick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D14),
      appBar: AppBar(title: const Text('Gaya Badge Clan')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: ClanBadgeStyle.values.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, i) {
          final st = ClanBadgeStyle.values[i];
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
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ClanStyledBadge(text: tag, style: st, height: 14),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        ClanStyledBadge(text: tag, style: st, height: 20),
                        const SizedBox(width: 6),
                        const Text('Ramdan',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ]),
                      ClanStyledBadge(text: tag, style: st, height: 32),
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
