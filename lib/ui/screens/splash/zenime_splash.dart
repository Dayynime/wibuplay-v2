import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/app_colors.dart';

/// Splash beranimasi gaya "tinta" (terinspirasi splash Wibuku), sekali jalan
/// ~2,2 detik:
///  1. Logo Z "dilukis" miring dari kiri-atas ke kanan-bawah, ujung kuas
///     bercahaya mengikuti.
///  2. Tetes tinta ungu/putih meletup dari dua ujung Z lalu jatuh.
///  3. Tulisan ZENIME muncul di bawah logo, jarak huruf merapat
///     (matikan dengan [showTitle] = false untuk animasi Z saja).
///  4. Kilau lewat di atas logo, teks versi muncul.
/// Setelah selesai [onFinished] dipanggil; kalau app masih sibuk (cek update)
/// logo tetap tampil dengan denyut cahaya pelan.
class ZenimeSplash extends StatefulWidget {
  const ZenimeSplash({super.key, this.onFinished, this.showTitle = true});

  final VoidCallback? onFinished;

  /// Tampilkan tulisan ZENIME di bawah logo.
  final bool showTitle;

  /// Lama animasi utama.
  static const Duration duration = Duration(milliseconds: 2200);

  @override
  State<ZenimeSplash> createState() => _ZenimeSplashState();
}

class _ZenimeSplashState extends State<ZenimeSplash> with TickerProviderStateMixin {
  static const _ink = Color(0xFFF2EEF8);
  static const _purple = Color(0xFF9B5CFF);

  late final AnimationController _c = AnimationController(vsync: this, duration: ZenimeSplash.duration);
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  late final Animation<double> _brush =
      CurvedAnimation(parent: _c, curve: const Interval(0.05, 0.52, curve: Curves.easeInOutCubic));
  late final Animation<double> _title =
      CurvedAnimation(parent: _c, curve: const Interval(0.48, 0.80, curve: Curves.easeOutCubic));
  late final Animation<double> _drops = CurvedAnimation(parent: _c, curve: const Interval(0.42, 1.0));
  late final Animation<double> _shine =
      CurvedAnimation(parent: _c, curve: const Interval(0.66, 0.92, curve: Curves.easeInOut));
  late final Animation<double> _ver =
      CurvedAnimation(parent: _c, curve: const Interval(0.70, 0.90, curve: Curves.easeOut));

  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = 'App ${p.version} (${p.buildNumber})');
    }).catchError((_) {});
    _c.forward().whenComplete(() {
      if (!mounted) return;
      _idle.repeat(reverse: true);
      widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final logo = math.min(190.0, w * 0.46);
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: _ink,
          fontSize: 30,
          fontWeight: FontWeight.w900,
        );
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: AnimatedBuilder(
        animation: Listenable.merge([_c, _idle]),
        builder: (context, _) {
          final idle = Curves.easeInOut.transform(_idle.value);
          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo + kuas + tetes tinta + kilau.
                    SizedBox(
                      width: logo * 1.6,
                      height: logo * 1.5,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Cahaya lembut di belakang logo (berdenyut saat menunggu).
                          Opacity(
                            opacity: (_brush.value * (0.55 + 0.25 * idle)).clamp(0.0, 1.0),
                            child: Container(
                              width: logo * 1.1,
                              height: logo * 1.1,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [
                                  _purple.withValues(alpha: 0.28),
                                  _purple.withValues(alpha: 0.0),
                                ]),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: logo,
                            height: logo,
                            child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (rect) {
                                final p = _brush.value;
                                return LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: const [Colors.white, Colors.white, Colors.transparent],
                                  stops: [
                                    0,
                                    (p * 1.2 - 0.2).clamp(0.0, 1.0),
                                    (p * 1.2).clamp(0.0, 1.0),
                                  ],
                                ).createShader(rect);
                              },
                              child: Image.asset('assets/images/logo_splash.png', fit: BoxFit.contain),
                            ),
                          ),
                          // Kilau melintas setelah logo utuh.
                          if (_shine.value > 0 && _shine.value < 1)
                            SizedBox(
                              width: logo,
                              height: logo,
                              child: ShaderMask(
                                blendMode: BlendMode.srcATop,
                                shaderCallback: (rect) {
                                  final s = _shine.value * 1.6 - 0.3;
                                  return LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withValues(alpha: 0),
                                      Colors.white.withValues(alpha: 0.55),
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                    stops: [
                                      (s - 0.12).clamp(0.0, 1.0),
                                      s.clamp(0.0, 1.0),
                                      (s + 0.12).clamp(0.0, 1.0),
                                    ],
                                  ).createShader(rect);
                                },
                                child: Image.asset('assets/images/logo_splash.png', fit: BoxFit.contain),
                              ),
                            ),
                          // Ujung kuas + tetes tinta.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _InkPainter(
                                  brush: _brush.value,
                                  drops: _drops.value,
                                  logo: logo,
                                  ink: _ink,
                                  purple: _purple,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.showTitle)
                      Opacity(
                        opacity: _title.value,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - _title.value)),
                          child: Text(
                            'ZENIME',
                            style: titleStyle?.copyWith(letterSpacing: 8 + 14 * (1 - _title.value)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 40 + MediaQuery.paddingOf(context).bottom,
                child: Opacity(
                  opacity: _ver.value,
                  child: Text(
                    _version,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Ujung kuas bercahaya yang menyapu diagonal + tetes tinta dengan gravitasi.
/// Pola tetes memakai seed tetap supaya sama tiap buka app.
class _InkPainter extends CustomPainter {
  _InkPainter({required this.brush, required this.drops, required this.logo, required this.ink, required this.purple});

  final double brush, drops, logo;
  final Color ink, purple;

  static final List<_Drop> _list = () {
    final r = math.Random(11);
    return List.generate(26, (i) {
      // Separuh dari ujung kiri-bawah Z, separuh dari ujung kanan-atas.
      final fromBottom = i.isEven;
      final base = fromBottom ? -math.pi * 0.75 : -math.pi * 0.25;
      final ang = base + (r.nextDouble() - 0.5) * 1.3;
      final speed = 70 + r.nextDouble() * 120;
      return _Drop(
        fromBottom: fromBottom,
        vx: math.cos(ang) * speed,
        vy: math.sin(ang) * speed,
        size: 1.4 + r.nextDouble() * 3.6,
        delay: r.nextDouble() * 0.3,
        white: r.nextDouble() < 0.4,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final half = logo / 2;

    // Ujung kuas: titik cahaya di tepi sapuan, bergerak dari kiri-atas ke kanan-bawah.
    if (brush > 0.02 && brush < 0.98) {
      final p = brush * 1.2 - 0.1;
      final tip = Offset(c.dx - half + logo * p, c.dy - half + logo * p);
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.9),
          purple.withValues(alpha: 0.5),
          purple.withValues(alpha: 0),
        ], stops: const [0, 0.35, 1])
            .createShader(Rect.fromCircle(center: tip, radius: 28));
      canvas.drawCircle(tip, 28, glow);
    }

    if (drops <= 0) return;
    final paint = Paint();
    final tipBottom = Offset(c.dx - half * 0.72, c.dy + half * 0.62);
    final tipTop = Offset(c.dx + half * 0.72, c.dy - half * 0.55);
    for (final d in _list) {
      final lt = ((drops - d.delay) / (1 - d.delay)).clamp(0.0, 1.0);
      if (lt <= 0) continue;
      final sec = lt * 1.1;
      final o = d.fromBottom ? tipBottom : tipTop;
      final x = o.dx + d.vx * sec;
      final y = o.dy + d.vy * sec + 0.5 * 300 * sec * sec;
      final fade = lt < 0.65 ? 1.0 : 1 - (lt - 0.65) / 0.35;
      paint.color = (d.white ? ink : purple).withValues(alpha: fade.clamp(0.0, 1.0));
      final angle = math.atan2(d.vy + 300 * sec, d.vx);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: d.size * 2.3, height: d.size * 1.3), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_InkPainter o) => o.brush != brush || o.drops != drops || o.logo != logo;
}

class _Drop {
  const _Drop({
    required this.fromBottom,
    required this.vx,
    required this.vy,
    required this.size,
    required this.delay,
    required this.white,
  });
  final bool fromBottom, white;
  final double vx, vy, size, delay;
}
