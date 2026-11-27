import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/lite_mode.dart';

/// Thumbnail "Zenime Town": pemandangan pixel kecil (rumput, jalan, meja
/// diskusi, pohon, dan beberapa karakter yang melompat pelan).
class TownPreview extends StatefulWidget {
  const TownPreview({super.key});

  @override
  State<TownPreview> createState() => _TownPreviewState();
}

class _TownPreviewState extends State<TownPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.of(context).disableAnimations) _c.liteRepeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(painter: _TownPainter(_c.value), size: Size.infinite),
    );
  }
}

class _TownPainter extends CustomPainter {
  _TownPainter(this.t);

  final double t;

  // Ukuran adegan dalam "pixel" (diskalakan memenuhi kotak).
  static const double _w = 64, _h = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.max(size.width / _w, size.height / _h);
    canvas.save();
    canvas.translate((size.width - _w * s) / 2, (size.height - _h * s) / 2);
    canvas.scale(s);
    final p = Paint()..isAntiAlias = false;
    void px(Color c, double x, double y, [double w = 1, double h = 1]) {
      p.color = c;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), p);
    }

    // Rumput + bintik.
    px(const Color(0xFF6CC24A), 0, 0, _w, _h);
    for (var i = 0; i < 40; i++) {
      px(i.isEven ? const Color(0xFF5AAE3C) : const Color(0xFF7FD25A), (i * 37 % 64).toDouble(), (i * 23 % 36).toDouble());
    }
    // Jalan.
    px(const Color(0xFFE3CF9F), 0, 22, _w, 6);
    px(const Color(0xFFD4BD88), 0, 22, _w, 1);
    px(const Color(0xFFE3CF9F), 27, 0, 6, 22);
    // Pohon.
    void tree(double x, double y) {
      px(const Color(0x33000000), x + 1, y + 9, 8, 2);
      px(const Color(0xFF6E4426), x + 4, y + 6, 2, 4);
      px(const Color(0xFF2F8F3A), x, y, 10, 7);
      px(const Color(0xFF3FAE47), x + 1, y, 8, 5);
      px(const Color(0xFF5CC85A), x + 2, y + 1, 3, 2);
    }

    tree(2, 2);
    tree(52, 4);
    tree(14, 26);
    // Meja diskusi + kursi.
    px(const Color(0xFF8A5A35), 40, 9, 3, 3);
    px(const Color(0xFF8A5A35), 47, 9, 3, 3);
    px(const Color(0xFF8A5A35), 40, 19, 3, 3);
    px(const Color(0xFF8A5A35), 47, 19, 3, 3);
    px(const Color(0xFF4A3A6E), 38, 12, 14, 7);
    px(const Color(0xFF8B6FD6), 39, 12, 12, 5);
    px(const Color(0xFFA891EA), 39, 12, 12, 1);
    // Meja game kecil (Ludo).
    px(const Color(0xFF6E4426), 8, 13, 12, 7);
    px(const Color(0xFFFF6B81), 10, 14, 4, 2);
    px(const Color(0xFF2FD59A), 14, 14, 4, 2);
    px(const Color(0xFF4D9DFF), 10, 16, 4, 2);
    px(const Color(0xFFFFC53D), 14, 16, 4, 2);

    // Karakter kecil (lompat bergantian).
    void char(double x, double y, Color hair, Color shirt, double phase) {
      final bob = (math.sin((t + phase) * math.pi * 2) > .6) ? -1.0 : 0.0;
      y += bob;
      px(const Color(0x33000000), x, y + 8, 5, 1);
      px(const Color(0xFF1D1A2B), x - 1, y - 1, 7, 9);
      px(hair, x, y, 5, 2);
      px(const Color(0xFFFFD9B8), x, y + 2, 5, 2);
      px(const Color(0xFF1D1A2B), x + 1, y + 2);
      px(const Color(0xFF1D1A2B), x + 3, y + 2);
      px(shirt, x, y + 4, 5, 2);
      px(const Color(0xFF2B3A55), x + 1, y + 6, 1, 2);
      px(const Color(0xFF2B3A55), x + 3, y + 6, 1, 2);
    }

    char(43, 5, const Color(0xFFE0B04A), const Color(0xFF4D9DFF), 0);
    char(54, 13, const Color(0xFF2B2233), const Color(0xFFFF6B81), .33);
    char(28, 14, const Color(0xFFE8657A), const Color(0xFF2FD59A), .66);
    // Gelembung chat.
    px(const Color(0xFF1D1A2B), 22, 4, 12, 7);
    px(Colors.white, 23, 5, 10, 5);
    px(const Color(0xFF1D1A2B), 26, 11, 2, 1);
    for (var i = 0; i < 3; i++) {
      px(const Color(0xFF1D1A2B), 25 + i * 2.5, 7, 1, 1);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TownPainter old) => old.t != t;
}
