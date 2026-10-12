import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../data/models/tree_models.dart';

part 'tree_decor.dart';

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

// Palet per fase langit: 0 = malam, 1 = senja/fajar, 2 = siang.
const List<List<Color>> _skyColors = [
  [Color(0xFF1A1240), Color(0xFF1B2347), Color(0xFF0E1424)],
  [Color(0xFF2E2A6B), Color(0xFFC2506A), Color(0xFFF4A259)],
  [Color(0xFF3D9BE9), Color(0xFF86CDF6), Color(0xFFD4F0FF)],
];
const List<Color> _backHill = [Color(0xFF15301F), Color(0xFF2A4A33), Color(0xFF4C9A58)];
const List<List<Color>> _frontGround = [
  [Color(0xFF2F7A3E), Color(0xFF173D22)],
  [Color(0xFF3E8A45), Color(0xFF1D4A28)],
  [Color(0xFF62C26A), Color(0xFF2E7D3F)],
];
const List<Color> _grass = [Color(0xFF3F9A50), Color(0xFF57A85E), Color(0xFF8BDB86)];

/// Fase langit dari jam HP (murni kosmetik, tidak memengaruhi buah).
int skyPhaseNow() {
  final h = DateTime.now().hour;
  if (h >= 7 && h <= 16) return 2;
  if (h == 5 || h == 6 || h == 17 || h == 18) return 1;
  return 0;
}

/// Angka pseudo-acak deterministik 0..1 (posisi bintang/daun stabil antar frame).
double _rand(int n) {
  final v = math.sin(n * 12.9898) * 43758.5453;
  return v - v.floorToDouble();
}

double _easeOutBack(double x) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final k = x - 1;
  return 1 + c3 * k * k * k + c1 * k * k;
}

class _Drop {
  _Drop(this.slot, this.start, this.label);
  final int slot;
  final double start;
  final String label;
}

/// State visual pohon: slot buah yang terisi, buah yang sedang jatuh, dan waktu
/// animasi. Angka "benar" tetap dari server; ini cuma tampilan.
class TreeSceneController extends ChangeNotifier {
  double t = 0;
  int level = 1;
  int capacity = 6;
  bool full = false;

  /// Titik tujuan koin terbang (posisi ikon ZCoin di HUD, koordinat scene).
  Offset? coinTarget;

  /// Dekorasi yang dipasang (atau sedang di-preview di toko).
  TreeLook look = const TreeLook();

  /// Tag clan (bendera clan) & username (papan nama).
  String? clanTag;
  String? username;

  void setLook(TreeLook value) {
    look = value;
    notifyListeners();
  }

  final List<bool> occupied = List<bool>.filled(kTreeSlots, false);
  final List<double> spawnAt = List<double>.filled(kTreeSlots, -10);
  final List<_Drop> drops = [];
  double burstAt = -10;
  bool _first = true;

  int get visibleCount => occupied.where((o) => o).length;

  /// Samakan jumlah buah yang tampil dengan [count]. Buah lama tetap di
  /// slotnya; buah baru muncul dengan animasi "pop".
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
    full = target >= this.capacity && this.capacity > 0;
    _first = false;
    notifyListeners();
  }

  /// Petik buah di [slot] (animasi jatuh + koin terbang). false kalau kosong.
  bool pick(int slot, String label, {double delay = 0}) {
    if (slot < 0 || slot >= kTreeSlots || !occupied[slot]) return false;
    occupied[slot] = false;
    full = false;
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
    drops.removeWhere((d) => t - d.start > 2.8);
    notifyListeners();
  }
}

/// Pemandangan pohon layar penuh: langit siang/senja/malam, awan, matahari/
/// bulan, pohon bergoyang, buah berkilau, daun gugur, kupu-kupu/kunang-kunang,
/// buah jatuh lalu berubah jadi koin yang terbang ke HUD.
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
    groundY = h * 0.80;
    base = Offset(w / 2, groundY);
    final grow = 0.86 + 0.14 * ((level - 1).clamp(0, 9) / 9);
    r = math.min(w * 0.40, h * 0.21) * grow;
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

  Offset slotLocal(int i, double t) =>
      canopy + _slotRel[i] * r + Offset(0, math.sin(t * 2.2 + i * 1.3) * r * 0.012);

  Offset fruitPos(int i, double t) => rotate(slotLocal(i, t), angle(t));

  int? hitTest(Offset p, TreeSceneController c) {
    int? best;
    var bestD = fruitR * 2.0;
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
    final phase = skyPhaseNow();
    final look = c.look;
    final skin = _skinFor(look.tree, phase);

    _sky(canvas, size, g, t, phase);
    _fxBack(canvas, size, g, t, phase, look.effect);
    _ground(canvas, size, g, phase);

    // Buah yang sudah "dipetik" tapi belum mulai jatuh (panen semua berurutan)
    // tetap digambar di pohon.
    final waiting = <int>{
      for (final d in c.drops)
        if (t < d.start) d.slot,
    };

    canvas.save();
    canvas.translate(g.base.dx, g.base.dy);
    canvas.rotate(g.angle(t));
    canvas.translate(-g.base.dx, -g.base.dy);
    if (c.full) _fullHalo(canvas, g, t);
    if (look.treeDeco == 'deco_swing') _decoSwing(canvas, g, t);
    _trunk(canvas, g);
    _canopy(canvas, g, t, skin);
    _skinExtras(canvas, g, t, look.tree);
    if (look.treeDeco != 'deco_swing') _treeDeco(canvas, g, t, phase, look.treeDeco, c.clanTag);
    _treePet(canvas, g, t, phase, look.pet);
    for (var i = 0; i < kTreeSlots; i++) {
      if (!c.occupied[i] && !waiting.contains(i)) continue;
      final x = ((t - c.spawnAt[i]) / 0.45).clamp(0.0, 1.0);
      if (x <= 0) continue;
      final s = _easeOutBack(x) * (1 + math.sin(t * 3 + i) * 0.03);
      final p = g.slotLocal(i, t);
      _fruitAt(canvas, p, g.fruitR, s, 1, math.sin(t * 1.7 + i) * 0.12);
      _twinkle(canvas, p, g.fruitR, t, i);
    }
    canvas.restore();

    final u = g.r / 100;
    for (var i = 0; i < look.ground.length && i < 2; i++) {
      final x = size.width * (i == 0 ? 0.17 : 0.83);
      _groundDeco(canvas, Offset(x, g.groundY + size.height * 0.012), u, t, phase, look.ground[i], c.username);
    }
    _groundPet(canvas, g, t, phase, look.pet);

    _drops(canvas, size, g, t);
    _burst(canvas, g, t);
    _leaves(canvas, g, t, skin.leaf);
    final replaced = _fxFront(canvas, size, g, t, phase, look.effect, look.tree);
    if (!replaced) {
      if (phase == 2) {
        _butterflies(canvas, g, t);
      } else {
        _fireflies(canvas, size, g, t, phase == 0 ? 7 : 3);
      }
    }
  }

  // ================================================================ langit

  void _sky(Canvas canvas, Size size, _TreeGeo g, double t, int phase) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _skyColors[phase],
        ).createShader(rect),
    );

    final w = size.width;
    final h = size.height;

    if (phase == 0) {
      for (var i = 0; i < 46; i++) {
        final x = _rand(i * 2) * w;
        final y = _rand(i * 2 + 1) * h * 0.6;
        final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * (1 + _rand(i + 99) * 2) + i));
        canvas.drawCircle(
          Offset(x, y),
          0.6 + _rand(i + 50) * 1.2,
          Paint()..color = Color.fromRGBO(255, 255, 255, 0.8 * tw),
        );
      }
      // bintang jatuh sesekali
      final sp = (t * 0.08) % 1.0;
      if (sp < 0.06) {
        final k = sp / 0.06;
        final start = Offset(w * 0.15, h * 0.08);
        final end = Offset(w * 0.55, h * 0.24);
        final head = Offset.lerp(start, end, k)!;
        final tail = Offset.lerp(start, end, math.max(0, k - 0.25))!;
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(
              colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, 0.9 * (1 - k))],
            ).createShader(Rect.fromPoints(tail, head)),
        );
      }
      final moon = Offset(w * 0.80, h * 0.24);
      canvas.drawCircle(
        moon,
        44,
        Paint()
          ..color = const Color(0x26FFE9B0)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
      canvas.drawCircle(moon, 19, Paint()..color = const Color(0xFFFFF1C9));
      final crater = Paint()..color = const Color(0x1A000000);
      canvas.drawCircle(moon + const Offset(-5, -4), 4, crater);
      canvas.drawCircle(moon + const Offset(6, 5), 3, crater);
    } else {
      final golden = phase == 1;
      final sun = golden ? Offset(w * 0.78, g.groundY - h * 0.13) : Offset(w * 0.80, h * 0.24);
      final core = golden ? const Color(0xFFFFB347) : const Color(0xFFFFE066);
      canvas.drawCircle(
        sun,
        golden ? 90 : 70,
        Paint()
          ..color = core.withValues(alpha: golden ? 0.35 : 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
      );
      if (!golden) {
        final ray = Paint()
          ..color = const Color(0x55FFF3B0)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 12; i++) {
          final a = t * 0.25 + i * math.pi / 6;
          final dir = Offset(math.cos(a), math.sin(a));
          final len = 40 + math.sin(t * 2 + i) * 4;
          canvas.drawLine(sun + dir * 32, sun + dir * len, ray);
        }
      }
      canvas.drawCircle(sun, golden ? 30 : 24, Paint()..color = core);
      canvas.drawCircle(
        sun + const Offset(-6, -6),
        golden ? 12 : 9,
        Paint()..color = const Color(0x55FFFFFF),
      );
    }

    // awan
    final cloudColor = switch (phase) {
      0 => const Color(0x1AC8D0FF),
      1 => const Color(0x99FFD6E0),
      _ => const Color(0xE6FFFFFF),
    };
    final cp = Paint()..color = cloudColor;
    for (var i = 0; i < 4; i++) {
      final span = w + 240;
      final x = ((t * (8 + _rand(i + 10) * 10) + _rand(i + 20) * span) % span) - 120;
      final y = h * (0.10 + 0.22 * _rand(i + 30));
      final s = 0.7 + _rand(i + 40) * 0.6;
      _cloud(canvas, Offset(x, y), s, cp);
    }
  }

  void _cloud(Canvas canvas, Offset p, double s, Paint paint) {
    canvas.drawCircle(p, 22 * s, paint);
    canvas.drawCircle(p + Offset(24 * s, -8 * s), 28 * s, paint);
    canvas.drawCircle(p + Offset(52 * s, 0), 20 * s, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(p.dx - 8 * s, p.dy, 72 * s, 20 * s),
        Radius.circular(10 * s),
      ),
      paint,
    );
  }

  void _ground(Canvas canvas, Size size, _TreeGeo g, int phase) {
    final w = size.width;
    final h = size.height;
    final gy = g.groundY;

    final back = Path()
      ..moveTo(0, gy - h * 0.05)
      ..quadraticBezierTo(w * 0.25, gy - h * 0.13, w * 0.55, gy - h * 0.06)
      ..quadraticBezierTo(w * 0.8, gy - h * 0.01, w, gy - h * 0.08)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = _backHill[phase]);

    final frontRect = Rect.fromLTWH(0, gy - h * 0.04, w, h - gy + h * 0.04);
    final front = Path()
      ..moveTo(0, gy + h * 0.015)
      ..quadraticBezierTo(w * 0.5, gy - h * 0.04, w, gy + h * 0.015)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _frontGround[phase],
        ).createShader(frontRect),
    );

    final grass = Paint()
      ..color = _grass[phase]
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 26; i++) {
      final x = _rand(i + 700) * w;
      final y = gy + h * 0.02 + _rand(i + 800) * (h - gy) * 0.8;
      canvas.drawLine(Offset(x, y), Offset(x - 2, y - 7), grass);
      canvas.drawLine(Offset(x, y), Offset(x + 2.5, y - 8), grass);
    }

    // bunga kecil
    for (var i = 0; i < 8; i++) {
      final x = _rand(i + 1100) * w;
      final y = gy + h * 0.03 + _rand(i + 1200) * (h - gy) * 0.5;
      final col = i.isEven ? const Color(0xFFFFE066) : const Color(0xFFFF8FB1);
      final fp = Paint()..color = col.withValues(alpha: phase == 0 ? 0.5 : 0.9);
      for (var k = 0; k < 4; k++) {
        final a = k * math.pi / 2;
        canvas.drawCircle(Offset(x, y) + Offset(math.cos(a), math.sin(a)) * 2.6, 2.2, fp);
      }
      canvas.drawCircle(Offset(x, y), 1.6, Paint()..color = const Color(0xFFFFFFFF));
    }

    canvas.drawOval(
      Rect.fromCenter(center: g.base + const Offset(0, 2), width: g.r * 1.8, height: g.r * 0.24),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  // ================================================================ pohon

  void _fullHalo(Canvas canvas, _TreeGeo g, double t) {
    final a = 0.16 + 0.08 * math.sin(t * 3);
    canvas.drawCircle(
      g.canopy,
      g.r * 1.35,
      Paint()
        ..color = Color.fromRGBO(255, 197, 61, a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );
  }

  void _trunk(Canvas canvas, _TreeGeo g) {
    final b = g.base;
    final topY = g.canopy.dy + g.r * 0.25;
    final tw = g.r * 0.17;
    final trunk = Path()
      ..moveTo(b.dx - tw * 1.3, b.dy + 4)
      ..quadraticBezierTo(b.dx - tw * 0.7, (b.dy + topY) / 2, b.dx - tw * 0.55, topY)
      ..lineTo(b.dx + tw * 0.55, topY)
      ..quadraticBezierTo(b.dx + tw * 0.7, (b.dy + topY) / 2, b.dx + tw * 1.3, b.dy + 4)
      ..close();
    canvas.drawPath(
      trunk,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF4A2E17), Color(0xFF7A4E2A), Color(0xFF4A2E17)],
        ).createShader(Rect.fromLTRB(b.dx - tw * 1.3, topY, b.dx + tw * 1.3, b.dy)),
    );
    // serat kayu
    final grain = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(b.dx - tw * 0.2, b.dy - 6), Offset(b.dx - tw * 0.1, topY + 20), grain);
    canvas.drawLine(Offset(b.dx + tw * 0.35, b.dy - 12), Offset(b.dx + tw * 0.2, topY + 40), grain);
    // akar
    final root = Paint()
      ..color = const Color(0xFF4A2E17)
      ..strokeWidth = tw * 0.35
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(b.dx - tw * 0.9, b.dy - 2), Offset(b.dx - tw * 1.9, b.dy + 6), root);
    canvas.drawLine(Offset(b.dx + tw * 0.9, b.dy - 2), Offset(b.dx + tw * 2.0, b.dy + 5), root);

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

  void _canopy(Canvas canvas, _TreeGeo g, double t, _Skin skin) {
    final shadow = Paint()..color = skin.shadow;
    for (var i = 0; i < _blobs.length; i++) {
      final (dx, dy, rr) = _blobs[i];
      final breathe = 1 + math.sin(t * 1.6 + i) * 0.012;
      canvas.drawCircle(
        g.canopy + Offset(dx * g.r, dy * g.r + g.r * 0.06),
        rr * g.r * breathe,
        shadow,
      );
    }
    final light = skin.light;
    for (var i = 0; i < _blobs.length; i++) {
      final (dx, dy, rr) = _blobs[i];
      final breathe = 1 + math.sin(t * 1.6 + i) * 0.012;
      final center = g.canopy + Offset(dx * g.r - g.r * 0.03, dy * g.r - g.r * 0.04);
      final radius = rr * g.r * 0.92 * breathe;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.45),
            radius: 0.95,
            colors: light,
            stops: const [0, 0.6, 1],
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

  // ================================================================ buah & koin

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
    if (_fruitSkin(canvas, rad, c.look.fruit, c.t)) return;
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
    _z(canvas, rad, const Color(0x998A3300));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-rad * 0.38, -rad * 0.42), width: rad * 0.5, height: rad * 0.3),
      Paint()..color = const Color(0xAAFFFFFF),
    );
  }

  void _z(Canvas canvas, double rad, Color color) {
    if (_zTp == null || (_zRad - rad).abs() > 0.5) {
      _zRad = rad;
      _zTp = TextPainter(
        text: TextSpan(
          text: 'Z',
          style: TextStyle(color: color, fontSize: rad * 1.15, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final tp = _zTp!;
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  }

  /// Koin emas (digambar pakai skala supaya cache huruf Z tetap kepakai).
  void _coin(Canvas canvas, Offset p, double rad, double scale, double spin) {
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.scale(scale * (0.35 + 0.65 * math.cos(spin).abs()), scale);
    canvas.drawCircle(
      Offset.zero,
      rad * 1.5,
      Paint()
        ..color = const Color(0x44FFD54F)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.7),
    );
    canvas.drawCircle(
      Offset.zero,
      rad,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF1A8), Color(0xFFFFC53D), Color(0xFFD98E04)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rad)),
    );
    canvas.drawCircle(
      Offset.zero,
      rad * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.12
        ..color = const Color(0x66A86A00),
    );
    _z(canvas, rad, const Color(0x998A3300));
    canvas.restore();
  }

  void _twinkle(Canvas canvas, Offset p, double rad, double t, int i) {
    final ph = (t * 0.45 + i * 0.37) % 1.0;
    if (ph > 0.14) return;
    final k = math.sin(ph / 0.14 * math.pi);
    _star(canvas, p + Offset(rad * 0.55, -rad * 0.65), rad * 0.55 * k, Color.fromRGBO(255, 255, 255, k));
  }

  void _star(Canvas canvas, Offset p, double s, Color color) {
    if (s <= 0) return;
    final path = Path()
      ..moveTo(p.dx, p.dy - s)
      ..quadraticBezierTo(p.dx, p.dy, p.dx + s, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + s)
      ..quadraticBezierTo(p.dx, p.dy, p.dx - s, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drops(Canvas canvas, Size size, _TreeGeo g, double t) {
    for (final d in c.drops) {
      final dt = t - d.start;
      if (dt < 0) continue;
      final from = g.fruitPos(d.slot, d.start);
      final floor = g.groundY - g.fruitR * 0.6;
      final gacc = size.height * 2.6;
      final fallH = math.max(0.0, floor - from.dy);
      final tl = math.sqrt(2 * fallH / gacc);
      final drift = (d.slot.isEven ? 1.0 : -1.0) * g.r * 0.12;
      final land = Offset(from.dx + drift, floor);

      // 1) buah jatuh & memantul
      if (dt <= tl) {
        final k = tl == 0 ? 1.0 : dt / tl;
        final pos = Offset(from.dx + drift * k, from.dy + 0.5 * gacc * dt * dt);
        _fruitAt(canvas, pos, g.fruitR, 1, 1, dt * 4);
        continue;
      }
      final lt = dt - tl;
      if (lt < 0.25) {
        final bounce = math.sin(lt / 0.25 * math.pi) * size.height * 0.025;
        final alpha = (1 - lt / 0.25).clamp(0.0, 1.0);
        _fruitAt(canvas, land - Offset(0, bounce), g.fruitR, 1 + lt * 0.8, alpha, dt * 4);
      }

      // 2) cincin + percikan saat mendarat
      if (lt < 0.45) {
        final k = lt / 0.45;
        canvas.drawCircle(
          land,
          g.fruitR * (0.8 + k * 2.4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 * (1 - k)
            ..color = Color.fromRGBO(255, 214, 92, 1 - k),
        );
        final sp = Paint()..color = Color.fromRGBO(255, 214, 92, 1 - k);
        for (var s = 0; s < 8; s++) {
          final a = s * math.pi / 4 + d.slot;
          canvas.drawCircle(
            land + Offset(math.cos(a), math.sin(a) * 0.6) * (k * g.fruitR * 2.6),
            (1 - k) * 2.8,
            sp,
          );
        }
      }

      // 3) label +N
      if (lt < 1.1) {
        final a = (1 - lt / 1.1).clamp(0.0, 1.0);
        _label(canvas, d.label, land - Offset(0, g.fruitR * 1.8 + lt * size.height * 0.08), a, g.fruitR);
      }

      // 4) koin terbang ke HUD
      final target = c.coinTarget;
      if (target != null) {
        final k = ((lt - 0.12) / 0.7).clamp(0.0, 1.0);
        if (k > 0 && k < 1) {
          final e = k * k * (3 - 2 * k);
          final ctrl = Offset((land.dx + target.dx) / 2, math.min(land.dy, target.dy) - size.height * 0.12);
          final u = 1 - e;
          final pos = land * (u * u) + ctrl * (2 * u * e) + target * (e * e);
          _coin(canvas, pos, g.fruitR * 0.85, 1 - e * 0.45, dt * 9);
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
          fontSize: math.max(16.0, fr * 1.6),
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(color: Color.fromRGBO(0, 0, 0, 0.7 * a), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  // ================================================================ efek

  void _burst(Canvas canvas, _TreeGeo g, double t) {
    final bt = t - c.burstAt;
    if (bt < 0 || bt > 1.6) return;
    final k = bt / 1.6;
    for (var ring = 0; ring < 2; ring++) {
      final kk = (k - ring * 0.15).clamp(0.0, 1.0);
      canvas.drawCircle(
        g.canopy,
        g.r * (0.6 + kk * 1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - kk) + 0.5
          ..color = Color.fromRGBO(255, 214, 92, 0.85 * (1 - kk)),
      );
    }
    for (var i = 0; i < 18; i++) {
      final a = i * math.pi * 2 / 18 + k * 0.6;
      final dist = g.r * (0.4 + k * 1.6) * (0.8 + _rand(i + 900) * 0.4);
      _star(
        canvas,
        g.canopy + Offset(math.cos(a), math.sin(a)) * dist,
        6 * (1 - k) + 1,
        Color.fromRGBO(255, 241, 180, 1 - k),
      );
    }
  }

  void _leaves(Canvas canvas, _TreeGeo g, double t, Color leaf) {
    for (var i = 0; i < 8; i++) {
      final speed = 0.06 + _rand(i + 200) * 0.05;
      final prog = (t * speed + _rand(i + 300)) % 1.0;
      final y = g.canopy.dy + prog * (g.groundY - g.canopy.dy + 10);
      final x = g.canopy.dx + (_rand(i + 400) * 2 - 1) * g.r * 1.2 + math.sin(t * 1.3 + i * 2) * g.r * 0.2;
      final a = prog < 0.1 ? prog / 0.1 : (prog > 0.85 ? (1 - prog) / 0.15 : 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(t * 2 + i) * 0.9);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: g.fruitR * 0.9, height: g.fruitR * 0.45),
        Paint()..color = leaf.withValues(alpha: 0.8 * a),
      );
      canvas.restore();
    }
  }

  void _fireflies(Canvas canvas, Size size, _TreeGeo g, double t, int count) {
    for (var i = 0; i < count; i++) {
      final x = size.width * (0.1 + 0.8 * _rand(i + 500)) + math.sin(t * 0.5 + i) * 22;
      final y = g.groundY - size.height * (0.04 + 0.32 * _rand(i + 600)) + math.cos(t * 0.7 + i * 1.7) * 14;
      final a = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 3 + i * 2));
      final p = Offset(x, y);
      canvas.drawCircle(
        p,
        6,
        Paint()
          ..color = Color.fromRGBO(255, 245, 157, 0.35 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(p, 1.8, Paint()..color = Color.fromRGBO(255, 250, 200, a));
    }
  }

  void _butterflies(Canvas canvas, _TreeGeo g, double t) {
    const colors = [Color(0xFFFF8FB1), Color(0xFFFFD54F), Color(0xFF8EC5FF)];
    for (var i = 0; i < 3; i++) {
      final tt = t * (0.35 + i * 0.07) + i * 2.1;
      final p = g.canopy +
          Offset(
            math.sin(tt) * g.r * (1.3 + i * 0.15),
            math.sin(tt * 2.1) * g.r * 0.5 + g.r * (0.4 + i * 0.25),
          );
      final flap = math.sin(t * 14 + i).abs();
      final wing = Paint()..color = colors[i].withValues(alpha: 0.9);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(math.cos(tt) * 0.4);
      for (final side in [-1.0, 1.0]) {
        canvas.save();
        canvas.scale(side * (0.25 + 0.75 * flap), 1);
        canvas.drawOval(const Rect.fromLTWH(0, -6, 7, 6), wing);
        canvas.drawOval(const Rect.fromLTWH(0, 0, 5, 5), wing);
        canvas.restore();
      }
      canvas.drawLine(
        const Offset(0, -5),
        const Offset(0, 5),
        Paint()
          ..color = const Color(0xFF3A2A1A)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TreePainter oldDelegate) => oldDelegate.c != c;
}
