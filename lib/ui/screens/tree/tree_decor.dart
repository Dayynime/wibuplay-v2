part of 'tree_scene.dart';

// Semua dekorasi digambar pakai kode (tanpa aset gambar).
// Satuan `u` = radius kanopi / 100, jadi ukuran ikut besar pohon & layar.

// ==================================================================== util

Path _starPath(Offset c, double outer, double inner, int points) {
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / points;
    final p = c + Offset(math.cos(a), math.sin(a)) * r;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

void _sparkle(Canvas canvas, Offset p, double s, Color color) {
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

void _glow(Canvas canvas, Offset p, double radius, Color color) {
  canvas.drawCircle(
    p,
    radius,
    Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6),
  );
}

void _text(Canvas canvas, String text, Offset center, double size, Color color, {FontWeight w = FontWeight.w900}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: w)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// Seberapa terang efek "menyala" (malam paling terang).
double _nightGlow(int phase) => phase == 0 ? 1.0 : (phase == 1 ? 0.6 : 0.25);

// ==================================================================== skin pohon

class _Skin {
  const _Skin(this.shadow, this.light, this.leaf);
  final Color shadow;
  final List<Color> light;
  final Color leaf;
}

_Skin _skinFor(String? id, int phase) {
  switch (id) {
    case 'tree_sakura': {
      return const _Skin(Color(0xFFB9507A), [Color(0xFFFFD6E7), Color(0xFFF59AC0), Color(0xFFD9628F)], Color(0xFFFFB7D0));
    }
    case 'tree_autumn': {
      return const _Skin(Color(0xFF7A2E0E), [Color(0xFFFFC46B), Color(0xFFF07B2A), Color(0xFFB83A12)], Color(0xFFFF9A3C));
    }
    case 'tree_snow': {
      return const _Skin(Color(0xFF1E4A40), [Color(0xFF6FBFA0), Color(0xFF2F7D63), Color(0xFF1E5A48)], Color(0xFFE8F4FF));
    }
    case 'tree_neon': {
      return const _Skin(Color(0xFF140A33), [Color(0xFF7CF8FF), Color(0xFF8B5CF6), Color(0xFF3B0E6B)], Color(0xFF7CF8FF));
    }
    case 'tree_gold': {
      return const _Skin(Color(0xFF7A5A00), [Color(0xFFFFF4B0), Color(0xFFFFC53D), Color(0xFFB7791F)], Color(0xFFFFD54F));
    }
  }
  return phase == 2
      ? const _Skin(Color(0xFF1A5530), [Color(0xFF6BE38A), Color(0xFF34A853), Color(0xFF237A3D)], Color(0xFF6EDC82))
      : const _Skin(Color(0xFF1A5530), [Color(0xFF4CC870), Color(0xFF2A8A47), Color(0xFF1F6B39)], Color(0xFF6EDC82));
}

/// Kilau animasi di atas kanopi (Pohon Emas).
void _skinExtras(Canvas canvas, _TreeGeo g, double t, String? skin) {
  if (skin != 'tree_gold') return;
  for (var i = 0; i < 11; i++) {
    final ph = (t * 0.6 + i * 0.29) % 1.0;
    if (ph > 0.3) continue;
    final k = math.sin(ph / 0.3 * math.pi);
    final p = g.canopy + Offset((_rand(i + 1300) * 2 - 1) * g.r * 0.85, (_rand(i + 1400) * 2 - 1) * g.r * 0.65);
    _sparkle(canvas, p, g.r * 0.07 * k, Color.fromRGBO(255, 255, 255, k));
  }
}

// ==================================================================== pohon realistis

class _Cluster {
  _Cluster(this.c, this.r);
  final Offset c;
  final double r;
}

/// Bentuk satu helai daun (lonjong runcing), ukuran -1..1.
final Path _kLeaf = Path()
  ..moveTo(0, -1)
  ..quadraticBezierTo(0.62, -0.3, 0, 1)
  ..quadraticBezierTo(-0.62, -0.3, 0, -1)
  ..close();

Color _jitter(Color c, math.Random rnd, double hue, double light) {
  final h = HSLColor.fromColor(c);
  return h
      .withHue((h.hue + (rnd.nextDouble() * 2 - 1) * hue) % 360)
      .withLightness((h.lightness + (rnd.nextDouble() * 2 - 1) * light).clamp(0.0, 1.0))
      .toColor();
}

void _drawLeaves(
  Canvas canvas,
  _Cluster cl,
  math.Random rnd,
  int count,
  double r,
  Color top,
  Color bottom,
  double hueJ, {
  double size = 1,
}) {
  final p = Paint();
  for (var i = 0; i < count; i++) {
    final a = rnd.nextDouble() * math.pi * 2;
    final d = math.sqrt(rnd.nextDouble()) * cl.r;
    final pos = cl.c + Offset(math.cos(a) * d, math.sin(a) * d);
    final ty = ((pos.dy - (cl.c.dy - cl.r)) / (cl.r * 2)).clamp(0.0, 1.0);
    final tx = ((pos.dx - (cl.c.dx - cl.r)) / (cl.r * 2)).clamp(0.0, 1.0);
    p.color = _jitter(Color.lerp(top, bottom, ty * 0.75 + tx * 0.25)!, rnd, hueJ, 0.05);
    final s = r * 0.05 * size * (0.7 + rnd.nextDouble() * 0.6);
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(rnd.nextDouble() * math.pi * 2);
    canvas.scale(s * 0.55, s);
    canvas.drawPath(_kLeaf, p);
    canvas.restore();
  }
}

/// Dahan meruncing dengan sedikit lengkung. [wa]/[wb] = setengah lebar.
void _limb(Canvas canvas, Offset a, Offset b, double wa, double wb, Paint paint, double bend) {
  final dir = b - a;
  final len = dir.distance;
  if (len <= 0) return;
  final n = Offset(-dir.dy / len, dir.dx / len);
  final mid = Offset.lerp(a, b, 0.5)! + n * bend;
  final wm = (wa + wb) / 2;
  final path = Path()
    ..moveTo(a.dx + n.dx * wa, a.dy + n.dy * wa)
    ..quadraticBezierTo(mid.dx + n.dx * wm, mid.dy + n.dy * wm, b.dx + n.dx * wb, b.dy + n.dy * wb)
    ..lineTo(b.dx - n.dx * wb, b.dy - n.dy * wb)
    ..quadraticBezierTo(mid.dx - n.dx * wm, mid.dy - n.dy * wm, a.dx - n.dx * wa, a.dy - n.dy * wa)
    ..close();
  canvas.drawPath(path, paint);
  canvas.drawCircle(b, wb, paint);
}

/// Rekam pohon realistis jadi Picture (skala [dpr]). Return (picture, kotak di layar).
(ui.Picture, Rect) _recordTree(_TreeGeo g, _Skin skin, String? skinId, int phase, double dpr) {
  final r = g.r;
  final base = g.base;
  final bounds = Rect.fromLTRB(g.canopy.dx - r * 1.45, g.canopy.dy - r * 1.25, g.canopy.dx + r * 1.45, base.dy + r * 0.16);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.scale(dpr);
  canvas.translate(-bounds.left, -bounds.top);
  canvas.saveLayer(bounds, Paint());

  final rnd = math.Random(20261013);
  final autumn = skinId == 'tree_autumn';
  final hueJ = autumn ? 24.0 : 7.0;
  final back = skin.shadow;
  final dark = skin.light[2];
  final mid = skin.light[1];
  final hi = skin.light[0];

  // ---------- susunan gerombol daun
  final clusters = <_Cluster>[];
  for (var i = 0; i < 22; i++) {
    final a = i / 22 * math.pi * 2 + (rnd.nextDouble() - 0.5) * 0.25;
    final ry = math.sin(a) > 0 ? 0.6 : 0.8;
    clusters.add(_Cluster(
      g.canopy + Offset(math.cos(a) * r * 0.9, math.sin(a) * r * ry - r * 0.03),
      r * (0.16 + rnd.nextDouble() * 0.1),
    ));
  }
  for (var i = 0; i < 24; i++) {
    final a = rnd.nextDouble() * math.pi * 2;
    final d = math.sqrt(rnd.nextDouble()) * 0.74;
    clusters.add(_Cluster(
      g.canopy + Offset(math.cos(a) * r * d, math.sin(a) * r * d * 0.75 - r * 0.05),
      r * (0.18 + rnd.nextDouble() * 0.12),
    ));
  }

  // ---------- 1) daun lapisan belakang (gelap = kedalaman)
  final backPaint = Paint()..color = back;
  final shift = Offset(r * 0.02, r * 0.05);
  for (final cl in clusters) {
    canvas.drawCircle(cl.c + shift, cl.r * 1.08, backPaint);
  }
  final backLeaf = Color.lerp(back, Colors.black, 0.2)!;
  for (final cl in clusters) {
    _drawLeaves(canvas, _Cluster(cl.c + shift, cl.r * 1.05), rnd, 10, r, back, backLeaf, hueJ);
  }

  // ---------- 2) akar, batang, dahan
  final tw = r * 0.17;
  final top = Offset(base.dx + r * 0.02, g.canopy.dy + r * 0.32);
  final bark = Paint()
    ..shader = ui.Gradient.linear(
      Offset(g.canopy.dx - r, 0),
      Offset(g.canopy.dx + r, 0),
      [const Color(0xFF7A5232), const Color(0xFF543620), const Color(0xFF34200F)],
    );

  for (final (side, len, drop, w) in const [
    (-1.0, 2.5, 0.05, 0.38),
    (1.0, 2.6, 0.04, 0.36),
    (-1.0, 1.7, 0.1, 0.3),
    (1.0, 1.6, 0.09, 0.3),
  ]) {
    _limb(
      canvas,
      Offset(base.dx + side * tw * 0.7, base.dy - 3),
      Offset(base.dx + side * tw * len, base.dy + r * drop),
      tw * w,
      tw * 0.06,
      bark,
      side * r * 0.02,
    );
  }

  final trunk = Path()
    ..moveTo(base.dx - tw * 2.0, base.dy + 6)
    ..quadraticBezierTo(base.dx - tw * 1.05, base.dy - r * 0.04, base.dx - tw * 0.95, base.dy - r * 0.3)
    ..cubicTo(base.dx - tw * 0.85, base.dy - r * 0.75, top.dx - tw * 0.75, top.dy + r * 0.25, top.dx - tw * 0.6, top.dy)
    ..lineTo(top.dx + tw * 0.6, top.dy)
    ..cubicTo(top.dx + tw * 0.75, top.dy + r * 0.25, base.dx + tw * 0.9, base.dy - r * 0.75, base.dx + tw * 1.0, base.dy - r * 0.3)
    ..quadraticBezierTo(base.dx + tw * 1.1, base.dy - r * 0.04, base.dx + tw * 2.1, base.dy + 6)
    ..close();
  canvas.drawPath(
    trunk,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(base.dx - tw * 1.2, 0),
        Offset(base.dx + tw * 1.2, 0),
        [const Color(0xFF8A603A), const Color(0xFF6B4628), const Color(0xFF4A2E18), const Color(0xFF2B190C)],
        const [0.0, 0.35, 0.7, 1.0],
      ),
  );

  // tekstur kulit kayu
  canvas.save();
  canvas.clipPath(trunk);
  final h0 = base.dy + 6;
  final h1 = top.dy;
  for (var i = 0; i < 30; i++) {
    final off = (rnd.nextDouble() * 2 - 1) * tw * 1.15;
    final path = Path();
    var first = true;
    for (var y = h0; y >= h1; y -= 8) {
      final f = ((h0 - y) / (h0 - h1)).clamp(0.0, 1.0);
      final ws = 1 - 0.4 * f;
      final x = base.dx + off * ws + math.sin(y * 0.07 + i) * 1.6 + (top.dx - base.dx) * f;
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 + rnd.nextDouble() * 1.4
        ..color = (i % 4 == 0 ? const Color(0xFFB08458) : const Color(0xFF1E1208))
            .withValues(alpha: i % 4 == 0 ? 0.18 : 0.3 + rnd.nextDouble() * 0.2),
    );
  }
  final knot = Offset(base.dx - tw * 0.3, base.dy - r * 0.55);
  canvas.drawOval(Rect.fromCenter(center: knot, width: tw * 0.4, height: tw * 0.6), Paint()..color = const Color(0xFF2B190C));
  canvas.drawOval(
    Rect.fromCenter(center: knot, width: tw * 0.6, height: tw * 0.85),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x55B08458),
  );
  canvas.restore();

  // dahan bercabang
  void grow(Offset start, double ang, double len, double w, int depth) {
    final end = start + Offset(math.sin(ang), -math.cos(ang)) * len;
    _limb(canvas, start, end, w, w * 0.66, bark, (rnd.nextDouble() - 0.5) * len * 0.3);
    if (depth == 0) {
      final twig = Paint()
        ..color = const Color(0xFF4A2E18)
        ..strokeWidth = math.max(0.8, w * 0.6)
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < 2; k++) {
        final a2 = ang + (k == 0 ? -0.6 : 0.6);
        canvas.drawLine(end, end + Offset(math.sin(a2), -math.cos(a2)) * len * 0.45, twig);
      }
      return;
    }
    final kids = depth >= 2 ? 2 : 3;
    for (var k = 0; k < kids; k++) {
      final spread = (k - (kids - 1) / 2) * (0.5 + rnd.nextDouble() * 0.25) + (rnd.nextDouble() - 0.5) * 0.2;
      grow(end, ang + spread, len * (0.66 + rnd.nextDouble() * 0.14), w * 0.66, depth - 1);
    }
  }

  for (final (ang, len, w, depth) in const [
    (-1.0, 0.42, 0.52, 3),
    (-0.42, 0.5, 0.56, 3),
    (0.12, 0.48, 0.52, 3),
    (0.68, 0.45, 0.5, 3),
    (1.2, 0.4, 0.42, 2),
  ]) {
    grow(top, ang, r * len, tw * w, depth);
  }

  // ---------- 3) daun lapisan depan (bawah dulu, atas terakhir)
  clusters.sort((a, b) => b.c.dy.compareTo(a.c.dy));
  final hiLight = Color.lerp(hi, Colors.white, 0.18)!;
  for (final cl in clusters) {
    // celah: sebagian gerombol bagian dalam dilewati supaya dahan kelihatan
    final inner = (cl.c - g.canopy).distance < r * 0.45;
    if (inner && rnd.nextDouble() < 0.3) continue;
    final rect = Rect.fromCircle(center: cl.c, radius: cl.r * 0.92);
    canvas.drawCircle(
      cl.c,
      cl.r * 0.92,
      Paint()
        ..shader = ui.Gradient.radial(
          cl.c + Offset(-cl.r * 0.35, -cl.r * 0.45),
          cl.r * 1.3,
          [mid, dark],
        ),
    );
    _drawLeaves(canvas, cl, rnd, (cl.r / r * 220).round().clamp(18, 70), r, hi, dark, hueJ);
    _drawLeaves(
      canvas,
      _Cluster(cl.c + Offset(-cl.r * 0.25, -cl.r * 0.35), cl.r * 0.5),
      rnd,
      9,
      r,
      hiLight,
      hi,
      hueJ,
      size: 0.9,
    );
    if (skinId == 'tree_snow' && cl.c.dy < g.canopy.dy + r * 0.15) {
      canvas.drawPath(
        Path()..addArc(rect, math.pi * 1.1, math.pi * 0.8)..close(),
        Paint()..color = const Color(0xF2F4F8FF),
      );
      _drawLeaves(
        canvas,
        _Cluster(cl.c - Offset(0, cl.r * 0.6), cl.r * 0.45),
        rnd,
        8,
        r,
        Colors.white,
        const Color(0xFFDCE8F5),
        0,
        size: 0.8,
      );
    }
    if (skinId == 'tree_neon') {
      canvas.drawCircle(
        cl.c,
        cl.r * 0.95,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = (cl.c.dx < g.canopy.dx ? const Color(0xFF7CF8FF) : const Color(0xFFF472B6)).withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  // ---------- 4) warna cahaya sesuai waktu (bulan / senja)
  final tint = switch (phase) {
    0 => const Color(0x380A1440),
    1 => const Color(0x22FF6A3D),
    _ => null,
  };
  if (tint != null) {
    canvas.drawRect(bounds, Paint()
      ..color = tint
      ..blendMode = BlendMode.srcATop);
  }
  canvas.restore();

  return (rec.endRecording(), bounds);
}

// ==================================================================== skin buah

void _stemLeaf(Canvas canvas, double rad, {Color leaf = const Color(0xFF4ADE80)}) {
  canvas.drawLine(
    Offset(0, -rad * 0.9),
    Offset(rad * 0.15, -rad * 1.35),
    Paint()
      ..color = const Color(0xFF4A2E17)
      ..strokeWidth = rad * 0.18
      ..strokeCap = StrokeCap.round,
  );
  final path = Path()
    ..moveTo(rad * 0.1, -rad * 1.2)
    ..quadraticBezierTo(rad * 0.75, -rad * 1.7, rad * 0.95, -rad * 1.05)
    ..quadraticBezierTo(rad * 0.5, -rad * 0.95, rad * 0.1, -rad * 1.2)
    ..close();
  canvas.drawPath(path, Paint()..color = leaf);
}

void _shine(Canvas canvas, double rad) {
  canvas.drawOval(
    Rect.fromCenter(center: Offset(-rad * 0.38, -rad * 0.42), width: rad * 0.5, height: rad * 0.3),
    Paint()..color = const Color(0xAAFFFFFF),
  );
}

void _roundBody(Canvas canvas, double rad, List<Color> colors) {
  canvas.drawCircle(
    Offset.zero,
    rad,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 0.9,
        colors: colors,
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: rad)),
  );
}

/// Gambar skin buah selain default. Return false kalau [skin] tidak dikenal.
bool _fruitSkin(Canvas canvas, double rad, String? skin, double t) {
  switch (skin) {
    case 'fruit_apple': {
      _glow(canvas, Offset.zero, rad * 1.5, const Color(0x33FF5252));
      _stemLeaf(canvas, rad);
      _roundBody(canvas, rad, const [Color(0xFFFF8A8A), Color(0xFFE53935), Color(0xFF8E1B1B)]);
      _shine(canvas, rad);
      return true;
    }
    case 'fruit_peach': {
      _glow(canvas, Offset.zero, rad * 1.5, const Color(0x33FFA48A));
      _stemLeaf(canvas, rad);
      _roundBody(canvas, rad, const [Color(0xFFFFE6D5), Color(0xFFFFA48A), Color(0xFFE0607A)]);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(rad * 0.5, 0), radius: rad * 0.8),
        math.pi * 0.75,
        math.pi * 0.5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rad * 0.08
          ..color = const Color(0x55B3405A),
      );
      _shine(canvas, rad);
      return true;
    }
    case 'fruit_pumpkin': {
      _glow(canvas, Offset.zero, rad * 1.5, const Color(0x33FF8C1A));
      canvas.drawRect(
        Rect.fromCenter(center: Offset(0, -rad * 0.95), width: rad * 0.22, height: rad * 0.45),
        Paint()..color = const Color(0xFF3F6212),
      );
      for (final dx in [-0.42, 0.42, 0.0]) {
        final rect = Rect.fromCenter(center: Offset(rad * dx, 0), width: rad * 1.15, height: rad * 1.75);
        canvas.drawOval(
          rect,
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFFFFB347), Color(0xFFF97316), Color(0xFFC2410C)],
            ).createShader(rect),
        );
      }
      _shine(canvas, rad);
      return true;
    }
    case 'fruit_star': {
      _glow(canvas, Offset.zero, rad * 1.7, const Color(0x44FFD54F));
      final star = _starPath(Offset.zero, rad * 1.25, rad * 0.55, 5);
      canvas.drawPath(
        star,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF59D), Color(0xFFFFD54F), Color(0xFFF59E0B)],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: rad * 1.25)),
      );
      canvas.drawPath(
        star,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rad * 0.08
          ..color = const Color(0x88B45309),
      );
      return true;
    }
    case 'fruit_candy': {
      canvas.drawLine(
        Offset(0, -rad * 0.9),
        Offset(0, -rad * 1.6),
        Paint()
          ..color = const Color(0xFFF5F5F5)
          ..strokeWidth = rad * 0.16
          ..strokeCap = StrokeCap.round,
      );
      _roundBody(canvas, rad, const [Color(0xFFFFC2DF), Color(0xFFF472B6), Color(0xFFBE185D)]);
      final sw = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.14
        ..color = const Color(0xCCFFFFFF);
      for (var k = 0; k < 3; k++) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: rad * (0.25 + 0.22 * k)),
          k * 1.3 + t * 0.8,
          math.pi * 1.2,
          false,
          sw,
        );
      }
      return true;
    }
    case 'fruit_lantern': {
      _glow(canvas, Offset.zero, rad * 1.9, Color.fromRGBO(255, 170, 60, 0.35 + 0.15 * math.sin(t * 3)));
      canvas.drawLine(Offset(0, -rad * 1.05), Offset(0, -rad * 1.5), Paint()..color = const Color(0xFF3A2A1A)..strokeWidth = rad * 0.1);
      final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: rad * 1.7, height: rad * 2.0),
        Radius.circular(rad * 0.85),
      );
      canvas.drawRRect(
        body,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFFD27A), Color(0xFFEF4444), Color(0xFF991B1B)],
            stops: [0, 0.6, 1],
          ).createShader(body.outerRect),
      );
      final rib = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.07
        ..color = const Color(0x66631010);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rad * 0.8, height: rad * 2.0), rib);
      final cap = Paint()..color = const Color(0xFFFBBF24);
      canvas.drawRect(Rect.fromCenter(center: Offset(0, -rad * 0.98), width: rad * 0.9, height: rad * 0.22), cap);
      canvas.drawRect(Rect.fromCenter(center: Offset(0, rad * 0.98), width: rad * 0.9, height: rad * 0.22), cap);
      return true;
    }
    case 'fruit_crystal': {
      _glow(canvas, Offset.zero, rad * 1.8, Color.fromRGBO(103, 232, 249, 0.3 + 0.15 * math.sin(t * 2.5)));
      final gem = Path()
        ..moveTo(0, -rad * 1.3)
        ..lineTo(rad * 0.95, -rad * 0.25)
        ..lineTo(0, rad * 1.25)
        ..lineTo(-rad * 0.95, -rad * 0.25)
        ..close();
      canvas.drawPath(
        gem,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE0FBFF), Color(0xFF22D3EE), Color(0xFF6D28D9)],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: rad * 1.3)),
      );
      final facet = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.06
        ..color = const Color(0x99FFFFFF);
      canvas.drawLine(Offset(-rad * 0.95, -rad * 0.25), Offset(rad * 0.95, -rad * 0.25), facet);
      canvas.drawLine(Offset(0, -rad * 1.3), Offset(0, rad * 1.25), facet);
      final ph = (t * 0.7) % 1.0;
      if (ph < 0.2) {
        final k = math.sin(ph / 0.2 * math.pi);
        _sparkle(canvas, Offset(rad * 0.4, -rad * 0.6), rad * 0.5 * k, Color.fromRGBO(255, 255, 255, k));
      }
      return true;
    }
  }
  return false;
}

// ==================================================================== hiasan pohon

/// Ayunan: digambar SEBELUM kanopi supaya talinya keluar dari bawah daun.
void _decoSwing(Canvas canvas, _TreeGeo g, double t) {
  final anchor = g.canopy + Offset(g.r * 0.5, g.r * 0.62);
  final len = g.r * 0.4;
  canvas.save();
  canvas.translate(anchor.dx, anchor.dy);
  canvas.rotate(math.sin(t * 1.6) * 0.22);
  final rope = Paint()
    ..color = const Color(0xFFD6B37A)
    ..strokeWidth = 2;
  canvas.drawLine(Offset(-g.r * 0.12, 0), Offset(-g.r * 0.12, len), rope);
  canvas.drawLine(Offset(g.r * 0.12, 0), Offset(g.r * 0.12, len), rope);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(-g.r * 0.18, len - 2, g.r * 0.36, g.r * 0.06),
      const Radius.circular(3),
    ),
    Paint()..color = const Color(0xFF8B5A2B),
  );
  canvas.restore();
}

void _treeDeco(Canvas canvas, _TreeGeo g, double t, int phase, String? id, String? clanTag) {
  final glowK = _nightGlow(phase);
  switch (id) {
    case 'deco_lights': {
      const cols = [Color(0xFFFF5A5A), Color(0xFFFFD54F), Color(0xFF4ADE80), Color(0xFF60A5FA), Color(0xFFF472B6)];
      final wire = Paint()
        ..color = const Color(0x88222222)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (var row = 0; row < 2; row++) {
        final y0 = g.canopy.dy + g.r * (row == 0 ? -0.3 : 0.28);
        final half = g.r * (row == 0 ? 0.72 : 0.86);
        const n = 9;
        final pts = <Offset>[];
        for (var i = 0; i <= n; i++) {
          final k = i / n;
          pts.add(Offset(g.canopy.dx + (k * 2 - 1) * half, y0 + math.sin(k * math.pi) * g.r * 0.18));
        }
        canvas.drawPath(Path()..addPolygon(pts, false), wire);
        for (var i = 0; i <= n; i++) {
          final on = math.sin(t * 3 + i * 1.7 + row) > -0.2;
          final col = cols[(i + row) % cols.length];
          if (on) _glow(canvas, pts[i], 7, col.withValues(alpha: 0.45 * glowK + 0.15));
          canvas.drawCircle(pts[i], 2.8, Paint()..color = on ? col : col.withValues(alpha: 0.35));
        }
      }
    }
    case 'deco_lanterns': {
      const spots = [Offset(-0.58, 0.72), Offset(0.02, 0.9), Offset(0.6, 0.7)];
      for (var i = 0; i < spots.length; i++) {
        final top = g.canopy + Offset(spots[i].dx * g.r, (spots[i].dy - 0.28) * g.r);
        canvas.save();
        canvas.translate(top.dx, top.dy);
        canvas.rotate(math.sin(t * 1.5 + i) * 0.08);
        canvas.drawLine(Offset.zero, Offset(0, g.r * 0.2), Paint()..color = const Color(0xFF3A2A1A)..strokeWidth = 1.2);
        final c = Offset(0, g.r * 0.3);
        _glow(canvas, c, g.r * 0.16, Color.fromRGBO(255, 120, 60, 0.35 * glowK + 0.1));
        final rect = Rect.fromCenter(center: c, width: g.r * 0.17, height: g.r * 0.2);
        canvas.drawOval(
          rect,
          Paint()
            ..shader = const RadialGradient(colors: [Color(0xFFFFB37A), Color(0xFFDC2626)]).createShader(rect),
        );
        final gold = Paint()..color = const Color(0xFFFBBF24);
        canvas.drawRect(Rect.fromCenter(center: c - Offset(0, g.r * 0.1), width: g.r * 0.09, height: g.r * 0.025), gold);
        canvas.drawRect(Rect.fromCenter(center: c + Offset(0, g.r * 0.1), width: g.r * 0.09, height: g.r * 0.025), gold);
        canvas.drawLine(c + Offset(0, g.r * 0.11), c + Offset(0, g.r * 0.17), gold..strokeWidth = 1.5);
        canvas.restore();
      }
    }
    case 'deco_treehouse': {
      final c = g.canopy + Offset(-g.r * 0.52, g.r * 0.5);
      final w = g.r * 0.42;
      final h = g.r * 0.28;
      // tangga ke tanah
      final ladder = Paint()
        ..color = const Color(0xFF6B4423)
        ..strokeWidth = 2;
      final lx = c.dx + w * 0.15;
      canvas.drawLine(Offset(lx - 6, c.dy + h * 0.6), Offset(lx - 6, g.groundY), ladder);
      canvas.drawLine(Offset(lx + 6, c.dy + h * 0.6), Offset(lx + 6, g.groundY), ladder);
      for (var y = c.dy + h * 0.8; y < g.groundY; y += 9) {
        canvas.drawLine(Offset(lx - 6, y), Offset(lx + 6, y), ladder);
      }
      // lantai
      canvas.drawRect(Rect.fromCenter(center: c + Offset(0, h * 0.55), width: w * 1.25, height: g.r * 0.05), Paint()..color = const Color(0xFF5C3A1E));
      // badan
      final body = Rect.fromCenter(center: c, width: w, height: h);
      canvas.drawRect(body, Paint()..color = const Color(0xFFA0682F));
      final plank = Paint()
        ..color = const Color(0x33000000)
        ..strokeWidth = 1;
      for (var k = 1; k < 4; k++) {
        final y = body.top + body.height * k / 4;
        canvas.drawLine(Offset(body.left, y), Offset(body.right, y), plank);
      }
      // atap
      canvas.drawPath(
        Path()
          ..moveTo(body.left - w * 0.15, body.top)
          ..lineTo(c.dx, body.top - h * 0.75)
          ..lineTo(body.right + w * 0.15, body.top)
          ..close(),
        Paint()..color = const Color(0xFFB91C1C),
      );
      // jendela
      final win = Rect.fromCenter(center: c + Offset(-w * 0.18, -h * 0.05), width: w * 0.26, height: h * 0.36);
      _glow(canvas, win.center, w * 0.25, Color.fromRGBO(255, 210, 120, 0.5 * glowK));
      canvas.drawRect(win, Paint()..color = Color.lerp(const Color(0xFF3A2A1A), const Color(0xFFFFD27A), glowK)!);
      // pintu
      canvas.drawRect(
        Rect.fromLTWH(c.dx + w * 0.12, body.bottom - h * 0.6, w * 0.22, h * 0.6),
        Paint()..color = const Color(0xFF5C3A1E),
      );
    }
    case 'deco_nest': {
      final c = g.canopy + Offset(g.r * 0.62, g.r * 0.42);
      final w = g.r * 0.34;
      final eggs = Paint()..color = const Color(0xFFBFE3F2);
      for (var k = -1; k <= 1; k++) {
        canvas.drawOval(Rect.fromCenter(center: c + Offset(k * w * 0.2, -w * 0.12), width: w * 0.2, height: w * 0.26), eggs);
      }
      final bowl = Rect.fromCenter(center: c, width: w, height: w * 0.55);
      canvas.drawArc(bowl, 0, math.pi, true, Paint()..color = const Color(0xFF8B5A2B));
      final stick = Paint()
        ..color = const Color(0xFF5C3A1E)
        ..strokeWidth = 1.4;
      for (var k = 0; k < 6; k++) {
        final x = bowl.left + bowl.width * (k + 0.5) / 6;
        canvas.drawLine(Offset(x - 5, c.dy + 2), Offset(x + 6, c.dy + w * 0.2), stick);
      }
    }
    case 'deco_clanflag': {
      final base = g.canopy + Offset(g.r * 0.08, -g.r * 0.85);
      final top = base - Offset(0, g.r * 0.55);
      canvas.drawLine(base, top - const Offset(0, 4), Paint()..color = const Color(0xFFE5E7EB)..strokeWidth = 2.4);
      canvas.drawCircle(top - const Offset(0, 5), 3, Paint()..color = const Color(0xFFFBBF24));
      final fw = g.r * 0.5;
      final fh = g.r * 0.28;
      final path = Path()..moveTo(top.dx, top.dy);
      const steps = 10;
      for (var i = 1; i <= steps; i++) {
        final k = i / steps;
        path.lineTo(top.dx + fw * k, top.dy + math.sin(t * 4 - k * 4) * fh * 0.12 * k);
      }
      for (var i = steps; i >= 0; i--) {
        final k = i / steps;
        path.lineTo(top.dx + fw * k, top.dy + fh + math.sin(t * 4 - k * 4) * fh * 0.12 * k);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFE4344A));
      _text(canvas, (clanTag == null || clanTag.isEmpty) ? '?' : clanTag, top + Offset(fw * 0.5, fh * 0.5), fh * 0.55, Colors.white);
    }
  }
}

// ==================================================================== pet

/// Pet yang nempel di pohon (ikut goyang): kucing & burung.
void _treePet(Canvas canvas, _TreeGeo g, double t, int phase, String? id) {
  switch (id) {
    case 'pet_cat': {
      final c = g.canopy + Offset(-g.r * 0.48, g.r * 0.8);
      final u = g.r / 100;
      final breathe = 1 + math.sin(t * 2) * 0.04;
      const fur = Color(0xFFF4A261);
      final p = Paint()..color = fur;
      // ekor menjuntai
      final tail = Path()
        ..moveTo(c.dx + 14 * u, c.dy)
        ..quadraticBezierTo(c.dx + 20 * u + math.sin(t * 1.5) * 6 * u, c.dy + 18 * u, c.dx + 12 * u + math.sin(t * 1.5) * 9 * u, c.dy + 28 * u);
      canvas.drawPath(
        tail,
        Paint()
          ..color = fur
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5 * u
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawOval(Rect.fromCenter(center: c, width: 32 * u, height: 13 * u * breathe), p);
      final head = c + Offset(-15 * u, -3 * u);
      canvas.drawCircle(head, 7.5 * u, p);
      for (final s in [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(head.dx + s * 6 * u, head.dy - 3 * u)
            ..lineTo(head.dx + s * 5 * u, head.dy - 11 * u)
            ..lineTo(head.dx + s * 1 * u, head.dy - 6 * u)
            ..close(),
          p,
        );
      }
      final eye = Paint()
        ..color = const Color(0xFF3A2A1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawArc(Rect.fromCircle(center: head + Offset(-3 * u, 0), radius: 1.8 * u), 0, math.pi, false, eye);
      canvas.drawArc(Rect.fromCircle(center: head + Offset(2.5 * u, 0), radius: 1.8 * u), 0, math.pi, false, eye);
      // garis loreng
      final stripe = Paint()
        ..color = const Color(0x55A0522D)
        ..strokeWidth = 2 * u;
      for (var k = 0; k < 3; k++) {
        canvas.drawLine(c + Offset((-4 + k * 6) * u, -6 * u), c + Offset((-2 + k * 6) * u, -1 * u), stripe);
      }
      // zzz
      final zp = (t * 0.4) % 1.0;
      _text(canvas, 'z', head + Offset(6 * u + zp * 8 * u, -12 * u - zp * 18 * u), (8 + zp * 6) * u, Color.fromRGBO(255, 255, 255, 1 - zp), w: FontWeight.w700);
    }
    case 'pet_bird': {
      final u = g.r / 100;
      final cycle = t % 3.2;
      final hop = cycle < 0.35 ? math.sin(cycle / 0.35 * math.pi) * 8 * u : 0.0;
      final c = g.canopy + Offset(g.r * 0.3, -g.r * 0.88 - hop);
      final body = Paint()..color = const Color(0xFF3B82F6);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + 8 * u, c.dy)
          ..lineTo(c.dx + 18 * u, c.dy - 4 * u)
          ..lineTo(c.dx + 16 * u, c.dy + 3 * u)
          ..close(),
        body,
      );
      canvas.drawOval(Rect.fromCenter(center: c, width: 20 * u, height: 14 * u), body);
      canvas.drawOval(Rect.fromCenter(center: c + Offset(-1 * u, 3 * u), width: 12 * u, height: 7 * u), Paint()..color = const Color(0xFFBFDBFE));
      final head = c + Offset(-8 * u, -6 * u);
      canvas.drawCircle(head, 6 * u, body);
      canvas.drawPath(
        Path()
          ..moveTo(head.dx - 5 * u, head.dy - 1 * u)
          ..lineTo(head.dx - 11 * u, head.dy + 1 * u)
          ..lineTo(head.dx - 5 * u, head.dy + 2.5 * u)
          ..close(),
        Paint()..color = const Color(0xFFF59E0B),
      );
      final blink = (t % 4.0) < 0.12;
      if (!blink) canvas.drawCircle(head + Offset(-2 * u, -1 * u), 1.4 * u, Paint()..color = Colors.black);
      final flap = math.sin(t * 20).abs() * (cycle < 0.35 ? 1 : 0.15);
      canvas.drawOval(
        Rect.fromCenter(center: c + Offset(3 * u, -3 * u - flap * 4 * u), width: 11 * u, height: 6 * u),
        Paint()..color = const Color(0xFF1D4ED8),
      );
    }
  }
}

/// Pet di tanah (tidak ikut goyang pohon): kitsune & slime.
void _groundPet(Canvas canvas, _TreeGeo g, double t, int phase, String? id) {
  final u = g.r / 100;
  switch (id) {
    case 'pet_kitsune': {
      final c = g.base + Offset(g.r * 0.45, -2);
      // api rubah biru
      for (var k = 0; k < 2; k++) {
        final a = t * 1.2 + k * math.pi;
        final p = c + Offset(math.cos(a) * 26 * u, -40 * u + math.sin(a * 1.3) * 10 * u);
        _glow(canvas, p, 9 * u, Color.fromRGBO(96, 165, 250, 0.35 + 0.35 * _nightGlow(phase)));
        canvas.drawCircle(p, 3 * u, Paint()..color = const Color(0xFFDBEAFE));
      }
      const fur = Color(0xFFF97316);
      final p = Paint()..color = fur;
      // ekor
      final sway = math.sin(t * 1.8) * 6 * u;
      final tail = Path()
        ..moveTo(c.dx + 4 * u, c.dy - 2 * u)
        ..quadraticBezierTo(c.dx + 36 * u + sway, c.dy, c.dx + 26 * u + sway, c.dy - 32 * u)
        ..quadraticBezierTo(c.dx + 14 * u + sway, c.dy - 20 * u, c.dx + 4 * u, c.dy - 16 * u)
        ..close();
      canvas.drawPath(tail, p);
      final tip = Path()
        ..moveTo(c.dx + 20 * u + sway, c.dy - 22 * u)
        ..quadraticBezierTo(c.dx + 32 * u + sway, c.dy - 20 * u, c.dx + 26 * u + sway, c.dy - 32 * u)
        ..quadraticBezierTo(c.dx + 20 * u + sway, c.dy - 30 * u, c.dx + 20 * u + sway, c.dy - 22 * u)
        ..close();
      canvas.drawPath(tip, Paint()..color = const Color(0xFFFFF7ED));
      // badan duduk
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - 12 * u, c.dy)
          ..quadraticBezierTo(c.dx - 14 * u, c.dy - 26 * u, c.dx - 2 * u, c.dy - 30 * u)
          ..quadraticBezierTo(c.dx + 12 * u, c.dy - 26 * u, c.dx + 10 * u, c.dy)
          ..close(),
        p,
      );
      canvas.drawOval(Rect.fromCenter(center: c + Offset(-2 * u, -14 * u), width: 10 * u, height: 16 * u), Paint()..color = const Color(0xFFFFF7ED));
      // kepala
      final head = c + Offset(-2 * u, -36 * u);
      for (final s in [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(head.dx + s * 3 * u, head.dy - 5 * u)
            ..lineTo(head.dx + s * 9 * u, head.dy - 16 * u)
            ..lineTo(head.dx + s * 10 * u, head.dy - 2 * u)
            ..close(),
          p,
        );
      }
      canvas.drawCircle(head, 9 * u, p);
      canvas.drawPath(
        Path()
          ..moveTo(head.dx - 7 * u, head.dy + 1 * u)
          ..quadraticBezierTo(head.dx, head.dy + 12 * u, head.dx + 7 * u, head.dy + 1 * u)
          ..close(),
        Paint()..color = const Color(0xFFFFF7ED),
      );
      canvas.drawCircle(head + Offset(0, 6 * u), 1.6 * u, Paint()..color = Colors.black);
      final eye = Paint()
        ..color = const Color(0xFF3A2A1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawArc(Rect.fromCircle(center: head + Offset(-4 * u, -1 * u), radius: 2 * u), math.pi, math.pi, false, eye);
      canvas.drawArc(Rect.fromCircle(center: head + Offset(4 * u, -1 * u), radius: 2 * u), math.pi, math.pi, false, eye);
    }
    case 'pet_slime': {
      final c0 = g.base + Offset(-g.r * 0.45, -1);
      final cyc = t % 1.6;
      var jump = 0.0;
      var sx = 1.0;
      var sy = 1.0;
      if (cyc < 0.25) {
        final k = cyc / 0.25;
        sx = 1 + 0.18 * math.sin(k * math.pi);
        sy = 1 - 0.18 * math.sin(k * math.pi);
      } else if (cyc < 0.85) {
        final k = (cyc - 0.25) / 0.6;
        jump = math.sin(k * math.pi) * 28 * u;
        sy = 1.08;
        sx = 0.94;
      }
      canvas.drawOval(
        Rect.fromCenter(center: c0, width: 30 * u * (1 - jump / (80 * u)), height: 6 * u),
        Paint()..color = const Color(0x44000000),
      );
      final w = 30 * u * sx;
      final h = 24 * u * sy;
      final bottom = c0 - Offset(0, jump);
      final body = Path()
        ..moveTo(bottom.dx - w / 2, bottom.dy)
        ..quadraticBezierTo(bottom.dx - w / 2, bottom.dy - h, bottom.dx, bottom.dy - h)
        ..quadraticBezierTo(bottom.dx + w / 2, bottom.dy - h, bottom.dx + w / 2, bottom.dy)
        ..close();
      canvas.drawPath(
        body,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFA7F3D0), Color(0xFF34D399), Color(0xFF059669)],
          ).createShader(Rect.fromLTWH(bottom.dx - w / 2, bottom.dy - h, w, h)),
      );
      canvas.drawOval(
        Rect.fromCenter(center: bottom + Offset(-w * 0.2, -h * 0.72), width: w * 0.22, height: h * 0.14),
        Paint()..color = const Color(0xAAFFFFFF),
      );
      final eye = Paint()..color = const Color(0xFF064E3B);
      canvas.drawCircle(bottom + Offset(-w * 0.16, -h * 0.45), 2.2 * u, eye);
      canvas.drawCircle(bottom + Offset(w * 0.16, -h * 0.45), 2.2 * u, eye);
      canvas.drawArc(
        Rect.fromCircle(center: bottom + Offset(0, -h * 0.32), radius: 3 * u),
        0.2,
        math.pi - 0.4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF064E3B),
      );
    }
  }
}

// ==================================================================== hiasan tanah

void _groundDeco(Canvas canvas, Offset base, double u, double t, int phase, String id, String? username) {
  final glowK = _nightGlow(phase);
  switch (id) {
    case 'ground_pond': {
      final c = base - Offset(0, 6 * u);
      final rect = Rect.fromCenter(center: c, width: 84 * u, height: 22 * u);
      final stone = Paint()..color = const Color(0xFF8E9AAF);
      for (var k = 0; k < 14; k++) {
        final a = k * math.pi * 2 / 14;
        canvas.drawCircle(c + Offset(math.cos(a) * 44 * u, math.sin(a) * 12 * u), 4.2 * u, stone);
      }
      canvas.drawOval(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF38BDF8), Color(0xFF0369A1)],
          ).createShader(rect),
      );
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      for (var k = 0; k < 2; k++) {
        final a = t * 0.9 + k * math.pi;
        final p = c + Offset(math.cos(a) * 28 * u, math.sin(a) * 6 * u);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(a + math.pi / 2);
        final fish = Paint()..color = k == 0 ? const Color(0xFFF97316) : const Color(0xFFF8FAFC);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 12 * u, height: 5 * u), fish);
        canvas.drawPath(
          Path()
            ..moveTo(-5 * u, 0)
            ..lineTo(-10 * u, -3 * u)
            ..lineTo(-10 * u, 3 * u)
            ..close(),
          fish,
        );
        if (k == 1) canvas.drawCircle(const Offset(1, -1), 1.8 * u, Paint()..color = const Color(0xFFEF4444));
        canvas.restore();
      }
      canvas.restore();
      canvas.drawCircle(c + Offset(22 * u, -2 * u), 5 * u, Paint()..color = const Color(0xFF22C55E));
      canvas.drawCircle(c + Offset(23 * u, -4 * u), 1.6 * u, Paint()..color = const Color(0xFFF9A8D4));
    }
    case 'ground_torii': {
      final red = Paint()..color = const Color(0xFFDC2626);
      final h = 66 * u;
      canvas.drawRect(Rect.fromLTWH(base.dx - 24 * u, base.dy - h, 6 * u, h), red);
      canvas.drawRect(Rect.fromLTWH(base.dx + 18 * u, base.dy - h, 6 * u, h), red);
      canvas.drawRect(Rect.fromLTWH(base.dx - 30 * u, base.dy - h * 0.72, 60 * u, 5 * u), red);
      canvas.drawRect(Rect.fromLTWH(base.dx - 34 * u, base.dy - h - 4 * u, 68 * u, 7 * u), red);
      canvas.drawPath(
        Path()
          ..moveTo(base.dx - 42 * u, base.dy - h - 12 * u)
          ..quadraticBezierTo(base.dx, base.dy - h - 4 * u, base.dx + 42 * u, base.dy - h - 12 * u)
          ..lineTo(base.dx + 38 * u, base.dy - h - 4 * u)
          ..quadraticBezierTo(base.dx, base.dy - h + 2 * u, base.dx - 38 * u, base.dy - h - 4 * u)
          ..close(),
        Paint()..color = const Color(0xFF1F1F1F),
      );
      canvas.drawRect(Rect.fromLTWH(base.dx - 3 * u, base.dy - h * 0.72 - 12 * u, 6 * u, 12 * u), red);
    }
    case 'ground_stonelantern': {
      final stone = Paint()..color = const Color(0xFF9CA3AF);
      final dark = Paint()..color = const Color(0xFF6B7280);
      canvas.drawRect(Rect.fromCenter(center: base - Offset(0, 3 * u), width: 24 * u, height: 6 * u), dark);
      canvas.drawRect(Rect.fromCenter(center: base - Offset(0, 16 * u), width: 9 * u, height: 22 * u), stone);
      canvas.drawRect(Rect.fromCenter(center: base - Offset(0, 28 * u), width: 22 * u, height: 4 * u), dark);
      final box = Rect.fromCenter(center: base - Offset(0, 37 * u), width: 16 * u, height: 14 * u);
      canvas.drawRect(box, stone);
      _glow(canvas, box.center, 14 * u, Color.fromRGBO(255, 200, 90, 0.55 * glowK));
      canvas.drawRect(Rect.fromCenter(center: box.center, width: 8 * u, height: 8 * u), Paint()..color = Color.lerp(const Color(0xFF374151), const Color(0xFFFFD27A), glowK)!);
      canvas.drawPath(
        Path()
          ..moveTo(base.dx - 18 * u, base.dy - 44 * u)
          ..lineTo(base.dx + 18 * u, base.dy - 44 * u)
          ..lineTo(base.dx + 6 * u, base.dy - 52 * u)
          ..lineTo(base.dx - 6 * u, base.dy - 52 * u)
          ..close(),
        dark,
      );
      canvas.drawCircle(base - Offset(0, 54 * u), 3 * u, stone);
    }
    case 'ground_fence': {
      final wood = Paint()..color = const Color(0xFFB07A44);
      for (var k = 0; k < 5; k++) {
        final x = base.dx - 40 * u + k * 20 * u;
        canvas.drawPath(
          Path()
            ..moveTo(x - 4 * u, base.dy)
            ..lineTo(x - 4 * u, base.dy - 24 * u)
            ..lineTo(x, base.dy - 29 * u)
            ..lineTo(x + 4 * u, base.dy - 24 * u)
            ..lineTo(x + 4 * u, base.dy)
            ..close(),
          wood,
        );
      }
      final rail = Paint()..color = const Color(0xFF8B5A2B);
      canvas.drawRect(Rect.fromLTWH(base.dx - 44 * u, base.dy - 20 * u, 88 * u, 4 * u), rail);
      canvas.drawRect(Rect.fromLTWH(base.dx - 44 * u, base.dy - 9 * u, 88 * u, 4 * u), rail);
    }
    case 'ground_bench': {
      final wood = Paint()..color = const Color(0xFFB07A44);
      final leg = Paint()..color = const Color(0xFF3F3F46);
      canvas.drawRect(Rect.fromLTWH(base.dx - 26 * u, base.dy - 14 * u, 4 * u, 14 * u), leg);
      canvas.drawRect(Rect.fromLTWH(base.dx + 22 * u, base.dy - 14 * u, 4 * u, 14 * u), leg);
      canvas.drawRect(Rect.fromLTWH(base.dx - 30 * u, base.dy - 17 * u, 60 * u, 5 * u), wood);
      canvas.drawRect(Rect.fromLTWH(base.dx - 28 * u, base.dy - 34 * u, 56 * u, 4 * u), wood);
      canvas.drawRect(Rect.fromLTWH(base.dx - 28 * u, base.dy - 27 * u, 56 * u, 4 * u), wood);
      canvas.drawRect(Rect.fromLTWH(base.dx - 25 * u, base.dy - 34 * u, 3 * u, 18 * u), leg);
      canvas.drawRect(Rect.fromLTWH(base.dx + 22 * u, base.dy - 34 * u, 3 * u, 18 * u), leg);
    }
    case 'ground_mushroom': {
      const specs = [(-14.0, 1.0, Color(0xFF22D3EE)), (6.0, 0.75, Color(0xFFC084FC)), (20.0, 0.55, Color(0xFF22D3EE))];
      for (final (dx, s, col) in specs) {
        final b = base + Offset(dx * u, 0);
        canvas.drawRect(Rect.fromCenter(center: b - Offset(0, 7 * u * s), width: 6 * u * s, height: 14 * u * s), Paint()..color = const Color(0xFFF5F5F4));
        final cap = Rect.fromCenter(center: b - Offset(0, 14 * u * s), width: 22 * u * s, height: 16 * u * s);
        _glow(canvas, cap.center, 14 * u * s, col.withValues(alpha: 0.5 * glowK));
        canvas.drawArc(cap, math.pi, math.pi, true, Paint()..color = Color.lerp(const Color(0xFF7C3AED), col, 0.4 + 0.4 * glowK)!);
        final dot = Paint()..color = const Color(0xCCFFFFFF);
        canvas.drawCircle(cap.center + Offset(-4 * u * s, -3 * u * s), 1.6 * u * s, dot);
        canvas.drawCircle(cap.center + Offset(3 * u * s, -5 * u * s), 1.3 * u * s, dot);
      }
    }
    case 'ground_sign': {
      final wood = Paint()..color = const Color(0xFFB07A44);
      canvas.drawRect(Rect.fromLTWH(base.dx - 2.5 * u, base.dy - 34 * u, 5 * u, 34 * u), Paint()..color = const Color(0xFF6B4423));
      final board = RRect.fromRectAndRadius(
        Rect.fromCenter(center: base - Offset(0, 36 * u), width: 64 * u, height: 22 * u),
        Radius.circular(4 * u),
      );
      canvas.drawRRect(board, wood);
      canvas.drawRRect(
        board,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF6B4423),
      );
      var name = (username == null || username.isEmpty) ? 'Pohonku' : username;
      if (name.length > 10) name = '${name.substring(0, 9)}…';
      _text(canvas, name, board.center, 10 * u, const Color(0xFF3A2A1A), w: FontWeight.w800);
    }
    case 'ground_pumpkin': {
      final c = base - Offset(0, 14 * u);
      _glow(canvas, c, 26 * u, Color.fromRGBO(255, 140, 26, 0.35 * glowK + 0.1));
      canvas.drawRect(Rect.fromCenter(center: c - Offset(0, 15 * u), width: 5 * u, height: 8 * u), Paint()..color = const Color(0xFF3F6212));
      for (final dx in [-10.0, 10.0, 0.0]) {
        final rect = Rect.fromCenter(center: c + Offset(dx * u, 0), width: 24 * u, height: 28 * u);
        canvas.drawOval(
          rect,
          Paint()
            ..shader = const LinearGradient(colors: [Color(0xFFFFB347), Color(0xFFF97316), Color(0xFFC2410C)]).createShader(rect),
        );
      }
      final face = Paint()..color = Color.lerp(const Color(0xFF3A1A00), const Color(0xFFFFE066), glowK)!;
      for (final s in [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + s * 9 * u, c.dy - 2 * u)
            ..lineTo(c.dx + s * 3 * u, c.dy - 2 * u)
            ..lineTo(c.dx + s * 6 * u, c.dy - 8 * u)
            ..close(),
          face,
        );
      }
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - 10 * u, c.dy + 4 * u)
          ..lineTo(c.dx - 5 * u, c.dy + 8 * u)
          ..lineTo(c.dx, c.dy + 5 * u)
          ..lineTo(c.dx + 5 * u, c.dy + 8 * u)
          ..lineTo(c.dx + 10 * u, c.dy + 4 * u)
          ..lineTo(c.dx, c.dy + 11 * u)
          ..close(),
        face,
      );
    }
  }
}

// ==================================================================== efek suasana

/// Efek di langit, digambar SEBELUM tanah (Fuji, aurora, kembang api, kelelawar).
void _fxBack(Canvas canvas, Size size, _TreeGeo g, double t, int phase, String? id) {
  final w = size.width;
  final h = size.height;
  switch (id) {
    case 'fx_fuji': {
      _fuji(canvas, size, g, t, phase);
    }
    case 'fx_aurora': {
      if (phase != 0) return;
      _aurora(canvas, size, g, t);
    }
    case 'fx_fireworks': {
      _fireworks(canvas, size, g, t);
    }
    case 'fx_bats': {
      final bat = Paint()..color = phase == 2 ? const Color(0xFF374151) : const Color(0xFF111111);
      for (var i = 0; i < 4; i++) {
        final span = w + 120;
        final x = ((t * (28 + _rand(i + 1500) * 20) + _rand(i + 1600) * span) % span) - 60;
        final y = h * (0.12 + 0.2 * _rand(i + 1700)) + math.sin(t * 2 + i) * 14;
        final flap = math.sin(t * 16 + i);
        canvas.save();
        canvas.translate(x, y);
        canvas.drawOval(const Rect.fromLTWH(-3, -3, 6, 7), bat);
        for (final s in [-1.0, 1.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(0, 0)
              ..quadraticBezierTo(s * 6, -8 * flap, s * 14, -4 * flap)
              ..quadraticBezierTo(s * 9, 0, s * 12, 3)
              ..quadraticBezierTo(s * 6, 1, 0, 2)
              ..close(),
            bat,
          );
        }
        canvas.restore();
      }
    }
  }
}

/// Efek di depan pohon (kelopak, kunang emas, salju). Return true kalau efek
/// ini menggantikan kunang-kunang bawaan.
bool _fxFront(Canvas canvas, Size size, _TreeGeo g, double t, int phase, String? effect, String? skin) {
  final w = size.width;
  final h = size.height;
  if (skin == 'tree_snow') {
    final p = Paint()..color = const Color(0xDDFFFFFF);
    for (var i = 0; i < 40; i++) {
      final prog = (t * (0.04 + _rand(i + 1800) * 0.04) + _rand(i + 1900)) % 1.0;
      final x = _rand(i + 2100) * w + math.sin(t + i) * 12;
      canvas.drawCircle(Offset(x, prog * h), 1.2 + _rand(i + 2200) * 1.8, p);
    }
  }
  switch (effect) {
    case 'fx_petals': {
      for (var i = 0; i < 16; i++) {
        final prog = (t * (0.05 + _rand(i + 2300) * 0.04) + _rand(i + 2400)) % 1.0;
        final x = _rand(i + 2500) * w + math.sin(t * 1.2 + i) * 30;
        canvas.save();
        canvas.translate(x, prog * h);
        canvas.rotate(t * 2 + i);
        canvas.drawOval(
          const Rect.fromLTWH(-4, -2.5, 8, 5),
          Paint()..color = const Color(0xE6F9A8D4),
        );
        canvas.restore();
      }
      return false;
    }
    case 'fx_goldflies': {
      for (var i = 0; i < 12; i++) {
        final x = w * (0.08 + 0.84 * _rand(i + 2600)) + math.sin(t * 0.6 + i) * 26;
        final y = g.groundY - h * (0.05 + 0.45 * _rand(i + 2700)) + math.cos(t * 0.8 + i * 1.7) * 16;
        final a = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 3 + i * 2));
        _glow(canvas, Offset(x, y), 9, Color.fromRGBO(255, 197, 61, 0.45 * a));
        canvas.drawCircle(Offset(x, y), 2.2, Paint()..color = Color.fromRGBO(255, 236, 160, a));
      }
      return true;
    }
  }
  return false;
}


// ==================================================================== Gunung Fuji

void _fuji(Canvas canvas, Size size, _TreeGeo g, double t, int phase) {
  final w = size.width;
  final h = size.height;
  // Puncak di kiri-atas supaya kelihatan di samping & di atas kanopi,
  // tidak ketutup kartu HUD di tengah.
  final cx = w * 0.27;
  final peakY = math.max(g.canopy.dy - g.r * 1.35, h * 0.25);
  final baseY = g.groundY - h * 0.03;
  final top = w * 0.045;

  final (Color hi, Color lo, Color snow, Color snowShade, Color mist) = switch (phase) {
    0 => (const Color(0xFF4A5A8C), const Color(0xFF1B2347), const Color(0xFFDDE6FF), const Color(0xFF8E9CC8), const Color(0xFF6B7BB0)),
    1 => (const Color(0xFF9A6E9E), const Color(0xFF4A3560), const Color(0xFFFFE3D6), const Color(0xFFC79AB6), const Color(0xFFF3B6A8)),
    _ => (const Color(0xFF5E86C2), const Color(0xFFB4CDEB), const Color(0xFFFFFFFF), const Color(0xFFC9D8EE), const Color(0xFFE6F1FF)),
  };

  final mountain = Path()
    ..moveTo(-w * 0.45, baseY)
    ..cubicTo(-w * 0.05, baseY - h * 0.015, cx - w * 0.2, peakY + h * 0.11, cx - top, peakY)
    ..lineTo(cx - top * 0.35, peakY - h * 0.004)
    ..lineTo(cx + top * 0.25, peakY + h * 0.002)
    ..lineTo(cx + top, peakY)
    ..cubicTo(cx + w * 0.2, peakY + h * 0.11, w * 0.85, baseY - h * 0.015, w * 1.25, baseY)
    ..close();

  final bounds = Rect.fromLTRB(-w * 0.5, peakY - 10, w * 1.3, baseY + 2);
  canvas.save();
  canvas.clipPath(mountain);

  // badan gunung
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = ui.Gradient.linear(Offset(0, peakY), Offset(0, baseY), [hi, lo]),
  );

  // tudung salju bergerigi (dipotong rapi oleh bentuk gunung)
  final capH = (baseY - peakY) * 0.30;
  final snowPath = Path()
    ..moveTo(cx - w * 0.6, peakY - 20)
    ..lineTo(cx + w * 0.6, peakY - 20);
  const n = 34;
  for (var i = n; i >= 0; i--) {
    final x = cx + (i / n * 2 - 1) * w * 0.42;
    final long = i % 3 == 0;
    final d = capH * (long ? 0.85 + 0.45 * _rand(i + 3100) : 0.45 + 0.25 * _rand(i + 3200));
    snowPath.lineTo(x, peakY + d);
  }
  snowPath.close();
  canvas.drawPath(
    snowPath,
    Paint()
      ..shader = ui.Gradient.linear(Offset(0, peakY), Offset(0, peakY + capH * 1.3), [snow, snowShade]),
  );

  // alur lembah (garis halus dari puncak ke bawah)
  final ridge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = const Color(0x22000000);
  for (var i = 0; i < 9; i++) {
    final k = (i / 8) * 2 - 1;
    final x0 = cx + k * top * 0.9;
    canvas.drawLine(Offset(x0, peakY + 4), Offset(cx + k * w * 0.32, baseY), ridge);
  }

  // sisi kanan lebih gelap (cahaya dari kiri / bulan)
  canvas.drawRect(
    Rect.fromLTRB(cx, peakY - 10, w * 1.3, baseY + 2),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx, 0),
        Offset(cx + w * 0.5, 0),
        [const Color(0x38000814), const Color(0x14000814)],
      ),
  );
  canvas.restore();

  // garis tepi tipis yang terkena cahaya
  canvas.drawPath(
    mountain,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = snow.withValues(alpha: 0.18),
  );

  // kabut di kaki gunung, pelan bergeser
  for (var k = 0; k < 3; k++) {
    final y = baseY - h * (0.015 + 0.035 * k);
    final dx = math.sin(t * 0.07 + k * 2) * w * 0.06;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.4 + dx, y), width: w * 1.5, height: h * 0.05),
      Paint()
        ..color = mist.withValues(alpha: phase == 2 ? 0.35 : 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }
}

// ==================================================================== Aurora

void _aurora(Canvas canvas, Size size, _TreeGeo g, double t) {
  final w = size.width;
  final h = size.height;

  // cahaya hijau samar yang memantul ke langit
  canvas.drawOval(
    Rect.fromCenter(center: Offset(w * 0.5, h * 0.3), width: w * 1.4, height: h * 0.3),
    Paint()
      ..color = const Color(0x1A34D399)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
  );

  // Tirai cahaya: banyak "sinar" vertikal, tiap sinar gradasi hijau terang di
  // bawah -> toska -> ungu memudar di atas. Digambar di layer blur + plus
  // supaya menyala seperti aurora asli.
  canvas.saveLayer(
    Rect.fromLTWH(0, 0, w, g.groundY),
    Paint()
      ..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 10)
      ..blendMode = BlendMode.plus,
  );
  for (var curtain = 0; curtain < 3; curtain++) {
    final strips = 80;
    final sw = w / strips;
    final baseH = h * (0.33 - curtain * 0.06);
    final tall = h * (0.2 - curtain * 0.035);
    final power = curtain == 0 ? 1.0 : (curtain == 1 ? 0.65 : 0.4);
    for (var i = 0; i <= strips; i++) {
      final k = i / strips;
      final x = i * sw;
      final base = baseH +
          math.sin(k * math.pi * 2.0 + t * 0.22 + curtain * 1.9) * h * 0.055 +
          math.sin(k * math.pi * 7 + t * 0.5 + curtain) * h * 0.01;
      final ray = 0.5 + 0.5 * math.sin(k * 41 + t * 1.3 + curtain * 3);
      final height = tall * (0.45 + 0.55 * ray);
      final wave = 0.5 + 0.5 * math.sin(k * math.pi * 3.5 - t * 0.7 + curtain * 2);
      final bright = (0.25 + 0.75 * wave * wave) * power;
      final top = base - height;
      canvas.drawRect(
        Rect.fromLTRB(x, top, x + sw + 1, base + h * 0.012),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, base + h * 0.012),
            Offset(x, top),
            [
              const Color(0x0078FFAA),
              Color.fromRGBO(110, 255, 170, 0.8 * bright),
              Color.fromRGBO(45, 220, 200, 0.45 * bright),
              Color.fromRGBO(170, 100, 255, 0.18 * bright),
              const Color(0x00AA64FF),
            ],
            const [0.0, 0.06, 0.4, 0.75, 1.0],
          ),
      );
    }
  }
  canvas.restore();
}

// ==================================================================== Kembang api

void _fireworks(Canvas canvas, Size size, _TreeGeo g, double t) {
  final w = size.width;
  final h = size.height;
  const palettes = [
    [Color(0xFFFFE08A), Color(0xFFFF6B3D)],
    [Color(0xFFB4F0FF), Color(0xFF3B82F6)],
    [Color(0xFFFFC2E2), Color(0xFFEC4899)],
    [Color(0xFFD9FFB3), Color(0xFF22C55E)],
    [Color(0xFFFFF4C2), Color(0xFFF59E0B)],
  ];
  for (var k = 0; k < 3; k++) {
    const period = 3.1;
    final tt = t + k * 1.05;
    final cycle = (tt / period).floor();
    final p = tt / period - cycle;
    final seed = cycle * 3 + k;
    final center = Offset(w * (0.12 + 0.76 * _rand(seed + 2000)), h * (0.13 + 0.17 * _rand(seed + 3000)));
    final pal = palettes[seed % palettes.length];
    final start = Offset(center.dx + (_rand(seed + 4000) - 0.5) * w * 0.1, g.groundY);

    if (p < 0.22) {
      // roket naik + percikan ekor
      final q = p / 0.22;
      final e = 1 - (1 - q) * (1 - q);
      final pos = Offset.lerp(start, center, e)!;
      for (var j = 0; j < 6; j++) {
        final back = Offset.lerp(start, center, math.max(0.0, e - j * 0.025))!;
        canvas.drawCircle(
          back + Offset((_rand(j + seed) - 0.5) * 3, 0),
          1.6 - j * 0.2,
          Paint()
            ..color = pal[0].withValues(alpha: 0.7 - j * 0.1)
            ..blendMode = BlendMode.plus,
        );
      }
      canvas.drawCircle(pos, 2.4, Paint()..color = Colors.white);
      continue;
    }

    final q = (p - 0.22) / 0.78;
    // kilatan saat meledak
    if (q < 0.12) {
      canvas.drawCircle(
        center,
        w * 0.09 * (1 - q / 0.12),
        Paint()
          ..color = pal[0].withValues(alpha: 0.5 * (1 - q / 0.12))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }
    final ease = 1 - math.pow(1 - q, 3).toDouble();
    final fade = (1 - q).clamp(0.0, 1.0);
    final glowPaint = Paint()..blendMode = BlendMode.plus;
    for (var ring = 0; ring < 2; ring++) {
      final count = ring == 0 ? 28 : 18;
      final radius = w * (ring == 0 ? 0.17 : 0.1);
      for (var i = 0; i < count; i++) {
        final a = i * math.pi * 2 / count + ring * 0.3 + seed;
        final dir = Offset(math.cos(a), math.sin(a));
        final drop = Offset(0, q * q * h * 0.06);
        final pos = center + dir * (radius * ease) + drop;
        final prevE = 1 - math.pow(1 - math.max(0.0, q - 0.07), 3).toDouble();
        final prev = center + dir * (radius * prevE) + Offset(0, math.max(0.0, q - 0.07) * math.max(0.0, q - 0.07) * h * 0.06);
        final col = Color.lerp(pal[0], pal[1], q)!;
        // jejak
        canvas.drawLine(
          prev,
          pos,
          Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = col.withValues(alpha: 0.55 * fade)
            ..blendMode = BlendMode.plus,
        );
        // kerlip di akhir
        final twinkle = q > 0.6 ? (0.5 + 0.5 * math.sin(t * 30 + i * 7)) : 1.0;
        canvas.drawCircle(pos, 2.0 * fade + 0.4, glowPaint..color = col.withValues(alpha: fade * twinkle));
      }
    }
  }
}
