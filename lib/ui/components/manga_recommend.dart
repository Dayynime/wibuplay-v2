import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anime_item.dart';
import '../redesign/z_kit.dart';
import 'common_components.dart';
import 'net_image.dart';
import 'poster_holder.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

// -----------------------------------------------------------------------------
// "Rekomendasi minggu ini": 4 anime disusun seperti satu halaman manga
// (panel miring, screentone, kotak narasi, balon kata, efek suara).
//
// - Pilihan diacak per MINGGU (seed = nomor minggu), jadi stabil selama
//   seminggu dan tidak lompat-lompat tiap kali Beranda dimuat ulang.
// - Panel "dibanting" masuk satu per satu saat section pertama kali terlihat.
// - Panel yang diketuk membesar jadi area hero halaman Detail, lalu Detail
//   muncul di atasnya (gambar yang sama, jadi menyambung).
// -----------------------------------------------------------------------------

/// Pilih 4 anime untuk minggu ini dari gabungan beberapa daftar Beranda.
List<AnimeItem> pickWeeklyRecommendations(List<List<AnimeItem>> sources) {
  final seen = <String>{};
  final pool = <AnimeItem>[];
  for (final list in sources) {
    for (final a in list) {
      final id = a.id;
      if (id == null || a.coverUrl.isEmpty || !seen.add(id)) continue;
      pool.add(a);
    }
  }
  if (pool.length < 4) return const [];
  final week = DateTime.now().difference(DateTime(2024, 1, 1)).inDays ~/ 7;
  pool.shuffle(math.Random(week));
  return pool.take(4).toList();
}

/// Bentuk panel: posisi di halaman (pecahan lebar, px tinggi) + sudut poligon
/// (pecahan ukuran panel).
class _PanelSpec {
  const _PanelSpec(this.left, this.top, this.width, this.height, this.poly, {this.right = false});

  final double left; // pecahan lebar isi halaman (diabaikan kalau right)
  final double top;
  final double width; // pecahan lebar isi halaman
  final double height;
  final List<Offset> poly;
  final bool right;
}

const double _pageH = 470;
const double _pad = 8;

const List<_PanelSpec> _panels = [
  _PanelSpec(0, 0, 1, 180, [Offset(0, 0), Offset(1, 0), Offset(1, .82), Offset(0, 1)]),
  _PanelSpec(0, 152, .56, 302, [Offset(0, .11), Offset(1, 0), Offset(.92, 1), Offset(0, 1)]),
  _PanelSpec(0, 142, .46, 150, [Offset(.14, .07), Offset(1, 0), Offset(1, 1), Offset(.07, .92)], right: true),
  _PanelSpec(0, 288, .46, 166, [Offset(.07, 0), Offset(1, .06), Offset(1, 1), Offset(0, 1)], right: true),
];

const List<String> _bubbles = ['Wajib\ntonton!', 'Lagi\nrame!', 'Bikin\nnagih!', 'Plot\ntwist!'];
const List<String> _sfx = ['ドン!', 'ゴゴゴ', 'バン!'];

class MangaRecommendSection extends StatefulWidget {
  const MangaRecommendSection({super.key, required this.items, required this.onAnimeClick});

  final List<AnimeItem> items;
  final ValueChanged<String> onAnimeClick;

  @override
  State<MangaRecommendSection> createState() => _MangaRecommendSectionState();
}

class _MangaRecommendSectionState extends State<MangaRecommendSection> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  ScrollPosition? _pos;
  bool _started = false;
  final List<GlobalKey> _panelKeys = List.generate(4, (_) => GlobalKey());
  bool _opening = false;

  int get _week => DateTime.now().difference(DateTime(2024, 1, 1)).inDays ~/ 7;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _in.value = 1;
    }
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _pos) {
      _pos?.removeListener(_check);
      _pos = p;
      _pos?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  /// Mulai animasi masuk saat bagian atas section sudah ~80% masuk layar.
  void _check() {
    if (_started || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    final y = box.localToGlobal(Offset.zero).dy;
    final h = MediaQuery.sizeOf(context).height;
    if (y < h * 0.8) {
      _started = true;
      _pos?.removeListener(_check);
      _in.forward();
    }
  }

  @override
  void dispose() {
    _pos?.removeListener(_check);
    _in.dispose();
    super.dispose();
  }

  Future<void> _open(int i) async {
    final a = widget.items[i];
    final id = a.id;
    if (id == null || _opening) return;
    HapticFeedback.selectionClick();
    final box = _panelKeys[i].currentContext?.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay;
    if (box == null || overlay == null || MediaQuery.disableAnimationsOf(context)) {
      PosterTransitionHolder.url = a.coverUrl;
      widget.onAnimeClick(id);
      return;
    }
    _opening = true;
    final from = box.localToGlobal(Offset.zero) & box.size;
    final size = MediaQuery.sizeOf(context);
    final to = Rect.fromLTWH(0, 0, size.width, 360 + MediaQuery.paddingOf(context).top);
    final url = _urlFor(i, a);
    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
    final entry = OverlayEntry(
      builder: (_) => _ZoomPanel(anim: ctrl, from: from, to: to, poly: _panels[i].poly, url: url),
    );
    overlay.insert(entry);
    await ctrl.forward();
    // Detail terbuka di atas panel yang sudah memenuhi area hero; hero Detail
    // memakai gambar yang sama, jadi peralihannya menyambung.
    PosterTransitionHolder.url = url;
    PosterTransitionHolder.zoomedIn = true;
    widget.onAnimeClick(id);
    Timer(const Duration(milliseconds: 600), () {
      entry.remove();
      ctrl.dispose();
      _opening = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.length < 4) return const SizedBox.shrink();
    final bubble = _bubbles[_week % _bubbles.length];
    final sfx = _sfx[_week % _sfx.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        const SectionHeader(title: 'Rekomendasi Minggu Ini', eyebrow: '今週のおすすめ'),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            height: _pageH,
            decoration: BoxDecoration(
              color: const Color(0xFF121722),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x0FFFFFFF)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  const Positioned(top: 0, right: 0, width: 200, height: 220, child: ZScreentone(opacity: 0.08, spacing: 5)),
                  Padding(
                    padding: const EdgeInsets.all(_pad),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        return Stack(
                          children: [
                            for (var i = 0; i < 4; i++) _panel(i, w, items[i], bubble: bubble, sfx: sfx),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel(int i, double pageW, AnimeItem a, {required String bubble, required String sfx}) {
    final spec = _panels[i];
    final w = pageW * spec.width;
    final h = spec.height;
    final left = spec.right ? pageW - w : pageW * spec.left;
    final url = _urlFor(i, a);
    final start = i * 220;

    final caption = _Caption(title: a.title ?? 'Anime', sub: _sub(a));

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.surfaceVariantDark),
        NetImage(url, alignment: i == 1 ? const Alignment(0, -0.4) : const Alignment(0, -0.3)),
        const _PanelTone(),
        if (i == 1) _SpeedLines(anim: _in),
        if (i == 0) const Positioned(right: 10, top: 10, child: ZChip('Pilihan', tone: ZTone.brand)),
        if (i == 1) Positioned(left: 12, top: h * 0.17, child: _Bubble(bubble)),
        if (i == 2) Positioned(right: 8, top: 12, child: _Sfx(text: sfx, anim: _in)),
        Positioned(
          left: i == 0 || i == 1 ? 10 : null,
          right: i >= 2 ? 8 : null,
          top: i == 0 ? 10 : null,
          bottom: i == 0 ? null : (i == 2 ? h * 0.12 : 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: i == 0 ? w * 0.6 : w - 18),
            child: caption,
          ),
        ),
        CustomPaint(painter: _PanelBorder(spec.poly)),
      ],
    );

    content = ClipPath(clipper: _PolyClip(spec.poly), child: content);

    return Positioned(
      left: left,
      top: spec.top,
      width: w,
      height: h,
      child: AnimatedBuilder(
        animation: _in,
        child: GestureDetector(
          key: _panelKeys[i],
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(i),
          child: content,
        ),
        builder: (context, child) {
          final total = _in.duration!.inMilliseconds;
          final a0 = start / total, a1 = (start + 380) / total;
          final t = Curves.easeOutBack.transform(((_in.value - a0) / (a1 - a0)).clamp(0.0, 1.0));
          final f = ((_in.value - a0) / ((a1 - a0) * 0.6)).clamp(0.0, 1.0);
          return Opacity(opacity: f, child: Transform.scale(scale: 1.18 - 0.18 * t, child: child));
        },
      ),
    );
  }

  /// Panel 0, 2, 3 lanskap (cover); panel 1 tinggi (poster).
  static String _urlFor(int i, AnimeItem a) => i == 1 && a.posterUrl.isNotEmpty ? a.posterUrl : a.coverUrl;

  static String _sub(AnimeItem a) {
    final genre = (a.genre ?? '').split(',').first.trim();
    final extra = !_blank(a.status) ? a.status!.trim() : (a.year ?? a.type ?? '').trim();
    return [genre, extra].where((e) => e.isNotEmpty).join(' · ');
  }
}

// ----------------------------------------------------------------- potongan

class _PolyClip extends CustomClipper<Path> {
  const _PolyClip(this.poly);

  final List<Offset> poly;

  @override
  Path getClip(Size s) => Path()..addPolygon([for (final p in poly) Offset(p.dx * s.width, p.dy * s.height)], true);

  @override
  bool shouldReclip(_PolyClip old) => old.poly != poly;
}

/// Garis tepi panel: putih tipis (manga "tinta terbalik" di latar gelap).
class _PanelBorder extends CustomPainter {
  const _PanelBorder(this.poly);

  final List<Offset> poly;

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xD9F5F5F7);
    final pts = [for (final o in poly) Offset(o.dx * s.width, o.dy * s.height)];
    // Sedikit ke dalam supaya garis tidak terpotong klip.
    final cx = s.width / 2, cy = s.height / 2;
    final inset = [for (final o in pts) Offset(o.dx + (cx - o.dx).sign * 0.8, o.dy + (cy - o.dy).sign * 0.8)];
    c.drawPath(Path()..addPolygon(inset, true), p);
  }

  @override
  bool shouldRepaint(_PanelBorder old) => old.poly != poly;
}

/// Screentone gelap di bagian bawah panel (bayangan ala manga).
class _PanelTone extends StatelessWidget {
  const _PanelTone();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xFF000000)],
            stops: [0.35, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: const CustomPaint(painter: _DotsPainter(), size: Size.infinite),
        ),
      );
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter();

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0xA60B0E14);
    for (double y = 2.5; y < s.height; y += 5) {
      for (double x = 2.5; x < s.width; x += 5) {
        c.drawCircle(Offset(x, y), 1.1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => false;
}

class _Caption extends StatelessWidget {
  const _Caption({required this.title, required this.sub});

  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
      decoration: const BoxDecoration(
        color: Color(0xDB0B0E14),
        border: Border(left: BorderSide(color: AppColors.accentViolet, width: 3)),
        borderRadius: BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, height: 1.25),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

/// Balon kata putih dengan ekor.
class _Bubble extends StatelessWidget {
  const _Bubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _BubblePainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 15),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF111111), fontSize: 11, fontWeight: FontWeight.w900, height: 1.1),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter();

  @override
  void paint(Canvas c, Size s) {
    final body = Rect.fromLTWH(0, 0, s.width, s.height - 6);
    final merged = Path.combine(PathOperation.union, Path()..addOval(body), Path()..addPolygon([
          Offset(s.width * 0.28, body.bottom - 4),
          Offset(s.width * 0.22, s.height),
          Offset(s.width * 0.45, body.bottom - 2),
        ], true));
    c.drawPath(merged, Paint()..color = Colors.white);
    c.drawPath(
      merged,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF111111),
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => false;
}

/// Efek suara: putih bergaris merah, sempat membesar sebentar.
class _Sfx extends StatelessWidget {
  const _Sfx({required this.text, required this.anim});

  final String text;
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    final style = ZFont.jp(size: 28, weight: FontWeight.w900, color: Colors.white, letterSpacing: -1);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        // Denyut di 0.62..0.8 timeline masuk.
        final k = ((anim.value - 0.62) / 0.18).clamp(0.0, 1.0);
        return Transform.rotate(
          angle: -0.17,
          child: Transform.scale(scale: 1 + 0.35 * math.sin(k * math.pi), child: child),
        );
      },
      child: Stack(
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: style.fontFamily,
              fontFamilyFallback: style.fontFamilyFallback,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              height: 1.25,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 5
                ..strokeJoin = StrokeJoin.round
                ..color = AppColors.accentViolet,
            ),
          ),
          Text(text, style: style),
        ],
      ),
    );
  }
}

/// Garis konsentrasi (集中線) yang berkilat sebentar.
class _SpeedLines extends StatelessWidget {
  const _SpeedLines({required this.anim});

  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final v = anim.value;
          // Muncul 0.55..0.62, bertahan, hilang 0.85..1.
          final o = v < 0.55 ? 0.0 : v < 0.62 ? (v - 0.55) / 0.07 : v < 0.85 ? 1.0 : (1 - (v - 0.85) / 0.15);
          if (o <= 0) return const SizedBox.shrink();
          return Opacity(opacity: o.clamp(0.0, 1.0), child: const CustomPaint(painter: _SpeedPainter(), size: Size.infinite));
        },
      ),
    );
  }
}

class _SpeedPainter extends CustomPainter {
  const _SpeedPainter();

  @override
  void paint(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final r1 = math.sqrt(s.width * s.width + s.height * s.height) / 2;
    final rnd = math.Random(7);
    for (var i = 0; i < 64; i++) {
      final ang = i / 64 * math.pi * 2 + rnd.nextDouble() * 0.05;
      final r0 = r1 * (0.42 + rnd.nextDouble() * 0.22);
      final d = Offset(math.cos(ang), math.sin(ang));
      final p = Paint()
        ..color = const Color(0xCCFFFFFF)
        ..strokeWidth = 0.6 + rnd.nextDouble() * 1.4
        ..strokeCap = StrokeCap.round;
      c.drawLine(ctr + d * r0, ctr + d * r1, p);
    }
  }

  @override
  bool shouldRepaint(_SpeedPainter old) => false;
}

/// Panel yang membesar dari posisinya ke area hero Detail.
class _ZoomPanel extends StatelessWidget {
  const _ZoomPanel({required this.anim, required this.from, required this.to, required this.poly, required this.url});

  final Animation<double> anim;
  final Rect from;
  final Rect to;
  final List<Offset> poly;
  final String url;

  static const List<Offset> _rect = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, child) {
          final e = Curves.easeInOutCubic.transform(anim.value);
          final r = Rect.lerp(from, to, e)!;
          final shape = [for (var i = 0; i < 4; i++) Offset.lerp(poly[i], _rect[i], e)!];
          return Stack(
            children: [
              Positioned.fromRect(
                rect: r,
                child: ClipPath(clipper: _PolyClip(shape), child: child),
              ),
            ],
          );
        },
        child: ColoredBox(
          color: AppColors.surfaceVariantDark,
          child: NetImage(url, alignment: Alignment.topCenter),
        ),
      ),
    );
  }
}
