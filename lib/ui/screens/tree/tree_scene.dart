import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Jumlah slot buah maksimal yang bisa digambar di pohon (kapasitas Lv.10 = 10).
const int kTreeSlots = 12;

/// Posisi slot buah relatif ke pusat kanopi (satuan = radius kanopi).
/// Urutan = urutan buah muncul.
const List<Offset> _slotRel = [
  Offset(-0.50, -0.30),
  Offset(0.48, -0.34),
  Offset(0.02, -0.62),
  Offset(-0.18, 0.06),
  Offset(0.30, 0.12),
  Offset(-0.72, 0.20),
  Offset(0.72, 0.18),
  Offset(-0.38, 0.46),
  Offset(0.12, 0.44),
  Offset(0.52, 0.48),
  Offset(-0.08, -0.26),
  Offset(0.84, -0.12),
];

/// Lingkaran penyusun kanopi: (dx, dy, radius) dalam satuan radius kanopi.
const List<(double, double, double)> _blobs = [
  (0.0, 0.0, 0.78),
  (-0.55, 0.15, 0.58),
  (0.55, 0.14, 0.58),
  (-0.32, -0.42, 0.55),
  (0.34, -0.44, 0.52),
  (0.0, 0.34, 0.60),
  (-0.78, -0.05, 0.40),
  (0.80, -0.08, 0.38),
];

/// Angka pseudo-acak deterministik 0..1 (posisi bintang/daun stabil antar frame).
double _rand(int n) {
  final v = math.sin(n * 12.9898) * 43758.5453;
  return v - v.floorToDouble();
}

class _Drop {
  _Drop(this.slot, this.start, this.label);
  final int slot;
  final double start;
  final String label;
}

/// Menyimpan state visual pohon: slot buah yang terisi, buah yang sedang jatuh,
/// dan waktu animasi. Angka "benar" tetap dari server; ini cuma tampilan.
class TreeSceneController extends ChangeNotifier {
  double t = 0;
  int level = 1;
  int capacity = 6;
  final List<bool> occupied = List<bool>.filled(kTreeSlots, false);
  final List<double> spawnAt = List<double>.filled(kTreeSlots, -10);
  final List<_Drop> drops = [];
  double burstAt = -10;
  bool _first = true;

  int get visibleCount => occupied.where((o) => o).length;

  /// Samakan jumlah buah yang tampil dengan [count]. Buah yang sudah ada tetap
  /// di slotnya; buah baru muncul dengan animasi "pop".
  void sync(int count, int capacity, int level) {
    this.level = level;
    this.capacity = capacity.clamp(0, kTreeSlots);
    final target = count.clamp(0, this.capacity);
    for (var i = this.capacity; i < kTreeSlots; i++) {
      occupied[i] = false;
    }
    var cur = visibleCount;
    var added = 0;
    for (var i = 0; i < this.capacity && cur < target; i++) {
      if (!occupied[i]) {
        occupied[i] = true;
        spawnAt[i] = _first ? -10 : t + added * 0.12;
        cur++;
        added++;
      }
    }
    for (var i = this.capacity - 1; i >= 0 && cur > target; i--) {
      if (occupied[i]) {
        occupied[i] = false;
        cur--;
      }
    }
    _first = false;
    notifyListeners();
  }

  /// Petik buah di [slot] (animasi jatuh + label). false kalau slot kosong.
  bool pick(int slot, String label, {double delay = 0}) {
    if (slot < 0 || slot >= kTreeSlots || !occupied[slot]) return false;
    occupied[slot] = false;
    drops.add(_Drop(slot, t + delay, label));
    notifyListeners();
    return true;
  }

  /// Petik semua buah (maksimal [limit]) berurutan. Return jumlah yang dipetik.
  int pickAll(String label, int limit) {
    var n = 0;
    for (var i = 0; i < kTreeSlots && n < limit; i++) {
      if (occupied[i] && pick(i, label, delay: n * 0.09)) n++;
    }
    return n;
  }

  /// Efek kilau (dipakai saat upgrade).
  void celebrate() {
    burstAt = t;
    notifyListeners();
  }

  void _tick(double now) {
    t = now;
    drops.removeWhere((d) => t - d.start > 2.6);
    notifyListeners();
  }
}

/// Pemandangan pohon yang hidup: pohon bergoyang, buah memantul, daun gugur,
/// kunang-kunang, buah jatuh saat dipanen. Murni Flutter (CustomPainter).
class TreeScene extends StatefulWidget {
  const TreeScene({super.key, required this.controller, required this.onFruitTap});

  final TreeSceneController controller;
  final ValueChanged<int> onFruitTap;

  @override
  State<TreeScene> createState() => _TreeSceneState();
}

class _TreeSceneState extends State<TreeScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _TreePainter _painter;

  @override
  void initState() {
    super.initState();
    _painter = _TreePainter(widget.controller);
    _ticker = createTicker((elapsed) {
      widget.controller._tick(elapsed.inMicroseconds / 1e6);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final c = widget.controller;
            final slot = _TreeGeo(size, c.level).hitTest(d.localPosition, c);
            if (slot != null) widget.onFruitTap(slot);
          },
          child: RepaintBoundary(
            child: CustomPaint(size: size, painter: _painter),
          ),
        );
      },
    );
  }
}

/// Geometri pohon untuk ukuran layar tertentu (dipakai painter & hit test).
class _TreeGeo {
  _TreeGeo(this.size, int level) {
    final w = size.width;
    final h = size.height;
    groundY = h * 0.86;
    base = Offset(w / 2, groundY);
    final grow = 0.86 + 0.14 * ((level - 1).clamp(0, 9) / 9);
    r = math.min(w * 0.34, h * 0.29) * grow;
    canopy = Offset(w / 2, groundY - r * 1.8);
    fruitR = r * 0.12;
  }

  final Size size;
  late final double groundY;
  late final Offset base;
  late final double r;
  late final Offset canopy;
  late final double fruitR;

  double angle(double t) => math.sin(t * 1.15) * 0.022 + math.sin(t * 2.7) * 0.006;

  Offset rotate(Offset p, double a) {
    final d = p - base;
    final c = math.cos(a);
    final s = math.sin(a);
    return base + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// Posisi slot di ruang pohon (sebelum rotasi goyang).
  Offset slotLocal(int i, double t) =>
      canopy + _slotRel[i] * r + Offset(0, math.sin(t * 2.2 + i * 1.3) * r * 0.012);

  /// Posisi slot di layar (setelah rotasi goyang).
  Offset fruitPos(int i, double t) => rotate(slotLocal(i, t), angle(t));

  int? hitTest(Offset p, TreeSceneController c) {
    int? best;
    var bestD = fruitR * 1.9;
    for (var i = 0; i < kTreeSlots; i++) {
      if (!c.occupied[i]) continue;
      final d = (fruitPos(i, c.t) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}

double _easeOutBack(double x) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final k = x - 1;
  return 1 + c3 * k * k * k + c1 * k * k;
}

class _TreePainter extends CustomPainter {
  _TreePainter(this.c) : super(repaint: c);

  final TreeSceneController c;

  TextPainter? _zTp;
  double _zRad = -1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = c.t;
    final g = _TreeGeo(size, c.level);

    _sky(canvas, size, t);
    _ground(canvas, size, g);

    // Slot yang buahnya "sudah dipetik" tapi belum mulai jatuh (panen semua
    // berurutan) tetap digambar di pohon.
    final waiting = <int>{
      for (final d in c.drops)
        if (t < d.start) d.slot,
    };

    canvas.save();
    canvas.translate(g.base.dx, g.base.dy);
    canvas.rotate(g.angle(t));
    canvas.translate(-g.base.dx, -g.base.dy);
    _trunk(canvas, g);
    _canopy(canvas, g, t);
    for (var i = 0; i < kTreeSlots; i++) {
      if (!c.occupied[i] && !waiting.contains(i)) continue;
      final x = ((t - c.spawnAt[i]) / 0.45).clamp(0.0, 1.0);
      if (x <= 0) continue;
      final s = _easeOutBack(x) * (1 + math.sin(t * 3 + i) * 0.03);
      _fruitAt(canvas, g.slotLocal(i, t), g.fruitR, s, 1, math.sin(t * 1.7 + i) * 0.12);
    }
    canvas.restore();

    _drops(canvas, size, g, t);
    _burst(canvas, g, t);
    _leaves(canvas, g, t);
    _fireflies(canvas, size, g, t);
  }

  // ---------------------------------------------------------------- latar

  void _sky(Canvas canvas, Size size, double t) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2B1B54), Color(0xFF1B2347), Color(0xFF0E1424)],
        ).createShader(rect),
    );

    for (var i = 0; i < 34; i++) {
      final x = _rand(i * 2) * size.width;
      final y = _rand(i * 2 + 1) * size.height * 0.55;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * (1 + _rand(i + 99) * 2) + i));
      canvas.drawCircle(
        Offset(x, y),
        0.6 + _rand(i + 50) * 1.1,
        Paint()..color = Color.fromRGBO(255, 255, 255, 0.8 * tw),
      );
    }

    final moon = Offset(size.width * 0.83, size.height * 0.13);
    canvas.drawCircle(
      moon,
      34,
      Paint()
        ..color = const Color(0x22FFE9B0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(moon, 15, Paint()..color = const Color(0xFFFFF1C9));
    final crater = Paint()..color = const Color(0x1A000000);
    canvas.drawCircle(moon + const Offset(-4, -3), 3.2, crater);
    canvas.drawCircle(moon + const Offset(5, 4), 2.4, crater);
  }

  void _ground(Canvas canvas, Size size, _TreeGeo g) {
    final w = size.width;
    final h = size.height;
    final gy = g.groundY;

    final back = Path()
      ..moveTo(0, gy - h * 0.06)
      ..quadraticBezierTo(w * 0.25, gy - h * 0.16, w * 0.55, gy - h * 0.07)
      ..quadraticBezierTo(w * 0.8, gy - h * 0.01, w, gy - h * 0.10)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF15301F));

    final frontRect = Rect.fromLTWH(0, gy - h * 0.05, w, h - gy + h * 0.05);
    final front = Path()
      ..moveTo(0, gy + h * 0.02)
      ..quadraticBezierTo(w * 0.5, gy - h * 0.05, w, gy + h * 0.02)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2F7A3E), Color(0xFF173D22)],
        ).createShader(frontRect),
    );

    // rumput kecil
    final grass = Paint()
      ..color = const Color(0xFF3F9A50)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 16; i++) {
      final x = _rand(i + 700) * w;
      final y = gy + h * 0.03 + _rand(i + 800) * h * 0.08;
      canvas.drawLine(Offset(x, y), Offset(x - 2, y - 6), grass);
      canvas.drawLine(Offset(x, y), Offset(x + 2.5, y - 7), grass);
    }

    // bayangan pohon
    canvas.drawOval(
      Rect.fromCenter(center: g.base + const Offset(0, 2), width: g.r * 1.7, height: g.r * 0.22),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  // ---------------------------------------------------------------- pohon

  void _trunk(Canvas canvas, _TreeGeo g) {
    final b = g.base;
    final topY = g.canopy.dy + g.r * 0.25;
    final tw = g.r * 0.17;
    final trunk = Path()
      ..moveTo(b.dx - tw * 1.25, b.dy + 4)
      ..quadraticBezierTo(b.dx - tw * 0.7, (b.dy + topY) / 2, b.dx - tw * 0.55, topY)
      ..lineTo(b.dx + tw * 0.55, topY)
      ..quadraticBezierTo(b.dx + tw * 0.7, (b.dy + topY) / 2, b.dx + tw * 1.25, b.dy + 4)
      ..close();
    canvas.drawPath(
      trunk,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF4A2E17), Color(0xFF7A4E2A), Color(0xFF4A2E17)],
        ).createShader(Rect.fromLTRB(b.dx - tw * 1.3, topY, b.dx + tw * 1.3, b.dy)),
    );
    final branch = Paint()
      ..color = const Color(0xFF5C3A1E)
      ..strokeWidth = tw * 0.45
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(b.dx, topY + g.r * 0.35),
      Offset(b.dx - g.r * 0.45, g.canopy.dy + g.r * 0.05),
      branch,
    );
    canvas.drawLine(
      Offset(b.dx, topY + g.r * 0.25),
      Offset(b.dx + g.r * 0.42, g.canopy.dy),
      branch,
    );
  }

  void _canopy(Canvas canvas, _TreeGeo g, double t) {
    final shadow = Paint()..color = const Color(0xFF1A5530);
    for (var i = 0; i < _blobs.length; i++) {
      final (dx, dy, rr) = _blobs[i];
      final breathe = 1 + math.sin(t * 1.6 + i) * 0.012;
      canvas.drawCircle(
        g.canopy + Offset(dx * g.r, dy * g.r + g.r * 0.06),
        rr * g.r * breathe,
        shadow,
      );
    }
    for (var i = 0; i < _blobs.length; i++) {
      final (dx, dy, rr) = _blobs[i];
      final breathe = 1 + math.sin(t * 1.6 + i) * 0.012;
      final center = g.canopy + Offset(dx * g.r - g.r * 0.03, dy * g.r - g.r * 0.04);
      final radius = rr * g.r * 0.92 * breathe;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.45),
            radius: 0.95,
            colors: [Color(0xFF4CC870), Color(0xFF2A8A47), Color(0xFF1F6B39)],
            stops: [0, 0.6, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    final hl = Paint()..color = const Color(0x2E9BF5B0);
    for (var i = 0; i < 5; i++) {
      final (dx, dy, rr) = _blobs[i];
      canvas.drawCircle(
        g.canopy + Offset((dx - rr * 0.35) * g.r, (dy - rr * 0.4) * g.r),
        rr * g.r * 0.22,
        hl,
      );
    }
  }

  // ---------------------------------------------------------------- buah

  void _fruitAt(Canvas canvas, Offset p, double rad, double scale, double alpha, double rot) {
    if (scale <= 0 || alpha <= 0) return;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(rot);
    canvas.scale(scale);
    if (alpha < 1) {
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: rad * 3),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
    _fruit(canvas, rad);
    if (alpha < 1) canvas.restore();
    canvas.restore();
  }

  void _fruit(Canvas canvas, double rad) {
    canvas.drawCircle(
      Offset.zero,
      rad * 1.7,
      Paint()
        ..color = const Color(0x33FFC53D)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.8),
    );
    canvas.drawLine(
      Offset(0, -rad * 0.9),
      Offset(rad * 0.15, -rad * 1.35),
      Paint()
        ..color = const Color(0xFF4A2E17)
        ..strokeWidth = rad * 0.18
        ..strokeCap = StrokeCap.round,
    );
    final leaf = Path()
      ..moveTo(rad * 0.1, -rad * 1.2)
      ..quadraticBezierTo(rad * 0.75, -rad * 1.7, rad * 0.95, -rad * 1.05)
      ..quadraticBezierTo(rad * 0.5, -rad * 0.95, rad * 0.1, -rad * 1.2)
      ..close();
    canvas.drawPath(leaf, Paint()..color = const Color(0xFF4ADE80));

    canvas.drawCircle(
      Offset.zero,
      rad,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: [Color(0xFFFFE58A), Color(0xFFF7A614), Color(0xFFC2410C)],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rad)),
    );

    if (_zTp == null || (_zRad - rad).abs() > 0.5) {
      _zRad = rad;
      _zTp = TextPainter(
        text: TextSpan(
          text: 'Z',
          style: TextStyle(
            color: const Color(0x998A3300),
            fontSize: rad * 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final tp = _zTp!;
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));

    canvas.drawOval(
      Rect.fromCenter(center: Offset(-rad * 0.38, -rad * 0.42), width: rad * 0.5, height: rad * 0.3),
      Paint()..color = const Color(0xAAFFFFFF),
    );
  }

  void _drops(Canvas canvas, Size size, _TreeGeo g, double t) {
    for (final d in c.drops) {
      final dt = t - d.start;
      if (dt < 0) continue;
      final from = g.fruitPos(d.slot, d.start);
      final floor = g.groundY - g.fruitR * 0.6;
      final gacc = size.height * 2.4;
      final fallH = math.max(0.0, floor - from.dy);
      final tl = math.sqrt(2 * fallH / gacc);
      final drift = (d.slot.isEven ? 1.0 : -1.0) * g.r * 0.12;

      Offset pos;
      var alpha = 1.0;
      if (dt <= tl) {
        final k = tl == 0 ? 1.0 : dt / tl;
        pos = Offset(from.dx + drift * k, from.dy + 0.5 * gacc * dt * dt);
      } else {
        final b = dt - tl;
        final bounce = b < 0.28 ? math.sin(b / 0.28 * math.pi) * size.height * 0.035 : 0.0;
        pos = Offset(from.dx + drift, floor - bounce);
        alpha = (1 - (b - 0.3) / 0.35).clamp(0.0, 1.0);
      }
      _fruitAt(canvas, pos, g.fruitR, 1, alpha, dt * 4);

      if (dt > tl) {
        final lt = dt - tl;
        final land = Offset(from.dx + drift, floor);
        if (lt < 0.5) {
          final k = lt / 0.5;
          final sp = Paint()..color = Color.fromRGBO(255, 214, 92, 1 - k);
          for (var s = 0; s < 6; s++) {
            final a = s * math.pi / 3 + d.slot;
            canvas.drawCircle(
              land + Offset(math.cos(a), math.sin(a) * 0.6) * (k * g.fruitR * 2.4),
              (1 - k) * 2.6,
              sp,
            );
          }
        }
        if (lt < 1.2) {
          final a = (1 - lt / 1.2).clamp(0.0, 1.0);
          _label(canvas, d.label, land - Offset(0, g.fruitR * 1.6 + lt * size.height * 0.11), a, g.fruitR);
        }
      }
    }
  }

  void _label(Canvas canvas, String text, Offset center, double a, double fr) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Color.fromRGBO(255, 214, 92, a),
          fontSize: math.max(14.0, fr * 1.5),
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Color.fromRGBO(0, 0, 0, 0.6 * a),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  // ---------------------------------------------------------------- efek

  void _burst(Canvas canvas, _TreeGeo g, double t) {
    final bt = t - c.burstAt;
    if (bt < 0 || bt > 1.4) return;
    final k = bt / 1.4;
    canvas.drawCircle(
      g.canopy,
      g.r * (0.6 + k * 1.3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - k) + 0.5
        ..color = Color.fromRGBO(255, 214, 92, 0.8 * (1 - k)),
    );
    final sp = Paint()..color = Color.fromRGBO(255, 241, 180, 1 - k);
    for (var i = 0; i < 14; i++) {
      final a = i * math.pi * 2 / 14;
      final dist = g.r * (0.5 + k * 1.4) * (0.8 + _rand(i + 900) * 0.4);
      canvas.drawCircle(g.canopy + Offset(math.cos(a), math.sin(a)) * dist, 3 * (1 - k) + 0.5, sp);
    }
  }

  void _leaves(Canvas canvas, _TreeGeo g, double t) {
    for (var i = 0; i < 7; i++) {
      final speed = 0.06 + _rand(i + 200) * 0.05;
      final prog = (t * speed + _rand(i + 300)) % 1.0;
      final y = g.canopy.dy + prog * (g.groundY - g.canopy.dy + 10);
      final x = g.canopy.dx + (_rand(i + 400) * 2 - 1) * g.r * 1.1 + math.sin(t * 1.3 + i * 2) * g.r * 0.18;
      final a = prog < 0.1 ? prog / 0.1 : (prog > 0.85 ? (1 - prog) / 0.15 : 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(t * 2 + i) * 0.9);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: g.fruitR * 0.9, height: g.fruitR * 0.45),
        Paint()..color = Color.fromRGBO(110, 220, 130, 0.75 * a),
      );
      canvas.restore();
    }
  }

  void _fireflies(Canvas canvas, Size size, _TreeGeo g, double t) {
    for (var i = 0; i < 6; i++) {
      final x = size.width * (0.1 + 0.8 * _rand(i + 500)) + math.sin(t * 0.5 + i) * 20;
      final y = g.groundY - size.height * (0.05 + 0.3 * _rand(i + 600)) + math.cos(t * 0.7 + i * 1.7) * 12;
      final a = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 3 + i * 2));
      final p = Offset(x, y);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..color = Color.fromRGBO(255, 245, 157, 0.35 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(p, 1.6, Paint()..color = Color.fromRGBO(255, 250, 200, a));
    }
  }

  @override
  bool shouldRepaint(covariant _TreePainter oldDelegate) => oldDelegate.c != c;
}
