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
