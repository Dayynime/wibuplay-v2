import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/lite_mode.dart';

/// Slide promosi Zenime Town di carousel Beranda.
///
/// Latar = cuplikan asli dari Zenime Town (Plaza & Pulau Pancing) yang
/// bergantian dengan efek zoom pelan. Di adegan pulau, ikan mitos asli dari
/// game melompat keluar dari air. Animasi cuma jalan saat slide terlihat.
class HeroTownSlide extends StatefulWidget {
  const HeroTownSlide({super.key, required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  State<HeroTownSlide> createState() => _HeroTownSlideState();
}

const _cycle = 9.0; // detik: 4,5 dtk Plaza + 4,5 dtk Pulau Pancing
const _half = _cycle / 2;
const _scenes = ['assets/town_promo/plaza.webp', 'assets/town_promo/island.webp'];
const _sceneNames = ['Plaza', 'Pulau Pancing'];
const _fish = [
  'assets/town_promo/fish_nagakidul.webp',
  'assets/town_promo/fish_kraken.webp',
  'assets/town_promo/fish_sakura.webp',
  'assets/town_promo/fish_leviathan.webp',
];

class _HeroTownSlideState extends State<HeroTownSlide> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 9000));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant HeroTownSlide old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && !_c.isAnimating) {
      _c.liteRepeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final a in [..._scenes, ..._fish]) {
      precacheImage(AssetImage(a), context);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text,
            style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
      );

  Widget _feature(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _scene(String asset, double opacity, double scale, Offset shift) => Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(
          offset: shift,
          child: Transform.scale(
            scale: scale,
            child: Image.asset(asset, fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * _cycle;
          final cur = t < _half ? 0 : 1;
          final local = t - cur * _half; // 0..4,5
          final fade = (local / 0.8).clamp(0.0, 1.0).toDouble();
          final k = local / _half;
          final zoom = 1.06 + 0.06 * k;
          final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2 / 1.6);
          return LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Latar: adegan sebelumnya diam di bawah, adegan aktif memudar masuk + zoom pelan.
                Positioned.fill(child: _scene(_scenes[1 - cur], 1, 1.12, Offset.zero)),
                Positioned.fill(
                  child: _scene(_scenes[cur], fade, zoom, Offset((cur == 0 ? 6 : -6) * k, -3 * k)),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x590B0E14),
                        Color(0x000B0E14),
                        Color(0x260B0E14),
                        Color(0xC70B0E14),
                        Color(0xF50B0E14),
                      ],
                      stops: [0, 0.28, 0.45, 0.72, 1],
                    ),
                  ),
                ),
                if (cur == 1) ..._leapingFish(local, w, h),
                Positioned(
                  left: 14,
                  top: 12,
                  child: Row(children: [
                    _chip('BARU', const Color(0xFFFF3B5C), Colors.white),
                    const SizedBox(width: 6),
                    _chip('BETA', const Color(0xFFFFD84D), const Color(0xFF3B2A06)),
                  ]),
                ),
                Positioned(
                  right: 12,
                  top: 11,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey(cur),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.place_rounded, size: 12, color: Color(0xFFFF5C6E)),
                        const SizedBox(width: 3),
                        Text(_sceneNames[cur],
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 14,
                  bottom: 13,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFFF7D1), Color(0xFFFFD24A), Color(0xFFFF9F1C)],
                          stops: [0, 0.55, 1],
                        ).createShader(r),
                        child: const Text(
                          'ZENIME TOWN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            shadows: [
                              Shadow(color: Color(0xFF4A2A00), offset: Offset(0, 2)),
                              Shadow(color: Color(0x59FFBE3C), blurRadius: 10),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Dunia pixel buat nongkrong bareng user Zenime',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Color(0xFFE6E9F0), fontSize: 12),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(children: [
                                _feature(Icons.mic_rounded, 'Ngobrol'),
                                const SizedBox(width: 6),
                                _feature(Icons.phishing_rounded, 'Mancing'),
                                const SizedBox(width: 6),
                                _feature(Icons.sports_esports_rounded, 'Mabar'),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFFFE066), Color(0xFFFFB52B)],
                              ),
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: [
                                const BoxShadow(color: Color(0xFFC9820C), offset: Offset(0, 3)),
                                BoxShadow(
                                  color: const Color(0xFFFFC83C).withValues(alpha: 0.35 + 0.35 * pulse),
                                  blurRadius: 6 + 10 * pulse,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Main',
                                    style: TextStyle(
                                        color: Color(0xFF3B2A06), fontSize: 13, fontWeight: FontWeight.w900)),
                                Icon(Icons.play_arrow_rounded, size: 18, color: Color(0xFF3B2A06)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          });
        },
      ),
    );
  }

  /// Ikan mitos melompat dari air (sisi kanan) + cipratan saat keluar & masuk.
  List<Widget> _leapingFish(double local, double w, double h) {
    const jump = 2.2;
    if (local < 0.6) return const [];
    final j = (local % jump) / jump;
    if (j >= 0.7) return const [];
    final q = j / 0.7;
    final fi = (local / jump).floor() % _fish.length;
    final fw = w * 0.22;
    final x = w * (0.66 + 0.24 * q), y = h * (0.52 - 0.32 * math.sin(q * math.pi));
    return [
      Positioned(
        left: x - fw / 2,
        top: y - fw * 0.31,
        width: fw,
        height: fw * 0.62,
        child: Transform.rotate(
          angle: -0.8 + 1.6 * q,
          child: Image.asset(_fish[fi], filterQuality: FilterQuality.none, gaplessPlayback: true),
        ),
      ),
      Positioned.fill(child: CustomPaint(painter: _SplashPainter(q))),
    ];
  }
}

class _SplashPainter extends CustomPainter {
  _SplashPainter(this.q);

  final double q;

  @override
  bool shouldRepaint(covariant _SplashPainter o) => o.q != q;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (exit, xx) in [(false, 0.66), (true, 0.90)]) {
      final d = exit ? q - 0.85 : 0.15 - q;
      if (d <= 0) continue;
      final a = (d / 0.15).clamp(0.0, 1.0).toDouble();
      final p = Paint()..color = const Color(0xFFDCF0FF).withValues(alpha: a);
      for (var n = 0; n < 7; n++) {
        canvas.drawCircle(
          Offset(size.width * xx + math.cos(n * 0.9) * size.width * 0.035 * (1.3 - a),
              size.height * 0.53 - (math.sin(n * 1.7)).abs() * size.height * 0.07 * (1.2 - a)),
          size.width * 0.006,
          p,
        );
      }
    }
  }
}
