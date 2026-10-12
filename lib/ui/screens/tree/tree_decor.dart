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

Offset _blobCenter(_TreeGeo g, int i) {
  final (dx, dy, _) = _blobs[i];
  return g.canopy + Offset(dx * g.r - g.r * 0.03, dy * g.r - g.r * 0.04);
}

double _blobRadius(_TreeGeo g, int i, double t) {
  final (_, _, rr) = _blobs[i];
  return rr * g.r * 0.92 * (1 + math.sin(t * 1.6 + i) * 0.012);
}

/// Hiasan tambahan di atas kanopi sesuai skin (salju, neon, kilau emas).
void _skinExtras(Canvas canvas, _TreeGeo g, double t, String? skin) {
  switch (skin) {
    case 'tree_snow': {
      final p = Paint()..color = const Color(0xF2FFFFFF);
      for (var i = 0; i < _blobs.length; i++) {
        final (_, dy, _) = _blobs[i];
        if (dy > 0.2) continue;
        final rect = Rect.fromCircle(center: _blobCenter(g, i), radius: _blobRadius(g, i, t));
        canvas.drawPath(Path()..addArc(rect, math.pi * 1.1, math.pi * 0.8)..close(), p);
      }
    }
    case 'tree_neon': {
      final pulse = 0.55 + 0.45 * math.sin(t * 2.5);
      for (var i = 0; i < _blobs.length; i++) {
        final col = i.isEven ? Color.fromRGBO(124, 248, 255, 0.6 * pulse) : Color.fromRGBO(244, 114, 182, 0.6 * pulse);
        canvas.drawCircle(
          _blobCenter(g, i),
          _blobRadius(g, i, t),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..color = col
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }
    case 'tree_gold': {
      for (var i = 0; i < 9; i++) {
        final ph = (t * 0.6 + i * 0.29) % 1.0;
        if (ph > 0.3) continue;
        final k = math.sin(ph / 0.3 * math.pi);
        final p = g.canopy + Offset((_rand(i + 1300) * 2 - 1) * g.r * 0.85, (_rand(i + 1400) * 2 - 1) * g.r * 0.7);
        _sparkle(canvas, p, g.r * 0.07 * k, Color.fromRGBO(255, 255, 255, k));
      }
    }
  }
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
  final len = g.r * 0.62;
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
        ..moveTo(c.dx + 6 * u, c.dy - 6 * u)
        ..quadraticBezierTo(c.dx + 30 * u + sway, c.dy - 6 * u, c.dx + 22 * u + sway, c.dy - 30 * u)
        ..quadraticBezierTo(c.dx + 14 * u + sway, c.dy - 16 * u, c.dx + 2 * u, c.dy - 12 * u)
        ..close();
      canvas.drawPath(tail, p);
      canvas.drawCircle(Offset(c.dx + 22 * u + sway, c.dy - 29 * u), 5 * u, Paint()..color = Colors.white);
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
      final mountain = switch (phase) {
        0 => const Color(0xFF2A3157),
        1 => const Color(0xFF6B4A7A),
        _ => const Color(0xFF7FA6D9),
      };
      final peak = Offset(w * 0.32, g.groundY - h * 0.34);
      canvas.drawPath(
        Path()
          ..moveTo(-w * 0.1, g.groundY - h * 0.02)
          ..lineTo(peak.dx - w * 0.06, peak.dy + h * 0.02)
          ..quadraticBezierTo(peak.dx, peak.dy - h * 0.008, peak.dx + w * 0.06, peak.dy + h * 0.02)
          ..lineTo(w * 0.8, g.groundY - h * 0.02)
          ..close(),
        Paint()..color = mountain,
      );
      canvas.drawPath(
        Path()
          ..moveTo(peak.dx - w * 0.06, peak.dy + h * 0.02)
          ..quadraticBezierTo(peak.dx, peak.dy - h * 0.008, peak.dx + w * 0.06, peak.dy + h * 0.02)
          ..lineTo(peak.dx + w * 0.12, peak.dy + h * 0.07)
          ..lineTo(peak.dx + w * 0.07, peak.dy + h * 0.06)
          ..lineTo(peak.dx + w * 0.03, peak.dy + h * 0.085)
          ..lineTo(peak.dx - w * 0.01, peak.dy + h * 0.06)
          ..lineTo(peak.dx - w * 0.05, peak.dy + h * 0.08)
          ..lineTo(peak.dx - w * 0.12, peak.dy + h * 0.07)
          ..close(),
        Paint()..color = const Color(0xF2FFFFFF),
      );
    }
    case 'fx_aurora': {
      if (phase != 0) return;
      const cols = [Color(0xFF34D399), Color(0xFF22D3EE), Color(0xFFA78BFA)];
      for (var k = 0; k < 3; k++) {
        final path = Path();
        for (var i = 0; i <= 24; i++) {
          final x = w * i / 24;
          final y = h * (0.14 + 0.05 * k) + math.sin(i / 24 * math.pi * 3 + t * 0.4 + k) * h * 0.03;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = h * 0.05
            ..color = cols[k].withValues(alpha: 0.16 + 0.06 * math.sin(t + k))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
      }
    }
    case 'fx_fireworks': {
      const cols = [Color(0xFFFF5A5A), Color(0xFFFFD54F), Color(0xFF60A5FA), Color(0xFFF472B6), Color(0xFF4ADE80)];
      for (var k = 0; k < 3; k++) {
        final tt = t + k * 0.9;
        final cycle = (tt / 2.7).floor();
        final p = (tt / 2.7) - cycle;
        final seed = cycle * 3 + k;
        final center = Offset(w * (0.15 + 0.7 * _rand(seed + 2000)), h * (0.12 + 0.18 * _rand(seed + 3000)));
        final col = cols[seed % cols.length];
        if (p < 0.25) {
          final q = p / 0.25;
          final y = g.groundY - (g.groundY - center.dy) * q;
          canvas.drawCircle(Offset(center.dx, y), 2, Paint()..color = col);
        } else {
          final q = (p - 0.25) / 0.75;
          final pa = Paint()..color = col.withValues(alpha: (1 - q).clamp(0.0, 1.0));
          for (var i = 0; i < 18; i++) {
            final a = i * math.pi * 2 / 18;
            final pos = center + Offset(math.cos(a), math.sin(a)) * (q * w * 0.16) + Offset(0, q * q * 30);
            canvas.drawCircle(pos, 2.4 * (1 - q) + 0.6, pa);
          }
        }
      }
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
