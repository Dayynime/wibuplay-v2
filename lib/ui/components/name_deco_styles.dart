import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/decor_tick.dart';

/// Dekorasi nama futuristik (dibeli pakai ZCoin di Decor > Dekorasi Nama).
///
/// ```dart
/// NameDecoText(name: 'Dayynime', style: NameDecoStyle.laserEdge, fontSize: 12)
/// ```
///
/// Huruf memakai Orbitron (google_fonts). Semua efek digambar CustomPainter,
/// satu AnimationController per nama, digambar ulang lewat [DecorTick]
/// (maks 30 fps) di dalam RepaintBoundary, dan diam kalau "kurangi animasi".

enum NameDecoTier {
  biasa('Biasa', Color(0xFF9AA3B2)),
  langka('Langka', Color(0xFF3FD0FF)),
  epik('Epik', Color(0xFFB98CFF)),
  legenda('Legenda', Color(0xFFFFC93C));

  const NameDecoTier(this.label, this.color);
  final String label;
  final Color color;
}

enum NameDecoStyle {
  cyberPlate('cyber_plate', 'Cyber Plate', NameDecoTier.biasa),
  hudLock('hud_lock', 'HUD Lock', NameDecoTier.biasa),
  scanline('scanline', 'Scanline', NameDecoTier.langka),
  decode('decode', 'Decode', NameDecoTier.langka),
  circuit('circuit', 'Circuit', NameDecoTier.langka),
  laserEdge('laser_edge', 'Laser Edge', NameDecoTier.epik),
  neonTube('neon_tube', 'Neon Tube', NameDecoTier.epik),
  dataStream('data_stream', 'Data Stream', NameDecoTier.epik),
  holoProjector('holo_projector', 'Proyektor Holo', NameDecoTier.legenda),
  quantumCore('quantum_core', 'Quantum Core', NameDecoTier.legenda),
  synthwave('synthwave', 'Synthwave', NameDecoTier.legenda),
  mechaChrome('mecha_chrome', 'Mecha Chrome', NameDecoTier.legenda),

  // ---- Seri 2: tanpa bingkai/latar, tiap gaya punya font sendiri.
  terminal('terminal', 'Terminal', NameDecoTier.biasa, font: 'VT323', sizeK: 1.3, weight: FontWeight.w400),
  arcade('arcade', 'Arcade', NameDecoTier.biasa, font: 'Press Start 2P', sizeK: .72, weight: FontWeight.w400),
  streetComic('street_comic', 'Komik', NameDecoTier.biasa, font: 'Bangers', sizeK: 1.2, weight: FontWeight.w400),
  neonSign('neon_sign', 'Papan Neon', NameDecoTier.langka, font: 'Monoton', sizeK: 1.0, weight: FontWeight.w400),
  horrorDrip('horror_drip', 'Horor', NameDecoTier.langka, font: 'Creepster', sizeK: 1.2, weight: FontWeight.w400),
  stencilOps('stencil_ops', 'Militer', NameDecoTier.langka, font: 'Black Ops One', sizeK: 1.05, weight: FontWeight.w400),
  racer('racer', 'Pembalap', NameDecoTier.epik, font: 'Russo One', sizeK: 1.05, weight: FontWeight.w400),
  rgbGlitch('rgb_glitch', 'Glitch RGB', NameDecoTier.epik, font: 'Rubik Glitch', sizeK: 1.1, weight: FontWeight.w400),
  royalGold('royal_gold', 'Bangsawan', NameDecoTier.epik, font: 'Cinzel Decorative', sizeK: 1.0, weight: FontWeight.w900),
  zenSpace('zen_space', 'Kosmik', NameDecoTier.legenda, font: 'Zen Dots', sizeK: 1.0, weight: FontWeight.w400),
  auroraFlow('aurora_flow', 'Aurora', NameDecoTier.legenda, font: 'Audiowide', sizeK: 1.05, weight: FontWeight.w400),
  rainbowWave('rainbow_wave', 'Pelangi', NameDecoTier.legenda, font: 'Righteous', sizeK: 1.1, weight: FontWeight.w400);

  const NameDecoStyle(this.id, this.label, this.tier,
      {this.font = 'Orbitron', this.sizeK = 1, this.weight = FontWeight.w800});

  final String id;
  final String label;
  final NameDecoTier tier;

  /// Font Google Fonts untuk gaya ini (diunduh otomatis lewat google_fonts).
  final String font;

  /// Pengali ukuran huruf (font lebar/sempit disamakan tingginya).
  final double sizeK;
  final FontWeight weight;

  /// Gaya yang memakai bingkai/pelat (butuh ruang di kiri-kanan nama).
  bool get framed => switch (this) {
        cyberPlate || hudLock || laserEdge || dataStream || mechaChrome || synthwave => true,
        _ => false,
      };

  /// Ruang tambahan di kiri nama (garis kecepatan Pembalap).
  double get padLeftK => this == racer ? 9 : 0;

  /// Ruang ekstra di kanan nama untuk hiasan (kursor, bidikan, kilau).
  double get padRightK => switch (this) {
        mechaChrome => 14,
        terminal => 10,
        stencilOps => 11,
        arcade => 7,
        _ => 0,
      };

  static NameDecoStyle? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Nama pengguna dengan dekorasi [style].
class NameDecoText extends StatefulWidget {
  const NameDecoText({
    super.key,
    required this.name,
    required this.style,
    this.fontSize = 13,
    this.animate = true,
    this.maxWidth,
  });

  final String name;
  final NameDecoStyle style;
  final double fontSize;

  /// false = gambar diam (pose statis), tanpa ticker.
  final bool animate;

  /// Batas lebar nama (diberi "…" kalau kepanjangan). null = 260.
  final double? maxWidth;

  @override
  State<NameDecoText> createState() => _NameDecoTextState();
}

class _NameDecoTextState extends State<NameDecoText> with SingleTickerProviderStateMixin {
  // Satu putaran panjang supaya efek dengan frekuensi berbeda tidak kelihatan "lompat".
  static const double _loopSec = 24;

  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 24000));
  late final Animation<double> _tick = DecorAnimation(_c);
  _Glyphs? _glyphs;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(NameDecoText old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name || old.fontSize != widget.fontSize || old.style != widget.style) {
      _retire(_glyphs);
      _glyphs = null;
    }
    _syncTicker();
  }

  void _syncTicker() {
    final run = widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  void _fontsChanged() {
    if (!mounted) return;
    _retire(_glyphs);
    setState(() => _glyphs = null); // Orbitron baru selesai diunduh
  }

  /// Lepas TextPainter lama setelah frame berikutnya (painter lama sudah diganti).
  void _retire(_Glyphs? g) {
    if (g == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => g.dispose());
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _c.dispose();
    _glyphs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.fontSize / 16;
    final st = widget.style;
    final padX = (st.framed ? 9.0 : 3.0) * k;
    final padL = padX + st.padLeftK * k;
    final padY = (st == NameDecoStyle.horrorDrip ? 7.0 : 4.0) * k;
    final extra = st.padRightK * k;
    final textMax = math.max(20.0, (widget.maxWidth ?? 260) - padX - padL - extra);
    var g = _glyphs;
    if (g == null || g.maxWidth != textMax) {
      _retire(g);
      g = _glyphs = _Glyphs(widget.name, widget.fontSize * st.sizeK, textMax, st.font, st.weight);
    }
    final size = Size(g.fill.width + padX + padL + extra, g.fill.height + padY * 2);
    final running = widget.animate && !MediaQuery.disableAnimationsOf(context);
    // FittedBox: kalau tempatnya sempit, nama diperkecil (bukan meluap).
    return Semantics(
      label: widget.name,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: _NameDecoPainter(
              glyphs: g,
              style: widget.style,
              k: k,
              pad: Offset(padL, padY),
              anim: running ? _tick : null,
              loopSec: _loopSec,
            ),
          ),
        ),
      ),
    );
  }
}

/// Teks nama yang sudah di-layout, plus varian berwarna yang di-cache.
class _Glyphs {
  _Glyphs(this.text, this.fontSize, this.maxWidth, this.font, this.weight)
      : fill = _tp(text, fontSize, maxWidth, Paint()..color = Colors.white, font, weight);

  final String text;
  final double fontSize;
  final double maxWidth;
  final String font;
  final FontWeight weight;
  /// Ukuran/tata letak dasar (juga dipakai untuk geometri efek).
  final TextPainter fill;

  static TextStyle styleFor(double fontSize, Paint p, String font, FontWeight weight) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: font == 'Orbitron' ? fontSize * .09 : fontSize * .03,
      height: 1.15,
      foreground: p,
    );
    try {
      return GoogleFonts.getFont(font, textStyle: base);
    } catch (_) {
      return base; // font tidak dikenal versi google_fonts ini: pakai bawaan
    }
  }

  static TextPainter _tp(String s, double fontSize, double maxWidth, Paint p, String font, FontWeight weight) => TextPainter(
        text: TextSpan(text: s, style: styleFor(fontSize, p, font, weight)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);

  // Varian teks berwarna (warna/gradien langsung di foreground TextPainter,
  // tanpa saveLayer + srcIn yang tidak stabil di sebagian GPU/Impeller).
  final Map<String, TextPainter> _variants = {};

  TextPainter variant(String s, NameBase base, String key, double alpha, Paint Function() mk) {
    final a = (alpha.clamp(0.0, 1.0) * 10).round();
    final ck = '$s|${base.index}|$key|$a';
    final hit = _variants[ck];
    if (hit != null) return hit;
    if (_variants.length > 80) {
      final old = _variants.values.toList();
      _variants.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final tp in old) {
          tp.dispose();
        }
      });
    }
    final p = mk();
    final f = a / 10;
    if (p.shader == null) {
      p.color = p.color.withValues(alpha: p.color.a * f);
    } else {
      p.color = Color.fromRGBO(0, 0, 0, f);
    }
    switch (base) {
      case NameBase.fill:
        break;
      case NameBase.glow:
        p.maskFilter = MaskFilter.blur(BlurStyle.normal, fontSize / 5);
      case NameBase.stroke:
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, fontSize / 9)
          ..strokeJoin = StrokeJoin.round;
      case NameBase.thin:
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.6, fontSize / 26)
          ..strokeJoin = StrokeJoin.round;
    }
    return _variants[ck] = _tp(s, fontSize, maxWidth, p, font, weight);
  }

  void dispose() {
    for (final tp in _variants.values) {
      tp.dispose();
    }
    _variants.clear();
    fill.dispose();
  }
}

/// Bentuk dasar teks: isi, cahaya blur, garis tebal, garis tipis.
enum NameBase { fill, glow, stroke, thin }

class _NameDecoPainter extends CustomPainter {
  _NameDecoPainter({
    required this.glyphs,
    required this.style,
    required this.k,
    required this.pad,
    required this.anim,
    required this.loopSec,
  }) : super(repaint: anim);

  final _Glyphs glyphs;
  final NameDecoStyle style;
  final double k;
  final Offset pad;
  final Animation<double>? anim;
  final double loopSec;

  static const String _gly = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#\$%&@<>/';

  // --------------------------------------------------------------- helpers

  /// Gambar teks nama ([s] = teks lain, mis. hasil acak Decode) dengan bentuk
  /// [base] dan warna/gradien dari [mk] (di-cache per [key] + [alpha]).
  void _txt(Canvas c, NameBase base, String key, Offset o, Paint Function() mk, {double alpha = 1, String? s}) {
    glyphs.variant(s ?? glyphs.text, base, key, alpha, mk).paint(c, o);
  }

  Paint _col(Color c) => Paint()..color = c;

  Paint _lin(Offset a, Offset b, List<Color> colors, [List<double>? stops, TileMode mode = TileMode.clamp]) =>
      Paint()..shader = ui.Gradient.linear(a, b, colors, stops, mode);

  Path _cut(Rect r, double kk) => Path()
    ..moveTo(r.left + kk, r.top)
    ..lineTo(r.right, r.top)
    ..lineTo(r.right, r.bottom - kk)
    ..lineTo(r.right - kk, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..lineTo(r.left, r.top + kk)
    ..close();

  /// Potongan garis sepanjang [len] mulai dari jarak [start] di keliling [path].
  Path _dash(Path path, double start, double len) {
    final out = Path();
    for (final m in path.computeMetrics()) {
      final total = m.length;
      var s = start % total;
      if (s < 0) s += total;
      final e = s + len;
      out.addPath(m.extractPath(s, math.min(e, total)), Offset.zero);
      if (e > total) out.addPath(m.extractPath(0, e - total), Offset.zero);
    }
    return out;
  }

  double _rnd(int i, int j) {
    final v = math.sin(i * 12.9898 + j * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  // ---------------------------------------------------------------- paint

  @override
  void paint(Canvas c, Size size) {
    final t = anim == null ? 0.8 : anim!.value * loopSec;
    final fill = glyphs.fill;
    final o = pad;
    final w = fill.width, th = fill.height;
    final box = Rect.fromLTWH(0, 0, size.width, size.height);
    final cy = o.dy + th / 2;
    final midText = Offset(o.dx, o.dy);

    switch (style) {
      case NameDecoStyle.cyberPlate:
        final plate = _cut(box, 6 * k);
        c.drawPath(plate, _col(const Color(0x1400E5FF)));
        c.drawPath(plate, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xBF00E5FF));
        c.save();
        c.clipPath(plate);
        final s = ((t * .5) % 1.4 - .2) * box.width;
        c.drawRect(box, _lin(Offset(s - 20 * k, 0), Offset(s + 20 * k, 0),
            const [Color(0x0000E5FF), Color(0x5900E5FF), Color(0x0000E5FF)]));
        c.restore();
        c.drawRect(Rect.fromLTWH(box.right - 3 * k, 3 * k, 2 * k, 6 * k), _col(const Color(0xFF00E5FF)));
        c.drawRect(Rect.fromLTWH(2 * k, box.bottom - 3 * k, 10 * k, 1.5 * k), _col(const Color(0xFF00E5FF)));
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF00E5FF)), alpha: .8);
        _txt(c, NameBase.fill, 'f', midText, () => _col(const Color(0xFFE8FDFF)));

      case NameDecoStyle.hudLock:
        final kk = (6 + 2 * math.sin(t * 3)) * k, off = 2 * k * math.sin(t * 3);
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * k
          ..color = const Color(0xFF3DFFB0);
        final r = box.deflate(1.5 * k).inflate(off);
        void br(Offset a, double sx, double sy) =>
            c.drawPath(Path()..moveTo(a.dx, a.dy + sy * kk)..lineTo(a.dx, a.dy)..lineTo(a.dx + sx * kk, a.dy), p);
        br(r.topLeft, 1, 1);
        br(r.topRight, -1, 1);
        br(r.bottomLeft, 1, -1);
        br(r.bottomRight, -1, -1);
        for (var i = 0; i < 5; i++) {
          c.drawRect(Rect.fromLTWH(4 * k + i * 5 * k, box.bottom + 2 * k, 3 * k, 1 * k), _col(const Color(0xB33DFFB0)));
        }
        if (math.sin(t * 6) > 0) c.drawRect(Rect.fromLTWH(box.right + 2 * k, 2 * k, 2 * k, 2 * k), _col(const Color(0xFF3DFFB0)));
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF3DFFB0)), alpha: .7);
        _txt(c, NameBase.fill, 'f', midText, () => _col(const Color(0xFFEFFFF8)));

      case NameDecoStyle.scanline:
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF2E9BFF)), alpha: .8);
        final tr = midText & fill.size;
        c.saveLayer(tr.inflate(4), Paint());
        _txt(c, NameBase.fill, 'f', midText, () => _lin(tr.topCenter, tr.bottomCenter, const [Color(0xFF7CF9FF), Color(0xFF2E9BFF)]));
        for (var yy = tr.top; yy < tr.bottom; yy += 3 * k) {
          c.drawRect(Rect.fromLTWH(tr.left - 2, yy, tr.width + 4, math.max(1.0, k)),
              Paint()
                ..color = const Color(0x47000000)
                ..blendMode = BlendMode.dstOut);
        }
        final sy = tr.top + ((t * .9) % 1) * tr.height;
        c.drawRect(Rect.fromLTWH(tr.left - 2, sy - 5 * k, tr.width + 4, 10 * k),
            _lin(Offset(0, sy - 5 * k), Offset(0, sy + 5 * k), const [Color(0x00FFFFFF), Color(0xF2FFFFFF), Color(0x00FFFFFF)])
              ..blendMode = BlendMode.srcATop);
        c.restore();
        c.drawRect(Rect.fromLTWH(0, sy, 2.5 * k, 1), _col(const Color(0x997CF9FF)));
        c.drawRect(Rect.fromLTWH(box.right - 2.5 * k, sy, 2.5 * k, 1), _col(const Color(0x997CF9FF)));

      case NameDecoStyle.decode:
        final cyc = t % 4, scr = cyc < 1.1;
        var shown = glyphs.text;
        if (scr) {
          final src = glyphs.text;
          final b = StringBuffer();
          for (var i = 0; i < src.length; i++) {
            final done = cyc > .15 + i * .11 || src[i] == ' ';
            b.write(done ? src[i] : _gly[((t * 30).floor() + i * 7) % _gly.length]);
          }
          shown = b.toString();
        } else {
          _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFFB478FF)), alpha: .7);
        }
        final tp = glyphs.variant(shown, NameBase.fill, scr ? 'fs' : 'f', 1,
            () => _col(scr ? const Color(0xFFFF4FD8) : const Color(0xFFF4F0FF)));
        tp.paint(c, midText);
        if (math.sin(t * 8) > 0) {
          c.drawRect(Rect.fromLTWH(o.dx + tp.width + 3 * k, o.dy + th * .18, 6 * k, th * .64), _col(const Color(0xFFFF4FD8)));
        }

      case NameDecoStyle.circuit:
        final lx = o.dx - 3 * k, rx = o.dx + w + 3 * k, ty = o.dy - 1 * k, by = o.dy + th + 1 * k;
        final paths = <List<Offset>>[
          [Offset(lx, cy), Offset(lx - 5 * k, cy), Offset(lx - 5 * k, ty - 2 * k), Offset(lx + 30 * k, ty - 2 * k)],
          [Offset(rx, cy + 4 * k), Offset(rx + 7 * k, cy + 4 * k), Offset(rx + 7 * k, by + 3 * k), Offset(rx - 40 * k, by + 3 * k)],
          [Offset(o.dx + w * .5, ty), Offset(o.dx + w * .5, ty - 5 * k), Offset(o.dx + w * .8, ty - 5 * k)],
        ];
        final line = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.8, k)
          ..color = const Color(0x5900FFAA);
        for (var pi = 0; pi < paths.length; pi++) {
          final pts = paths[pi];
          final path = Path()..moveTo(pts.first.dx, pts.first.dy);
          for (final p in pts.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          c.drawPath(path, line);
          c.drawRect(Rect.fromCenter(center: pts.last, width: 3 * k, height: 3 * k), _col(const Color(0xB300FFAA)));
          final m = path.computeMetrics().first;
          final pos = m.getTangentForOffset((t * 40 * k + pi * 23 * k) % m.length)?.position;
          if (pos != null) {
            c.drawCircle(pos, 3.5 * k, _col(const Color(0x6600FFAA))..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * k));
            c.drawCircle(pos, 1.6 * k, _col(const Color(0xFFB6FFE4)));
          }
        }
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF00FFAA)), alpha: .55);
        _txt(c, NameBase.fill, 'f', midText,
            () => _lin(Offset(o.dx, 0), Offset(o.dx + w, 0), const [Color(0xFFB6FFE4), Color(0xFF00FFAA), Color(0xFF00C2FF)]));

      case NameDecoStyle.laserEdge:
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFFFF285A)), alpha: .7);
        _txt(c, NameBase.fill, 'f', midText, () => _col(Colors.white));
        final frame = _cut(box.deflate(.5), 5 * k);
        c.drawPath(frame, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x40FF285A));
        final per = 2 * (box.width + box.height);
        final head = t * per * .6;
        c.drawPath(_dash(frame, head, per * .22), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * k
          ..color = const Color(0x99FF2A5F)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * k));
        c.drawPath(_dash(frame, head, per * .22), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * k
          ..color = const Color(0xFFFF2A5F));
        c.drawPath(_dash(frame, head + per * .5, per * .22), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * k
          ..color = const Color(0xFFFFD1DD));

      case NameDecoStyle.neonTube:
        final n = (t * 12).floor() % 37;
        final flick = n == 0 || n == 2 ? .25 : 1.0;
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFFFF3DF2)), alpha: flick);
        _txt(c, NameBase.stroke, 's', midText, () => _col(const Color(0xFFFF3DF2)), alpha: flick);
        _txt(c, NameBase.thin, 't', midText, () => _col(const Color(0xFFFFD6FC)), alpha: flick);

      case NameDecoStyle.dataStream:
        final plate = _cut(box, 7 * k);
        c.drawPath(plate, _col(const Color(0x241E78FF)));
        c.drawPath(plate, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x9946A0FF));
        c.save();
        c.clipPath(plate);
        final cols = math.max(8, (box.width / (5.5 * k)).floor());
        final cell = 7 * k;
        final dot = Paint()..color = const Color(0xFF5AB4FF);
        for (var col = 0; col < cols; col++) {
          final cx = col * box.width / cols + 1.5 * k;
          final sp = (18 + (col * 7) % 13) * k;
          final oy = (t * sp + col * 11 * k) % (box.height + 20 * k) - 10 * k;
          for (var j = 0; j < 4; j++) {
            final bit = ((col * 3 + j + (t * 6).floor()) % 2) == 0;
            dot.color = Color.fromRGBO(90, 180, 255, .45 - j * .1);
            final y = oy - j * cell;
            // "0" = kotak kecil berongga, "1" = garis tegak (gaya biner mini).
            if (bit) {
              c.drawRect(Rect.fromLTWH(cx, y, 2.6 * k, 4 * k), dot..style = PaintingStyle.stroke..strokeWidth = .7 * k);
            } else {
              c.drawRect(Rect.fromLTWH(cx + .8 * k, y, 1 * k, 4 * k), dot..style = PaintingStyle.fill);
            }
          }
        }
        c.restore();
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF46A0FF)), alpha: .9);
        _txt(c, NameBase.fill, 'f', midText, () => _col(const Color(0xFFEAF4FF)));

      case NameDecoStyle.holoProjector:
        final cx = o.dx + w / 2, by = o.dy + th + 4 * k;
        c.drawPath(
          Path()
            ..moveTo(cx - 6 * k, by)
            ..lineTo(o.dx + w + 4 * k, o.dy)
            ..lineTo(o.dx - 4 * k, o.dy)
            ..close(),
          _lin(Offset(0, by), Offset(0, o.dy), const [Color(0x5950DCFF), Color(0x0050DCFF)]),
        );
        c.drawRect(Rect.fromCenter(center: Offset(cx, by), width: 14 * k, height: 2 * k), _col(const Color(0xFF4FD8FF)));
        final jit = math.sin(t * 50) > .92 ? 2 * k : 0.0;
        final a = .75 + .25 * math.sin(t * 9);
        final tr = midText & fill.size;
        c.saveLayer(tr.inflate(6 * k), Paint());
        _txt(c, NameBase.fill, 'r', midText.translate(-k - jit, 0), () => _col(const Color(0x99FF3C78)), alpha: a);
        _txt(c, NameBase.fill, 'b', midText.translate(k + jit, 0), () => _col(const Color(0xB33CC8FF)), alpha: a);
        _txt(c, NameBase.fill, 'f', midText, () => _col(const Color(0xF2DCFAFF)), alpha: a);
        final shift = (t * 20 * k) % (2 * k);
        for (var yy = tr.top + shift; yy < tr.bottom; yy += 2 * k) {
          c.drawRect(Rect.fromLTWH(tr.left - 3 * k, yy, tr.width + 6 * k, .8 * k),
              Paint()
                ..color = const Color(0x59000000)
                ..blendMode = BlendMode.dstOut);
        }
        c.restore();

      case NameDecoStyle.quantumCore:
        final cx = o.dx + w / 2;
        for (var r = 0; r < 2; r++) {
          c.save();
          c.translate(cx, cy);
          c.rotate(r == 1 ? .22 : -.22);
          final ov = Rect.fromCenter(center: Offset.zero, width: w + 20 * k, height: 18 * k);
          c.drawOval(ov, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(.8, k)
            ..color = const Color(0x59B98CFF));
          final ang = t * (r == 1 ? 2.2 : -1.7);
          final p = Offset(math.cos(ang) * ov.width / 2, math.sin(ang) * ov.height / 2);
          final glowC = r == 1 ? const Color(0xFFB98CFF) : const Color(0xFF5EE7FF);
          c.drawCircle(p, 4.5 * k, _col(glowC.withValues(alpha: .6))..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * k));
          c.drawCircle(p, 2 * k, _col(r == 1 ? Colors.white : const Color(0xFF5EE7FF)));
          c.restore();
        }
        final pulse = .5 + .5 * math.sin(t * 3);
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFFB98CFF)), alpha: .6 + .4 * pulse);
        _txt(c, NameBase.fill, 'f', midText,
            () => _lin(Offset(o.dx, 0), Offset(o.dx + w, 0), const [Color(0xFF5EE7FF), Color(0xFFB98CFF), Color(0xFFFF6AD5)]));
        _txt(c, NameBase.thin, 't', midText, () => _col(const Color(0x99FFFFFF)));

      case NameDecoStyle.synthwave:
        c.save();
        c.clipRect(box);
        c.drawRect(box, _lin(box.topCenter, box.bottomCenter, const [Color(0x00FF3CAC), Color(0x597828C8)]));
        final grid = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.6, .8 * k)
          ..color = const Color(0x8CFF50C8);
        final hz = cy + 2 * k;
        for (var i = 0; i < 4; i++) {
          final q = (i + (t * 1.2) % 1) / 4;
          final yy = hz + q * q * (box.bottom - hz);
          c.drawLine(Offset(0, yy), Offset(box.right, yy), grid);
        }
        for (var i = -6; i <= 6; i++) {
          c.drawLine(Offset(o.dx + w / 2 + i * 6 * k, hz), Offset(o.dx + w / 2 + i * 26 * k, box.bottom), grid);
        }
        c.restore();
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFFFF3CAC)), alpha: .8);
        final tr = midText & fill.size;
        _txt(c, NameBase.fill, 'f', midText, () => _lin(tr.topCenter, tr.bottomCenter,
            const [Color(0xFFFFE66D), Color(0xFFFF8A3D), Color(0xFFFF3CAC), Color(0xFFB05BFF)], const [0, .45, .55, 1]));

      case NameDecoStyle.mechaChrome:
        final plate = _cut(box, 5 * k);
        c.drawPath(plate, _col(const Color(0xFF1A1D24)));
        c.drawPath(plate, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF4A5160));
        final stripe = Rect.fromLTWH(box.right - 15 * k, 1, 13 * k, box.height - 2);
        c.save();
        c.clipRect(stripe);
        for (var i = -2; i < 6; i++) {
          c.drawPath(
            Path()
              ..moveTo(stripe.left + i * 6 * k, stripe.bottom)
              ..lineTo(stripe.left + i * 6 * k + 6 * k, stripe.bottom)
              ..lineTo(stripe.left + i * 6 * k + 16 * k, stripe.top)
              ..lineTo(stripe.left + i * 6 * k + 10 * k, stripe.top)
              ..close(),
            _col(i.isOdd ? const Color(0xFF111111) : const Color(0xFFFFC93C)),
          );
        }
        c.restore();
        final tr = midText & fill.size;
        c.saveLayer(tr.inflate(2), Paint());
        _txt(c, NameBase.fill, 'f', midText, () => _lin(tr.topCenter, tr.bottomCenter,
            const [Colors.white, Color(0xFFC9D2E0), Color(0xFF6C7688), Color(0xFFE6ECF5), Color(0xFF9AA6B8)],
            const [0, .45, .5, .75, 1]));
        final s = ((t * .4) % 1.5 - .25) * w + o.dx;
        c.drawRect(tr, _lin(Offset(s - 12 * k, 0), Offset(s + 12 * k, 0),
            const [Color(0x00FFFFFF), Color(0xE6FFFFFF), Color(0x00FFFFFF)])..blendMode = BlendMode.srcATop);
        c.restore();
        c.drawRect(Rect.fromLTWH(3 * k, 3 * k, 3 * k, 3 * k),
            _col(math.sin(t * 5) > 0 ? const Color(0xFFFF3B3B) : const Color(0xFF5A1A1A)));

      // ================================================= Seri 2 (tanpa latar)

      case NameDecoStyle.terminal:
        final n = (t * 10).floor() % 53;
        final flick = n == 0 ? .55 : 1.0;
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF39FF6A)), alpha: .7 * flick);
        _txt(c, NameBase.fill, 'f', midText, () => _col(const Color(0xFFB8FFC8)), alpha: flick);
        if ((t * 2).floor().isEven) {
          c.drawRect(Rect.fromLTWH(o.dx + w + 2 * k, o.dy + th * .78, 7 * k, 2 * k), _col(const Color(0xFF39FF6A)));
        }

      case NameDecoStyle.arcade:
        final tr = midText & fill.size;
        _txt(c, NameBase.fill, 'sh', midText.translate(1.6 * k, 1.6 * k), () => _col(const Color(0xFF3A1060)));
        _txt(c, NameBase.fill, 'f', midText, () => _lin(tr.topCenter, tr.bottomCenter,
            const [Color(0xFFFFF27A), Color(0xFFFFC93C), Color(0xFFFF7A1A)], const [0, .5, 1]));
        // Kilau koin berkedip di pojok.
        final sp = (t * 1.3) % 1;
        if (sp < .45) {
          final a = math.sin(sp / .45 * math.pi);
          final cpt = Offset(o.dx + w + 2 * k, o.dy + 1 * k);
          final r = 3.5 * k * a;
          final star = Paint()..color = Color.fromRGBO(255, 255, 255, a);
          c.drawRect(Rect.fromCenter(center: cpt, width: 1.2 * k, height: r * 2), star);
          c.drawRect(Rect.fromCenter(center: cpt, width: r * 2, height: 1.2 * k), star);
        }

      case NameDecoStyle.streetComic:
        final ang = math.sin(t * 2.2) * .035;
        final ctr = Offset(o.dx + w / 2, cy);
        c.save();
        c.translate(ctr.dx, ctr.dy);
        c.rotate(ang);
        c.translate(-ctr.dx, -ctr.dy);
        _txt(c, NameBase.fill, 'sh', midText.translate(2 * k, 2 * k), () => _col(const Color(0xFFFF3D8B)));
        _txt(c, NameBase.stroke, 's', midText, () => _col(const Color(0xFF111111)));
        _txt(c, NameBase.fill, 'f', midText, () => _col(const Color(0xFFFFF6D6)));
        c.restore();

      case NameDecoStyle.neonSign:
        final n = (t * 12).floor() % 41;
        final flick = n == 0 || n == 3 ? .3 : 1.0;
        final hue = .5 + .5 * math.sin(t * 1.4);
        final glowC = Color.lerp(const Color(0xFF00E5FF), const Color(0xFFFF3DF2), hue)!;
        _txt(c, NameBase.glow, 'g${(hue * 6).round()}', midText, () => _col(glowC), alpha: flick);
        _txt(c, NameBase.fill, 'f', midText, () => _col(const Color(0xFFF2FDFF)), alpha: .55 + .45 * flick);

      case NameDecoStyle.horrorDrip:
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF8A0000)), alpha: .8);
        final tr = midText & fill.size;
        _txt(c, NameBase.fill, 'f', midText,
            () => _lin(tr.topCenter, tr.bottomCenter, const [Color(0xFFFF4A3D), Color(0xFFB30000), Color(0xFF5A0000)]));
        // Tetes darah jatuh dari bawah huruf.
        final drip = Paint()..color = const Color(0xFFB30000);
        for (var i = 0; i < 4; i++) {
          final ph = (t * (.35 + _rnd(i, 3) * .25) + _rnd(i, 1)) % 1;
          final x = o.dx + w * (.12 + .25 * i + _rnd(i, 2) * .08);
          final y0 = o.dy + th * .82;
          final len = ph < .5 ? ph / .5 * 4 * k : 4 * k;
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - .9 * k, y0, 1.8 * k, len), Radius.circular(k)), drip);
          if (ph >= .5) {
            final fall = (ph - .5) / .5;
            drip.color = Color.fromRGBO(179, 0, 0, 1 - fall);
            c.drawCircle(Offset(x, y0 + 4 * k + fall * 5 * k), 1.3 * k, drip);
            drip.color = const Color(0xFFB30000);
          } else {
            c.drawCircle(Offset(x, y0 + len), 1.2 * k, drip);
          }
        }

      case NameDecoStyle.stencilOps:
        final tr = midText & fill.size;
        c.saveLayer(tr.inflate(3 * k), Paint());
        _txt(c, NameBase.fill, 'f', midText,
            () => _lin(tr.topCenter, tr.bottomCenter, const [Color(0xFFD8D2A0), Color(0xFF8C8A55), Color(0xFF5B5E33)]));
        final s = ((t * .5) % 1.4 - .2) * tr.width + tr.left;
        c.drawRect(tr.inflate(2), _lin(Offset(s - 10 * k, 0), Offset(s + 10 * k, 0),
            const [Color(0x0039FF6A), Color(0xCC39FF6A), Color(0x0039FF6A)])..blendMode = BlendMode.srcATop);
        c.restore();
        // Bidikan kecil berkedip di kanan.
        if (math.sin(t * 4) > -.3) {
          final ch = Offset(o.dx + w + 5 * k, cy);
          final cp = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(.8, k)
            ..color = const Color(0xFF39FF6A);
          c.drawCircle(ch, 3 * k, cp);
          c.drawLine(ch.translate(-5 * k, 0), ch.translate(-1.5 * k, 0), cp);
          c.drawLine(ch.translate(1.5 * k, 0), ch.translate(5 * k, 0), cp);
        }

      case NameDecoStyle.racer:
        // Garis kecepatan melesat ke kiri.
        final line = Paint()..strokeCap = StrokeCap.round;
        for (var i = 0; i < 5; i++) {
          final ph = (t * (1.6 + _rnd(i, 4)) + _rnd(i, 5)) % 1;
          final y = o.dy + th * (.2 + .15 * i);
          final x1 = o.dx - 1 * k - ph * 5 * k;
          final len = (3 + 5 * _rnd(i, 6)) * k * (1 - ph);
          line
            ..strokeWidth = math.max(.8, 1.2 * k)
            ..color = Color.fromRGBO(255, 150, 40, .9 * (1 - ph));
          c.drawLine(Offset(x1, y), Offset(x1 - len, y), line);
        }
        c.save();
        c.translate(0, cy);
        c.transform(Float64List.fromList([1, 0, 0, 0, -.22, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
        c.translate(0, -cy);
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFFFF6A00)), alpha: .7);
        _txt(c, NameBase.fill, 'f', midText, () => _lin(Offset(o.dx, 0), Offset(o.dx + w, 0),
            const [Color(0xFFFFF27A), Color(0xFFFF9A2A), Color(0xFFFF2E2E)]));
        c.restore();

      case NameDecoStyle.rgbGlitch:
        final j = math.sin(t * 37) > .55;
        final dx = j ? math.sin(t * 91) * 2.5 * k : 1.0 * k;
        _txt(c, NameBase.fill, 'r', midText.translate(-dx, 0), () => _col(const Color(0xCCFF2A5F)));
        _txt(c, NameBase.fill, 'b', midText.translate(dx, j ? k : 0), () => _col(const Color(0xCC2AE5FF)));
        _txt(c, NameBase.fill, 'f', midText, () => _col(const Color(0xFFF4F4FF)));

      case NameDecoStyle.royalGold:
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFFFFB800)), alpha: .55);
        final tr = midText & fill.size;
        c.saveLayer(tr.inflate(3 * k), Paint());
        _txt(c, NameBase.fill, 'f', midText, () => _lin(tr.topCenter, tr.bottomCenter,
            const [Color(0xFFFFF3B0), Color(0xFFFFC93C), Color(0xFFB8780A), Color(0xFFFFE08A)], const [0, .45, .7, 1]));
        final s = ((t * .45) % 1.4 - .2) * tr.width + tr.left;
        c.drawRect(tr.inflate(2), _lin(Offset(s - 14 * k, 0), Offset(s + 14 * k, 0),
            const [Color(0x00FFFFFF), Color(0xF2FFFFFF), Color(0x00FFFFFF)])..blendMode = BlendMode.srcATop);
        c.restore();
        for (var i = 0; i < 4; i++) {
          final ph = (t * .7 + _rnd(i, 7)) % 1;
          final a = math.sin(ph * math.pi);
          final pt = Offset(o.dx + w * _rnd(i, 8), o.dy + th * (i.isEven ? -.05 : 1.0));
          final r = 3 * k * a;
          final sp = Paint()..color = Color.fromRGBO(255, 240, 180, a);
          c.drawPath(
            Path()
              ..moveTo(pt.dx, pt.dy - r)
              ..lineTo(pt.dx + r * .25, pt.dy - r * .25)
              ..lineTo(pt.dx + r, pt.dy)
              ..lineTo(pt.dx + r * .25, pt.dy + r * .25)
              ..lineTo(pt.dx, pt.dy + r)
              ..lineTo(pt.dx - r * .25, pt.dy + r * .25)
              ..lineTo(pt.dx - r, pt.dy)
              ..lineTo(pt.dx - r * .25, pt.dy - r * .25)
              ..close(),
            sp,
          );
        }

      case NameDecoStyle.zenSpace:
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF9B5CFF)), alpha: .8);
        final tr = midText & fill.size;
        c.saveLayer(tr.inflate(3 * k), Paint());
        _txt(c, NameBase.fill, 'f', midText, () => _lin(tr.topLeft, tr.bottomRight,
            const [Color(0xFF7B4DFF), Color(0xFFC08CFF), Color(0xFF4F8BFF), Color(0xFFE07BFF)]));
        final star = Paint();
        for (var i = 0; i < 22; i++) {
          final tw = .35 + .65 * (.5 + .5 * math.sin(t * 3 + i * 1.7));
          star.color = Color.fromRGBO(255, 255, 255, tw);
          final x = tr.left + ((_rnd(i, 9) * tr.width + t * 5 * k) % tr.width);
          c.drawRect(Rect.fromLTWH(x, tr.top + _rnd(i, 10) * tr.height, 1.2 * k, 1.2 * k), star..blendMode = BlendMode.srcATop);
        }
        c.restore();
        _txt(c, NameBase.thin, 't', midText, () => _col(const Color(0x99E6D2FF)));

      case NameDecoStyle.auroraFlow:
        _txt(c, NameBase.glow, 'g', midText, () => _col(const Color(0xFF2EE6B5)), alpha: .6);
        final tr = midText & fill.size;
        c.saveLayer(tr.inflate(3 * k), Paint());
        _txt(c, NameBase.fill, 'f', midText, () => _col(Colors.white));
        final shift = (t * 30 * k) % (tr.width * 2);
        c.drawRect(tr.inflate(2), _lin(Offset(tr.left - shift, 0), Offset(tr.left - shift + tr.width * 2, 0),
            const [Color(0xFF5EFFB1), Color(0xFF5EC8FF), Color(0xFFB98CFF), Color(0xFF5EFFB1)], null, TileMode.repeated)
          ..blendMode = BlendMode.srcATop);
        c.restore();

      case NameDecoStyle.rainbowWave:
        final lift = math.sin(t * 2.5) * 1.2 * k;
        final mt = midText.translate(0, lift);
        final tr = mt & fill.size;
        _txt(c, NameBase.glow, 'g', mt, () => _col(const Color(0xFFFF7AD9)), alpha: .45);
        c.saveLayer(tr.inflate(3 * k), Paint());
        _txt(c, NameBase.fill, 'f', mt, () => _col(Colors.white));
        final shift = (t * 40 * k) % (tr.width * 1.5);
        c.drawRect(tr.inflate(2), _lin(Offset(tr.left - shift, 0), Offset(tr.left - shift + tr.width * 1.5, 0),
            const [Color(0xFFFF5E7E), Color(0xFFFFB45E), Color(0xFFFFF27A), Color(0xFF5EFFB1), Color(0xFF5EC8FF), Color(0xFFB98CFF), Color(0xFFFF5E7E)],
            null, TileMode.repeated)
          ..blendMode = BlendMode.srcATop);
        c.restore();
    }
  }

  @override
  bool shouldRepaint(_NameDecoPainter old) =>
      old.glyphs != glyphs || old.style != style || old.k != k || old.anim != anim || old.pad != pad;
}

/// Contoh untuk thumbnail kartu Decor.
class NameDecoPreview extends StatelessWidget {
  const NameDecoPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NameDecoText(name: 'ZENIME', style: NameDecoStyle.mechaChrome, fontSize: 18),
              SizedBox(height: 12),
              NameDecoText(name: 'ZENIME', style: NameDecoStyle.laserEdge, fontSize: 16),
              SizedBox(height: 12),
              NameDecoText(name: 'ZENIME', style: NameDecoStyle.quantumCore, fontSize: 15),
            ],
          ),
        ),
      ),
    );
  }
}
