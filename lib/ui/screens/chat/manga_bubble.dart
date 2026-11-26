import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../redesign/z_kit.dart';

// -----------------------------------------------------------------------------
// Bubble chat Premium gaya balon kata manga:
//  - latar krem, teks tinta gelap, ekor runcing ke arah avatar;
//  - pesan yang BARU masuk "menyebar" dari pojok ekor seperti tetesan tinta;
//  - efek suara kecil (ドン, バン, ...) menempel di pojok atas.
// Nama + badge tetap di atas pelat gelap supaya dekorasi nama tetap terbaca.
// -----------------------------------------------------------------------------

const Color kMangaPaper = Color(0xFFF4F1EA);
const Color kMangaInk = Color(0xFF16181D);
const Color kMangaInkSoft = Color(0xFF5B5F68);

const List<String> _sfxWords = ['ドン', 'バン', 'ドキッ', 'ゴゴ'];

/// Pesan dianggap "baru masuk" kalau umurnya < 15 detik saat pertama tampil.
bool mangaIsFresh(DateTime? t) => t != null && DateTime.now().difference(t).inSeconds.abs() < 15;

class MangaBubbleFrame extends StatefulWidget {
  const MangaBubbleFrame({
    super.key,
    required this.child,
    required this.mine,
    required this.fresh,
    required this.seed,
  });

  final Widget child;
  final bool mine;
  final bool fresh;

  /// Penentu kata efek suara (mis. id pesan) supaya tidak berubah tiap build.
  final int seed;

  @override
  State<MangaBubbleFrame> createState() => _MangaBubbleFrameState();
}

class _MangaBubbleFrameState extends State<MangaBubbleFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.fresh && !MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = _sfxWords[widget.seed.abs() % _sfxWords.length];
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final spread = Curves.easeOutCubic.transform(t);
        // Efek suara muncul belakangan sambil memantul.
        final s = Curves.easeOutBack.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            ClipPath(
              clipper: _InkClip(spread, fromRight: widget.mine),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  child!,
                  // Screentone tipis di pojok atas seberang ekor.
                  Positioned(
                    top: 0,
                    right: widget.mine ? null : 0,
                    left: widget.mine ? 0 : null,
                    width: 70,
                    height: 40,
                    child: const IgnorePointer(child: _CornerTone()),
                  ),
                ],
              ),
            ),
            // Ekor runcing ke arah avatar (bawah).
            Positioned(
              bottom: 10,
              left: widget.mine ? null : -7,
              right: widget.mine ? -7 : null,
              child: Opacity(
                opacity: t < 0.15 ? t / 0.15 : 1,
                child: CustomPaint(size: const Size(9, 12), painter: _TailPainter(widget.mine)),
              ),
            ),
            Positioned(
              top: -12,
              right: widget.mine ? null : -6,
              left: widget.mine ? -6 : null,
              child: IgnorePointer(
                child: Opacity(
                  opacity: s.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: widget.mine ? -0.2 : 0.2,
                    child: Transform.scale(scale: 0.4 + 0.6 * s, child: _Sfx(word)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Lingkaran tinta yang membesar dari pojok bawah sisi avatar.
class _InkClip extends CustomClipper<Path> {
  const _InkClip(this.p, {required this.fromRight});

  final double p;
  final bool fromRight;

  @override
  Path getClip(Size s) {
    if (p >= 1) return Path()..addRect(Offset.zero & s);
    final origin = Offset(fromRight ? s.width : 0, s.height);
    final r = math.sqrt(s.width * s.width + s.height * s.height) * p * 1.05;
    // Tepi tinta sedikit bergelombang supaya tidak terlihat seperti lingkaran CSS.
    final path = Path();
    const n = 36;
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final wob = 1 + 0.06 * math.sin(a * 7 + p * 9);
      final pt = origin + Offset(math.cos(a), math.sin(a)) * r * wob;
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_InkClip old) => old.p != p || old.fromRight != fromRight;
}

class _TailPainter extends CustomPainter {
  const _TailPainter(this.mine);

  final bool mine;

  @override
  void paint(Canvas c, Size s) {
    final path = mine
        ? (Path()
          ..moveTo(0, 0)
          ..lineTo(s.width, s.height * 0.75)
          ..lineTo(0, s.height)
          ..close())
        : (Path()
          ..moveTo(s.width, 0)
          ..lineTo(0, s.height * 0.75)
          ..lineTo(s.width, s.height)
          ..close());
    c.drawPath(path, Paint()..color = kMangaPaper);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.mine != mine;
}

class _CornerTone extends StatelessWidget {
  const _CornerTone();

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => const RadialGradient(
          center: Alignment.topRight,
          radius: 1.2,
          colors: [Color(0xFF000000), Color(0x00000000)],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: const CustomPaint(painter: _ToneDots(), size: Size.infinite),
      );
}

class _ToneDots extends CustomPainter {
  const _ToneDots();

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0x2E16181D);
    for (double y = 2; y < s.height; y += 4.5) {
      for (double x = 2; x < s.width; x += 4.5) {
        c.drawCircle(Offset(x, y), 0.9, p);
      }
    }
  }

  @override
  bool shouldRepaint(_ToneDots old) => false;
}

class _Sfx extends StatelessWidget {
  const _Sfx(this.word);

  final String word;

  @override
  Widget build(BuildContext context) {
    final base = ZFont.jp(size: 13, weight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5);
    return Stack(
      children: [
        Text(
          word,
          style: TextStyle(
            fontFamily: base.fontFamily,
            fontFamilyFallback: base.fontFamilyFallback,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.2,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.4
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.accentViolet,
          ),
        ),
        Text(word, style: base.copyWith(height: 1.2)),
      ],
    );
  }
}
