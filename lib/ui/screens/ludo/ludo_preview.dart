import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Thumbnail kartu Ludo di Zenime Games: papan mini digambar dengan kode.
class LudoBoardPreview extends StatelessWidget {
  const LudoBoardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: _LudoPainter()),
        ),
      ),
    );
  }
}

class _LudoPainter extends CustomPainter {
  static const _red = Color(0xFFF48B94);
  static const _green = Color(0xFF7ED6AE);
  static const _yellow = Color(0xFFFFD56B);
  static const _blue = Color(0xFF86B5F5);
  static const _cream = Color(0xFFFFFBF2);
  static const _ink = Color(0xFF2B3A55);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = s / 15; // papan 15x15
    final fill = Paint();
    final line = Paint()
      ..color = _ink.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    // Papan.
    final board = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * 0.8));
    canvas.drawRRect(board, fill..color = Colors.white);

    // Kandang di 4 pojok + bidaknya.
    void base(double x, double y, Color color) {
      final r = Rect.fromLTWH(x * c, y * c, 6 * c, 6 * c);
      canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(c * 0.15), Radius.circular(c)), fill..color = color);
      canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(c * 1.1), Radius.circular(c * 0.7)), fill..color = _cream);
      for (final o in const [Offset(2.2, 2.2), Offset(3.8, 2.2), Offset(2.2, 3.8), Offset(3.8, 3.8)]) {
        final center = Offset((x + o.dx) * c, (y + o.dy) * c);
        canvas.drawCircle(center, c * 0.55, fill..color = color);
        canvas.drawCircle(center, c * 0.55, line..color = _ink.withValues(alpha: 0.6));
      }
    }

    base(0, 0, _red);
    base(9, 0, _green);
    base(0, 9, _blue);
    base(9, 9, _yellow);

    // Jalur home berwarna.
    for (var i = 1; i < 6; i++) {
      canvas.drawRect(Rect.fromLTWH(i * c, 7 * c, c, c), fill..color = _red);
      canvas.drawRect(Rect.fromLTWH(7 * c, i * c, c, c), fill..color = _green);
      canvas.drawRect(Rect.fromLTWH((14 - i) * c, 7 * c, c, c), fill..color = _yellow);
      canvas.drawRect(Rect.fromLTWH(7 * c, (14 - i) * c, c, c), fill..color = _blue);
    }

    // Garis petak jalur.
    for (var i = 0; i < 15; i++) {
      for (var j = 6; j < 9; j++) {
        if (i >= 6 && i < 9) continue;
        canvas.drawRect(Rect.fromLTWH(j * c, i * c, c, c), line);
        canvas.drawRect(Rect.fromLTWH(i * c, j * c, c, c), line);
      }
    }

    // Tengah: 4 segitiga.
    final mid = Offset(7.5 * c, 7.5 * c);
    void tri(Offset a, Offset b, Color color) {
      canvas.drawPath(Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(mid.dx, mid.dy)..close(), fill..color = color);
    }

    tri(Offset(6 * c, 6 * c), Offset(6 * c, 9 * c), _red);
    tri(Offset(6 * c, 6 * c), Offset(9 * c, 6 * c), _green);
    tri(Offset(9 * c, 6 * c), Offset(9 * c, 9 * c), _yellow);
    tri(Offset(6 * c, 9 * c), Offset(9 * c, 9 * c), _blue);

    canvas.drawRRect(
      board,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * 0.25,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thumbnail Ular Tangga: papan warna-warni dengan tangga & ular.
class UlarBoardPreview extends StatelessWidget {
  const UlarBoardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: _UlarPainter())),
      ),
    );
  }
}

class _UlarPainter extends CustomPainter {
  static const _tiles = [Color(0xFFFFE9A8), Color(0xFFC9F2DC), Color(0xFFFFD6DD), Color(0xFFD6E6FF), Color(0xFFEADCFF)];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width, c = s / 6;
    final fill = Paint();
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * .5)), fill..color = Colors.white);
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 6; x++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x * c + 1.5, y * c + 1.5, c - 3, c - 3), Radius.circular(c * .22)),
          fill..color = _tiles[(x + y) % _tiles.length],
        );
      }
    }
    // Tangga.
    final wood = Paint()
      ..color = const Color(0xFFC98A4B)
      ..strokeWidth = c * .13
      ..strokeCap = StrokeCap.round;
    final a = Offset(c * 1.2, c * 5.3), b = Offset(c * 2.6, c * 1.2);
    final d = b - a, n = Offset(-d.dy, d.dx) / d.distance * (c * .28);
    canvas.drawLine(a + n, b + n, wood);
    canvas.drawLine(a - n, b - n, wood);
    for (var i = 1; i < 6; i++) {
      final p = a + d * (i / 6);
      canvas.drawLine(p + n, p - n, wood);
    }
    // Ular.
    final body = Path()
      ..moveTo(c * 4.8, c * .9)
      ..cubicTo(c * 3.4, c * 2.2, c * 5.6, c * 3.4, c * 4.0, c * 5.2);
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF2F9A58)
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * .5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF3FBF6F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * .36
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(c * 4.8, c * .9), c * .38, fill..color = const Color(0xFF3FBF6F));
    for (final dx in [-.14, .14]) {
      canvas.drawCircle(Offset(c * (4.8 + dx), c * .82), c * .1, fill..color = Colors.white);
      canvas.drawCircle(Offset(c * (4.8 + dx), c * .84), c * .05, fill..color = const Color(0xFF2B3A55));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thumbnail Duel: separuh Tic-Tac-Toe, separuh Connect 4.
class DuelPreview extends StatelessWidget {
  const DuelPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: _DuelPainter())),
      ),
    );
  }
}

class _DuelPainter extends CustomPainter {
  static const _red = Color(0xFFFF5C76), _blue = Color(0xFF4D9DFF);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final fill = Paint();
    // Connect 4 di belakang.
    final board = RRect.fromRectAndRadius(Rect.fromLTWH(s * .3, s * .3, s * .7, s * .7), Radius.circular(s * .08));
    canvas.drawRRect(board, fill..color = const Color(0xFF4D7CF0));
    final r = s * .045, step = s * .7 / 5;
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 5; x++) {
        final col = y == 4 && x < 3 ? (x.isEven ? _red : _blue) : (y == 3 && x == 1 ? _red : Colors.white);
        canvas.drawCircle(Offset(s * .3 + step * (x + .5), s * .3 + step * (y + .5)), r, fill..color = col);
      }
    }
    // Tic-Tac-Toe di depan.
    final card = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s * .6, s * .6), Radius.circular(s * .08));
    canvas.drawRRect(card, fill..color = Colors.white);
    final line = Paint()
      ..color = const Color(0xFFD5E2F0)
      ..strokeWidth = s * .02;
    for (final t in [s * .2, s * .4]) {
      canvas.drawLine(Offset(t, s * .05), Offset(t, s * .55), line);
      canvas.drawLine(Offset(s * .05, t), Offset(s * .55, t), line);
    }
    final pen = Paint()
      ..strokeWidth = s * .035
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void x(double cx, double cy) {
      pen.color = _red;
      canvas.drawLine(Offset(cx - s * .05, cy - s * .05), Offset(cx + s * .05, cy + s * .05), pen);
      canvas.drawLine(Offset(cx + s * .05, cy - s * .05), Offset(cx - s * .05, cy + s * .05), pen);
    }

    x(s * .1, s * .1);
    x(s * .5, s * .5);
    canvas.drawCircle(Offset(s * .3, s * .3), s * .055, pen..color = _blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thumbnail Block!: papan gelap dengan balok warna-warni.
class BlockPreview extends StatelessWidget {
  const BlockPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: _BlockPainter())),
      ),
    );
  }
}

class _BlockPainter extends CustomPainter {
  static const _cells = <int, Color>{
    40: Color(0xFFFF6B81), 41: Color(0xFFFF6B81), 48: Color(0xFFFF6B81),
    42: Color(0xFFFFC53D), 50: Color(0xFFFFC53D), 51: Color(0xFFFFC53D),
    56: Color(0xFF4D9DFF), 57: Color(0xFF4D9DFF), 58: Color(0xFF4D9DFF), 59: Color(0xFF4D9DFF),
    44: Color(0xFF2FD59A), 52: Color(0xFF2FD59A), 60: Color(0xFF2FD59A), 61: Color(0xFF2FD59A),
    46: Color(0xFFA77BFF), 47: Color(0xFFA77BFF), 54: Color(0xFFA77BFF), 55: Color(0xFFA77BFF), 63: Color(0xFFA77BFF),
    20: Color(0xFFFF9A4D), 21: Color(0xFFFF9A4D), 29: Color(0xFFFF9A4D),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width, c = s / 8;
    final fill = Paint();
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * .6)), fill..color = const Color(0xFF1D2B4D));
    for (var i = 0; i < 64; i++) {
      final r = Rect.fromLTWH((i % 8) * c + 1.5, (i ~/ 8) * c + 1.5, c - 3, c - 3);
      final col = _cells[i];
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(c * .2)), fill..color = col ?? const Color(0xFF2F4372));
      if (col != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(r.left + c * .15, r.top + c * .12, c * .35, c * .12), Radius.circular(c * .06)),
          fill..color = Colors.white.withValues(alpha: .45),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thumbnail Congklak: papan kayu dengan 2 baris lubang & biji.
class CongklakPreview extends StatelessWidget {
  const CongklakPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: _CongklakPainter())),
      ),
    );
  }
}

class _CongklakPainter extends CustomPainter {
  static const _seeds = [Color(0xFFFFF3DC), Color(0xFFFFD9B0), Color(0xFFF3C58B), Color(0xFFD9EEF0)];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final fill = Paint();
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(s * .2, s * .02, s * .6, s * .96), Radius.circular(s * .3));
    canvas.drawRRect(
      body,
      fill
        ..shader = const LinearGradient(colors: [Color(0xFFA0612D), Color(0xFFCF8D4F), Color(0xFF9A5A28)])
            .createShader(body.outerRect),
    );
    fill.shader = null;
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFF7A4520)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .015,
    );
    void hole(Offset c, double rx, double ry, int n, int seed) {
      canvas.drawOval(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2), fill..color = const Color(0xFF4A250D));
      for (var k = 0; k < n; k++) {
        final a = (seed * 37 + k * 71) % 360 * math.pi / 180, d = ((seed + k * 13) % 10) / 10 * .6;
        canvas.drawOval(
          Rect.fromCenter(center: c + Offset(rx * d * math.cos(a), ry * d * math.sin(a)), width: s * .035, height: s * .028),
          fill..color = _seeds[(seed + k) % _seeds.length],
        );
      }
    }

    hole(Offset(s * .5, s * .13), s * .2, s * .07, 4, 1);
    hole(Offset(s * .5, s * .87), s * .2, s * .07, 6, 2);
    for (var i = 0; i < 5; i++) {
      final y = s * (.27 + i * .115);
      hole(Offset(s * .38, y), s * .07, s * .045, 3 + i % 3, i * 3);
      hole(Offset(s * .62, y), s * .07, s * .045, 2 + (i + 1) % 3, i * 5 + 1);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
