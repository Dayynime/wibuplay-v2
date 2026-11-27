import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/decor_tick.dart';
import '../../providers.dart';
import '../../core/lite_mode.dart';

/// Tag "TOP GIVER" untuk user yang masuk leaderboard Top Giver.
/// Tidak render apa-apa kalau user tidak ada di leaderboard.
class TopGiverBadge extends ConsumerWidget {
  const TopGiverBadge({super.key, required this.firebaseUid, this.height = 20});

  final String firebaseUid;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (firebaseUid.isEmpty) return const SizedBox.shrink();
    final rank = ref.watch(topGiverRankProvider(firebaseUid));
    if (rank == null) return const SizedBox.shrink();
    return TopGiverChip(rank: rank, height: height);
  }
}

// =============================================================================
// Badge Top Giver gaya tokusatsu: #1 sampai #10 masing-masing punya BENTUK dan
// animasi sendiri, #11 ke atas memakai satu desain umum.
//
//  #1  Kaisar Matahari  lambang emas, antena V, sayap, syal; lingkar sinar berputar
//  #2  Ksatria Perak    perisai + bilah pedang; kilau + sabetan
//  #3  Ronin Perunggu   tsuba berisi 三 + sarung katana; kilatan tebasan
//  #4  Driver Merah     gesper sabuk segi delapan; turbin berputar
//  #5  Visor Neon       topeng bermata majemuk; mata berkilat
//  #6  Petir Ungu       bola energi; berdenyut + petir menyambar
//  #7  Gear Mecha       roda gigi + pelat mesin; gigi berputar, LED berkedip
//  #8  Topan Biru       pusaran; berputar + garis angin
//  #9  Kartu Rider      kartu di slot; kartu berbalik
//  #10 Sayap Serangga   cangkang heksagon; sayap bergetar
//  #11+ Umum            pelat besi "TOP GIVER #n"; garis scan
//
// Semua digambar satu CustomPainter dalam koordinat desain tinggi 18, lalu
// diskalakan ke [height]. Digambar ulang maks DecorTick.fps; diam kalau HP
// diset "hapus animasi".
// =============================================================================

class TopGiverChip extends StatefulWidget {
  const TopGiverChip({super.key, required this.rank, this.height = 20});

  final int rank;
  final double height;

  @override
  State<TopGiverChip> createState() => _TopGiverChipState();
}

class _TopGiverChipState extends State<TopGiverChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  late final Listenable _tick = DecorTick(_c);
  _Layout? _layout;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.liteRepeat();
    }
  }

  @override
  void didUpdateWidget(TopGiverChip old) {
    super.didUpdateWidget(old);
    if (old.rank != widget.rank) {
      _layout?.dispose();
      _layout = null;
    }
  }

  @override
  void dispose() {
    _layout?.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout ??= _Layout(widget.rank);
    final k = widget.height / 18;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _tick,
        builder: (context, _) => CustomPaint(
          size: Size(layout.width * k, widget.height),
          painter: _TopGiverPainter(layout, _c.value, k),
        ),
      ),
    );
  }
}

/// Teks yang sudah di-layout + lebar total desain (unit desain).
class _Layout {
  _Layout(this.rank) {
    final d = rank.clamp(1, 11);
    switch (d) {
      case 1:
        text = _tp('TOP GIVER', 8.5, Colors.white, shader: true, from: Colors.white, to: const Color(0xFFFFD25A));
        num = _tp('1', 10, const Color(0xFF3A2200), italic: false);
        plateW = 8 + text.width + 12;
        width = 33 + plateW + 13;
      case 2:
        text = _tp('TOP GIVER', 7.5, const Color(0xFF1A1F28));
        num = _tp('2', 10, const Color(0xFF151A22), italic: false);
        plateW = 8 + text.width + 14;
        width = 15 + plateW;
      case 3:
        text = _tp('TOP GIVER', 8, const Color(0xFFF6C39B));
        num = _tp('三', 8.5, const Color(0xFFF6C39B), italic: false);
        plateW = 13 + text.width + 10;
        width = 8 + plateW;
      case 4:
        text = _tp('TOP GIVER', 8, const Color(0xFFFF8A9A));
        num = _tp('4', 9, Colors.white, italic: false);
        plateW = 7 + text.width + 10;
        width = 18 + plateW;
      case 5:
        text = _tp('TOP GIVER', 8, Colors.white);
        num = _tp('5', 9, Colors.white, italic: false);
        plateW = 6 + text.width + 9;
        width = 32 + plateW;
      case 6:
        text = _tp('TOP GIVER', 8, const Color(0xFFD7B4FF));
        num = _tp('6', 9.5, Colors.white, italic: false);
        plateW = 9 + text.width + 10;
        width = 15 + plateW;
      case 7:
        text = _tp('TOP GIVER', 8, const Color(0xFFB9C2FF));
        num = _tp('7', 9, const Color(0xFFB9C2FF), italic: false);
        plateW = 8 + text.width + 4 + 3 + 10;
        width = 17 + plateW;
      case 8:
        text = _tp('TOP GIVER', 8, const Color(0xFFA9DCFF));
        num = _tp('8', 9, const Color(0xFFA9DCFF), italic: false);
        plateW = 9 + text.width + 10;
        width = 16 + plateW;
      case 9:
        text = _tp('TOP GIVER', 8, const Color(0xFF9FF2E4));
        num = _tp('9', 8.5, const Color(0xFF08201C), italic: false);
        plateW = 7 + text.width + 10;
        width = 15 + plateW;
      case 10:
        text = _tp('TOP GIVER', 8, const Color(0xFFC9F7A6));
        num = _tp('10', 8, const Color(0xFF0D2006), italic: false);
        plateW = 6 + text.width + 10;
        width = 7 + 18 + plateW;
      default:
        text = _tp('TOP GIVER', 7.5, const Color(0xFF9AA0AC));
        num = _tp('#$rank', 8, const Color(0xFFF5F5F7), italic: false);
        plateW = 8 + text.width + 5 + num.width + 8;
        width = plateW;
    }
  }

  final int rank;
  late final TextPainter text;
  late final TextPainter num;
  late final double plateW;
  late final double width;

  static TextPainter _tp(
    String s,
    double size,
    Color color, {
    bool italic = true,
    bool shader = false,
    Color? from,
    Color? to,
  }) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: italic ? 0.6 : 0,
      height: 1,
      color: shader ? null : color,
      foreground: shader
          ? (Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size), [from!, to!]))
          : null,
    );
    return TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
  }

  void dispose() {
    text.dispose();
    num.dispose();
  }
}

class _TopGiverPainter extends CustomPainter {
  _TopGiverPainter(this.l, this.t, this.k);

  final _Layout l;
  final double t; // 0..1 per 6 detik
  final double k;

  // ------------------------------------------------------------- helpers

  /// Fase berulang [n] kali per putaran (0..1).
  double ph(double n) => (t * n) % 1;

  Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  Paint fill(Color c) => Paint()..color = c;

  Paint stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = c;

  Paint lin(Offset a, Offset b, List<Color> cs, [List<double>? stops]) {
    final st = stops ?? (cs.length == 2 ? null : [for (var i = 0; i < cs.length; i++) i / (cs.length - 1)]);
    return Paint()..shader = ui.Gradient.linear(a, b, cs, st);
  }

  Paint rad(Offset c, double r, List<Color> cs, [List<double>? stops]) {
    final st = stops ?? (cs.length == 2 ? null : [for (var i = 0; i < cs.length; i++) i / (cs.length - 1)]);
    return Paint()..shader = ui.Gradient.radial(c, r, cs, st);
  }

  void centerText(Canvas c, TextPainter tp, Offset center) =>
      tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));

  /// Kilau miring yang menyapu [rect] (dipotong [clip]).
  void sweep(Canvas c, Path clip, Rect rect, double p, {double w = 10, double a = 0.8}) {
    if (p > 1) return;
    c.save();
    c.clipPath(clip);
    final x = rect.left - w * 2 + (rect.width + w * 4) * p;
    final path = Path()
      ..moveTo(x, rect.top)
      ..lineTo(x + w, rect.top)
      ..lineTo(x + w - 5, rect.bottom)
      ..lineTo(x - 5, rect.bottom)
      ..close();
    c.drawPath(
      path,
      lin(Offset(x - 5, 0), Offset(x + w, 0),
          [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, a), const Color(0x00FFFFFF)]),
    );
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(k);
    switch (l.rank.clamp(1, 11)) {
      case 1:
        _sun(canvas);
      case 2:
        _knight(canvas);
      case 3:
        _ronin(canvas);
      case 4:
        _driver(canvas);
      case 5:
        _visor(canvas);
      case 6:
        _thunder(canvas);
      case 7:
        _gear(canvas);
      case 8:
        _cyclone(canvas);
      case 9:
        _card(canvas);
      case 10:
        _insect(canvas);
      default:
        _plain(canvas);
    }
    canvas.restore();
  }

  // ------------------------------------------------------------------- #1
  void _sun(Canvas c) {
    const gold1 = Color(0xFFFFF3B0), gold2 = Color(0xFFF5B82E), gold3 = Color(0xFF8A5A06);
    const cx = 19.0, cy = 9.0;
    // Lingkar sinar berputar.
    final rot = t * math.pi * 2;
    final ray = Paint()..color = const Color(0xF2FFD25A);
    for (var i = 0; i < 12; i++) {
      final a = rot + i * math.pi / 6;
      final a2 = a + 0.1;
      final p = Path()
        ..moveTo(cx + math.cos(a) * 12.5, cy + math.sin(a) * 12.5)
        ..lineTo(cx + math.cos(a2) * 15.5, cy + math.sin(a2) * 15.5)
        ..lineTo(cx + math.cos(a2 + 0.06) * 12.5, cy + math.sin(a2 + 0.06) * 12.5)
        ..close();
      c.drawPath(p, ray);
    }
    // Sayap kiri mengepak.
    final flap = 1 - 0.4 * (0.5 + 0.5 * math.sin(t * math.pi * 2 * 5));
    c.save();
    c.translate(12, 2);
    c.scale(flap, 1);
    c.translate(-12, 0);
    c.drawPath(
      poly(const [Offset(12, 2.4), Offset(0, 0), Offset(3.6, 5.4), Offset(0, 8.4), Offset(12, 12)]),
      lin(Offset.zero, const Offset(12, 0), const [gold2, Color(0xFFFFE7A0)]),
    );
    c.restore();
    // Lambang segi lima.
    final crest = poly(const [Offset(19, -1), Offset(29, 6.6), Offset(25.4, 19), Offset(12.6, 19), Offset(9, 6.6)]);
    c.drawPath(crest, lin(const Offset(9, -1), const Offset(29, 19), const [gold1, gold2, gold3], const [0, 0.5, 1]));
    centerText(c, l.num, const Offset(19, 10.5));
    // Antena V.
    c.drawPath(
      poly(const [Offset(9, -10), Offset(12.2, -10), Offset(19, -3), Offset(25.8, -10), Offset(29, -10), Offset(20.2, 0), Offset(17.8, 0)]),
      lin(const Offset(0, -10), Offset.zero, const [gold1, gold2]),
    );
    // Pelat teks.
    final w = l.plateW;
    const x = 33.0;
    final plate = poly([const Offset(x, 1), Offset(x + w, 1), Offset(x + w - 6, 17), const Offset(x, 17)]);
    c.drawPath(plate, lin(const Offset(x, 0), Offset(x + w, 0), const [Color(0xFF3A2808), Color(0xFF140D02)]));
    c.drawPath(plate, stroke(gold2, 1));
    l.text.paint(c, Offset(x + 8, 9 - l.text.height / 2));
    sweep(c, plate, Rect.fromLTWH(x, 1, w, 16), ph(2.7) / 0.45 - 1.2, w: 9);
    // Syal merah berkibar.
    final wave = math.sin(t * math.pi * 2 * 13);
    final sx = x + w - 3;
    c.drawPath(
      poly([
        Offset(sx, 4.5),
        Offset(sx + 15 + 2 * wave, 3 + wave),
        Offset(sx + 12.3, 8 + wave),
        Offset(sx + 15 + 2 * wave, 13 + wave),
        Offset(sx, 11.5),
      ]),
      fill(const Color(0xFFE4344A)),
    );
    // Kilau bintang.
    final sp = ph(2.7);
    if (sp < 0.2) {
      final a = math.sin(sp / 0.2 * math.pi);
      _star(c, const Offset(31, -4), 2.6 * a, Color.fromRGBO(255, 243, 176, a));
    }
  }

  void _star(Canvas c, Offset p, double r, Color col) {
    c.drawPath(
      Path()
        ..moveTo(p.dx, p.dy - r)
        ..lineTo(p.dx + r * 0.3, p.dy - r * 0.3)
        ..lineTo(p.dx + r, p.dy)
        ..lineTo(p.dx + r * 0.3, p.dy + r * 0.3)
        ..lineTo(p.dx, p.dy + r)
        ..lineTo(p.dx - r * 0.3, p.dy + r * 0.3)
        ..lineTo(p.dx - r, p.dy)
        ..lineTo(p.dx - r * 0.3, p.dy - r * 0.3)
        ..close(),
      fill(col),
    );
  }

  // ------------------------------------------------------------------- #2
  void _knight(Canvas c) {
    final w = l.plateW;
    const x = 15.0;
    final blade = poly([const Offset(x, 3), Offset(x + w * 0.88, 3), Offset(x + w, 9), Offset(x + w * 0.88, 15), const Offset(x, 15)]);
    c.drawPath(blade, lin(const Offset(0, 3), const Offset(0, 15), const [Color(0xFFE9EEF5), Color(0xFF9AA3B2), Color(0xFF6D7686)], const [0, 0.6, 1]));
    l.text.paint(c, Offset(x + 8, 9 - l.text.height / 2));
    sweep(c, blade, Rect.fromLTWH(x, 3, w, 12), ph(3.3) / 0.5 - 0.4, w: 7, a: 0.95);
    final shield = poly(const [Offset(0, -1), Offset(17, -1), Offset(17, 11), Offset(8.5, 19), Offset(0, 11)]);
    c.drawPath(shield, lin(const Offset(0, -1), const Offset(17, 19), const [Colors.white, Color(0xFFBFC8D4), Color(0xFF5D6676)], const [0, 0.5, 1]));
    centerText(c, l.num, const Offset(8.5, 7.5));
    // Sabetan miring sekejap.
    final s = ph(3.3);
    if (s > 0.78 && s < 0.86) {
      c.drawLine(const Offset(-1, 18), const Offset(14, -4), stroke(Colors.white, 1.4));
    }
  }

  // ------------------------------------------------------------------- #3
  void _ronin(Canvas c) {
    final w = l.plateW;
    const x = 8.0;
    final saya = RRect.fromRectAndCorners(
      Rect.fromLTWH(x, 2.5, w, 13),
      topLeft: const Radius.circular(6),
      bottomLeft: const Radius.circular(6),
      topRight: const Radius.circular(2),
      bottomRight: const Radius.circular(2),
    );
    c.drawRRect(saya, lin(const Offset(0, 2.5), const Offset(0, 15.5), const [Color(0xFF6A3A1C), Color(0xFF2C160A)]));
    c.drawRRect(saya, stroke(const Color(0xFFC97A45), 1));
    l.text.paint(c, Offset(x + 13, 9 - l.text.height / 2));
    // Tsuba.
    const tc = Offset(9.5, 9);
    c.drawCircle(tc, 9.5, rad(tc, 9.5, const [Color(0xFF2C160A), Color(0xFF2C160A), Color(0xFFC97A45), Color(0xFFC97A45), Color(0xFF7A4220)], const [0, 0.34, 0.36, 0.6, 0.62]));
    centerText(c, l.num, tc);
    // Kilatan tebasan di bawah pelat.
    final p = ph(2.5);
    if (p > 0.6) {
      final grow = ((p - 0.6) / 0.15).clamp(0.0, 1.0);
      final fade = p > 0.75 ? 1 - (p - 0.75) / 0.25 : 1.0;
      final len = w * 0.8 * grow;
      c.drawRect(
        Rect.fromLTWH(16, 14.5, len, 1.6),
        lin(const Offset(16, 0), Offset(16 + math.max(1, len), 0),
            [Color.fromRGBO(255, 255, 255, fade), Color.fromRGBO(246, 195, 155, fade), const Color(0x00F6C39B)]),
      );
    }
  }

  // ------------------------------------------------------------------- #4
  void _driver(Canvas c) {
    final w = l.plateW;
    const x = 18.0;
    final belt = Rect.fromLTWH(x, 2, w, 14);
    c.drawRect(belt, fill(const Color(0xFF17191F)));
    for (double sx = x; sx < x + w; sx += 6) {
      c.drawRect(Rect.fromLTWH(sx, 2, 3, 14), fill(const Color(0xFF1B1E27)));
    }
    c.drawLine(Offset(x, 2.75), Offset(x + w, 2.75), stroke(const Color(0xFFE4344A), 1.5));
    c.drawLine(Offset(x, 15.25), Offset(x + w, 15.25), stroke(const Color(0xFF8E1426), 1.5));
    l.text.paint(c, Offset(x + 7, 9 - l.text.height / 2));
    // Gesper segi delapan.
    List<Offset> oct(double ox, double oy, double s) => [
          Offset(ox + s * .3, oy), Offset(ox + s * .7, oy), Offset(ox + s, oy + s * .3), Offset(ox + s, oy + s * .7),
          Offset(ox + s * .7, oy + s), Offset(ox + s * .3, oy + s), Offset(ox, oy + s * .7), Offset(ox, oy + s * .3),
        ];
    c.drawPath(poly(oct(0, -1.5, 21)), lin(const Offset(0, -1.5), const Offset(21, 19.5), const [Color(0xFFFF8A9A), Color(0xFFE4344A), Color(0xFF8E1426)], const [0, 0.45, 1]));
    c.drawPath(poly(oct(2.5, 1, 16)), fill(const Color(0xFF0B0D12)));
    // Turbin berputar.
    const cc = Offset(10.5, 9);
    c.save();
    c.translate(cc.dx, cc.dy);
    c.rotate(t * math.pi * 2 * 7);
    final a = fill(const Color(0xFFFF8A9A)), b = fill(const Color(0xFF8E1426));
    for (var i = 0; i < 12; i++) {
      c.drawArc(Rect.fromCircle(center: Offset.zero, radius: 6.5), i * math.pi / 6, math.pi / 6, true, i.isEven ? a : b);
    }
    c.restore();
    c.drawCircle(cc, 6.5, Paint()
      ..color = const Color(0x99E4344A)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 2));
    centerText(c, l.num, cc);
  }

  // ------------------------------------------------------------------- #5
  void _visor(Canvas c) {
    final w = l.plateW;
    const x = 32.0;
    final tag = poly([const Offset(x, 2.5), Offset(x + w, 2.5), Offset(x + w - 5, 15.5), const Offset(x, 15.5)]);
    c.drawPath(tag, lin(const Offset(x, 0), Offset(x + w, 0), const [Color(0xFF8F1F57), Color(0xFFF0509A)]));
    l.text.paint(c, Offset(x + 6, 9 - l.text.height / 2));
    const mw = 34.0;
    final mask = poly(const [Offset(mw * .12, 0), Offset(mw * .88, 0), Offset(mw, 7.2), Offset(mw * .86, 18), Offset(mw * .14, 18), Offset(0, 7.2)]);
    c.drawPath(mask, lin(Offset.zero, const Offset(0, 18), const [Color(0xFF2A2F3E), Color(0xFF0E1117)]));
    c.drawPath(mask, stroke(const Color(0xB3F0509A), 0.8));
    final blink = ph(3) > 0.85 && ph(3) < 0.95;
    void eye(List<Offset> pts, Offset ctr) {
      c.drawPath(poly(pts), rad(ctr + const Offset(-1, -1.5), 7, const [Colors.white, Color(0xFFFFB3D1), Color(0xFFF0509A), Color(0xFF8F1F57)], const [0, 0.15, 0.5, 1]));
      if (blink) c.drawPath(poly(pts), fill(const Color(0x99FFFFFF)));
    }
    eye(const [Offset(3, 4.5), Offset(13, 7.2), Offset(11.5, 13.5), Offset(5, 12.2)], const Offset(8, 8));
    eye(const [Offset(21, 7.2), Offset(31, 4.5), Offset(29, 12.2), Offset(22.5, 13.5)], const Offset(26, 8));
    centerText(c, l.num, const Offset(17, 9));
  }

  // ------------------------------------------------------------------- #6
  void _thunder(Canvas c) {
    final w = l.plateW;
    const x = 15.0;
    final bar = RRect.fromRectAndCorners(Rect.fromLTWH(x, 2, w, 14), topRight: const Radius.circular(3), bottomRight: const Radius.circular(3));
    c.drawRRect(bar, fill(const Color(0xFF170C2B)));
    c.drawRRect(bar, stroke(const Color(0xFF9B5CFF), 1));
    l.text.paint(c, Offset(x + 9, 9 - l.text.height / 2));
    const oc = Offset(9.5, 9);
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 6);
    c.drawCircle(oc, 9.5 + 2 * pulse, Paint()
      ..color = Color.fromRGBO(155, 92, 255, 0.35 + 0.25 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    c.drawCircle(oc, 9.5, rad(const Offset(7.6, 6.7), 11, const [Color(0xFFEBD9FF), Color(0xFF9B5CFF), Color(0xFF3A1478)], const [0, 0.5, 1]));
    centerText(c, l.num, oc);
    // Petir menyambar.
    final zap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.miter
      ..color = const Color(0xFFE6D4FF);
    final p = ph(4.6);
    void bolt(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      c.drawPath(path, zap..maskFilter = null);
      c.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = const Color(0x669B5CFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    }
    if (p > 0.7 && p < 0.8) {
      bolt([Offset(x + 2, 9), Offset(x + 10, 1), Offset(x + 14, 11), Offset(x + 22, -1), Offset(x + 26, 9), Offset(x + 34, 3)]);
    }
    if (p > 0.2 && p < 0.3) {
      bolt([Offset(x + w * .45, 17), Offset(x + w * .55, 7), Offset(x + w * .6, 15), Offset(x + w * .7, 5), Offset(x + w * .78, 13), Offset(x + w * .9, 7)]);
    }
  }

  // ------------------------------------------------------------------- #7
  void _gear(Canvas c) {
    final w = l.plateW;
    const x = 17.0;
    final plate = poly([const Offset(x, 2), Offset(x + w, 2), Offset(x + w - 4, 9), Offset(x + w, 16), const Offset(x, 16)]);
    c.drawPath(plate, lin(const Offset(0, 2), const Offset(0, 16), const [Color(0xFF252A4A), Color(0xFF11142A)]));
    c.drawPath(plate, stroke(const Color(0xFF5C6CFF), 1));
    l.text.paint(c, Offset(x + 8, 9 - l.text.height / 2));
    final on = ph(6) < 0.5;
    c.drawCircle(Offset(x + 8 + l.text.width + 5.5, 9), 1.5, fill(on ? const Color(0xFF7CFFB2) : const Color(0xFF2A5A44)));
    // Roda gigi.
    const gc = Offset(10, 9);
    c.save();
    c.translate(gc.dx, gc.dy);
    c.rotate(t * math.pi * 2 * 1.5);
    final tooth = fill(const Color(0xFF5C6CFF));
    for (var i = 0; i < 12; i++) {
      c.save();
      c.rotate(i * math.pi / 6);
      c.drawRect(const Rect.fromLTWH(-1.4, -10, 2.8, 3.4), tooth);
      c.restore();
    }
    c.restore();
    c.drawCircle(gc, 7, rad(gc, 7, const [Color(0xFF202660), Color(0xFF0B0E24)]));
    c.drawCircle(gc, 7, stroke(const Color(0xFFB9C2FF), 1.4));
    centerText(c, l.num, gc);
  }

  // ------------------------------------------------------------------- #8
  void _cyclone(Canvas c) {
    final w = l.plateW;
    const x = 16.0;
    final tail = RRect.fromRectAndCorners(Rect.fromLTWH(x, 2, w, 14), topRight: const Radius.circular(8), bottomRight: const Radius.circular(8));
    c.drawRRect(tail, lin(const Offset(x, 0), Offset(x + w, 0), const [Color(0xFF123354), Color(0xFF0B1A2B)]));
    // Garis angin.
    c.save();
    c.clipRRect(tail);
    final wind = Paint()..strokeWidth = 0.8;
    for (var i = 0; i < 2; i++) {
      final p = (ph(6.7) + i * 0.5) % 1;
      final wx = x - 16 + (w + 16) * p;
      final y = i == 0 ? 5.0 : 12.0;
      wind.shader = ui.Gradient.linear(Offset(wx, y), Offset(wx + 16, y), const [Color(0x00A9DCFF), Color(0xB3A9DCFF)]);
      c.drawLine(Offset(wx, y), Offset(wx + 16, y), wind);
    }
    c.restore();
    l.text.paint(c, Offset(x + 9, 9 - l.text.height / 2));
    // Pusaran.
    const vc = Offset(10, 9);
    c.drawCircle(vc, 10, Paint()
      ..shader = ui.Gradient.sweep(
        vc,
        const [Color(0xFFA9DCFF), Color(0x00A9DCFF), Color(0xFF3C9BE0), Color(0x003C9BE0), Color(0xFFA9DCFF)],
        const [0, 0.3, 0.5, 0.8, 1],
        TileMode.clamp,
        0,
        math.pi * 2,
        (Matrix4.translationValues(vc.dx, vc.dy, 0)
              ..multiply(Matrix4.rotationZ(t * math.pi * 2 * 7.5))
              ..multiply(Matrix4.translationValues(-vc.dx, -vc.dy, 0)))
            .storage,
      ));
    c.drawCircle(vc, 4.6 + 1.6, fill(const Color(0xFF0E2238)));
    centerText(c, l.num, vc);
  }

  // ------------------------------------------------------------------- #9
  void _card(Canvas c) {
    final w = l.plateW;
    const x = 15.0;
    final slot = Rect.fromLTWH(x, 2, w, 14);
    c.drawRect(slot, fill(const Color(0xFF0B201D)));
    c.drawRect(slot, stroke(const Color(0xFF1FBFA6), 1));
    c.drawRect(Rect.fromLTWH(x, 2, 3, 14), fill(const Color(0xFF1FBFA6)));
    l.text.paint(c, Offset(x + 7, 9 - l.text.height / 2));
    // Kartu berbalik (0.7..1 tiap 2.3 putaran).
    final p = ph(2.3);
    final ang = p < 0.7 ? 0.0 : (p - 0.7) / 0.3 * math.pi * 2;
    final sx = math.cos(ang);
    const cc = Offset(8, 9);
    c.save();
    c.translate(cc.dx, cc.dy);
    c.scale(sx.abs() < 0.05 ? 0.05 : sx.abs(), 1);
    final card = RRect.fromRectAndRadius(const Rect.fromLTWH(-7, -10, 14, 20), const Radius.circular(2));
    if (sx >= 0) {
      c.drawRRect(card, lin(const Offset(-7, -10), const Offset(7, 10), const [Color(0xFF9FF2E4), Color(0xFF1FBFA6), Color(0xFF0E6B5D)], const [0, 0.55, 1]));
      c.drawRRect(card, stroke(const Color(0xFFD9FFF8), 1));
      centerText(c, l.num, Offset.zero);
    } else {
      // Sisi belakang kartu.
      c.drawRRect(card, fill(const Color(0xFF0E6B5D)));
      c.drawRRect(card, stroke(const Color(0xFF9FF2E4), 1));
      c.drawLine(const Offset(-4, -6), const Offset(4, 6), stroke(const Color(0xFF9FF2E4), 1));
      c.drawLine(const Offset(4, -6), const Offset(-4, 6), stroke(const Color(0xFF9FF2E4), 1));
    }
    c.restore();
  }

  // ------------------------------------------------------------------ #10
  void _insect(Canvas c) {
    final w = l.plateW;
    const x = 7 + 18.0;
    final plate = poly([Offset(x, 2.5), Offset(x + w, 2.5), Offset(x + w - 4, 15.5), Offset(x, 15.5)]);
    c.drawPath(plate, lin(Offset(x, 0), Offset(x + w, 0), const [Color(0xFF1B3A10), Color(0xFF0E1F08)]));
    c.drawPath(plate, stroke(const Color(0xFF5FC93C), 1));
    l.text.paint(c, Offset(x + 6, 9 - l.text.height / 2));
    // Sayap bergetar.
    final buzz = 0.75 + 0.25 * (ph(40) < 0.5 ? 1 : 0);
    c.save();
    c.translate(7, 15);
    c.scale(1, buzz);
    c.translate(-7, -15);
    c.drawPath(
      poly(const [Offset(11, 15), Offset(0, 1), Offset(6.6, 2.4)]),
      lin(Offset.zero, const Offset(11, 15), const [Color(0xD9C9F7A6), Color(0x665FC93C)]),
    );
    c.drawPath(
      poly(const [Offset(11, 15), Offset(2, 5), Offset(8, 4.5)]),
      lin(Offset.zero, const Offset(11, 15), const [Color(0xB3C9F7A6), Color(0x4D5FC93C)]),
    );
    c.restore();
    // Cangkang heksagon.
    const bx = 7.0;
    final shell = poly(const [Offset(bx + 8, 0), Offset(bx + 16, 5.4), Offset(bx + 16, 13.5), Offset(bx + 8, 18), Offset(bx, 13.5), Offset(bx, 5.4)]);
    c.drawPath(shell, lin(const Offset(bx, 0), const Offset(bx + 16, 18), const [Color(0xFFC9F7A6), Color(0xFF5FC93C), Color(0xFF2E6E1B)], const [0, 0.55, 1]));
    centerText(c, l.num, const Offset(bx + 8, 9));
  }

  // ----------------------------------------------------------------- #11+
  void _plain(Canvas c) {
    final w = l.plateW;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 2, w, 14), const Radius.circular(3));
    c.drawRRect(r, fill(const Color(0xFF151A23)));
    c.drawRRect(r, stroke(const Color(0xFF3A4253), 1));
    l.text.paint(c, Offset(8, 9 - l.text.height / 2));
    l.num.paint(c, Offset(8 + l.text.width + 5, 9 - l.num.height / 2));
    c.save();
    c.clipRRect(r);
    final y = 2 + 14 * ph(2.1);
    c.drawLine(Offset(0, y), Offset(w, y), stroke(const Color(0x2EFFFFFF), 1));
    c.restore();
  }

  @override
  bool shouldRepaint(_TopGiverPainter old) => old.t != t || old.k != k || !identical(old.l, l);
}
