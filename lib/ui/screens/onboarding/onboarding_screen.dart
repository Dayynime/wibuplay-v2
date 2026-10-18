import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../components/net_image.dart';
import '../auth/login_posters.dart';

// -----------------------------------------------------------------------------
// Port OnboardingScreen.kt Zenime.
// - Warna slide sengaja hardcode (brand), tiap slide punya pasangan aksen;
//   background, indikator, dan tombol berubah mulus (lerp) saat di-swipe.
// - Ilustrasi digambar pakai widget Flutter, hanya slide 1 yang memakai poster
//   jaringan (kLoginPosters); yang lain tanpa aset tambahan.
// -----------------------------------------------------------------------------

const double _stage = 300;
const Cubic _backOut = Cubic(0.34, 1.56, 0.64, 1.0);
const Color _gold = Color(0xFFFFB020);

// Poster asli untuk slide Komik & Donghua (Douluo Dalu: donghua dan manhua-nya).
// CDN publik MyAnimeList, cuma di-link seperti kLoginPosters, tidak di-bundle.
const String _kDonghuaPoster = 'https://cdn.myanimelist.net/images/anime/1438/101531l.jpg';
const String _kComicPoster = 'https://cdn.myanimelist.net/images/manga/4/221353l.jpg';

class _Slide {
  const _Slide(this.title, this.highlight, this.desc, this.a, this.b);

  final String title;
  final String highlight;
  final String desc;
  final Color a;
  final Color b;
}

const List<_Slide> _slides = [
  _Slide(
    'Nonton Anime Tanpa Batas',
    'Tanpa Batas',
    'Ribuan judul favoritmu siap ditonton langsung dari HP Android, kapan aja.',
    Color(0xFFE4344A),
    Color(0xFF9333EA),
  ),
  _Slide(
    'Download & Nonton Offline',
    'Offline',
    'Simpan episode favorit, terus tonton tanpa kuota di mana pun kamu berada.',
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
  ),
  _Slide(
    'Komik & Donghua Juga Ada',
    'Donghua',
    'Baca komik favoritmu dan nonton donghua terbaru, semua ada di satu aplikasi.',
    Color(0xFF10B981),
    Color(0xFF06B6D4),
  ),
  _Slide(
    'Ngobrol Bareng, Gabung Clan',
    'Clan',
    'Chat Global, tambah teman, dan bikin Clan bareng sesama penonton.',
    Color(0xFFA855F7),
    Color(0xFFEC4899),
  ),
  _Slide(
    'Naik Level, Jadi Legenda',
    'Legenda',
    'Kumpulin XP tiap nonton dan panjat Leaderboard bareng yang lain.',
    Color(0xFFF59E0B),
    Color(0xFFE4344A),
  ),
  _Slide(
    'Upgrade ke Premium',
    'Premium',
    'Kualitas sampai 1080p, tanpa iklan, dan XP nonton dobel biar makin puas dan naik level makin cepat.',
    Color(0xFFFFC53D),
    Color(0xFFEC4899),
  ),
];

Color _accentAt(double pos, Color Function(_Slide) pick) {
  final last = _slides.length - 1;
  final i = pos.floor().clamp(0, last).toInt();
  final j = math.min(i + 1, last);
  final t = (pos - i).clamp(0.0, 1.0).toDouble();
  return Color.lerp(pick(_slides[i]), pick(_slides[j]), t)!;
}

// -----------------------------------------------------------------------------
// Layar utama
// -----------------------------------------------------------------------------

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Dipanggil saat user menekan "Mulai Sekarang" atau "Lewati".
  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();
  final ValueNotifier<double> _pos = ValueNotifier<double>(0);
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    _pos.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    final m = n.metrics;
    if (n.depth == 0 && m is PageMetrics) {
      final p = m.page;
      if (p != null) _pos.value = p;
    }
    return false;
  }

  void _next() {
    if (_page >= _slides.length - 1) {
      widget.onFinished();
    } else {
      _pc.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;

    return PopScope(
      // Back di slide > 1 = mundur satu slide, bukan keluar app.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _pc.previousPage(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Stack(
          children: [
            Positioned.fill(child: _AuroraBackground(pos: _pos)),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(isLast: isLast, onSkip: widget.onFinished),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: PageView.builder(
                        controller: _pc,
                        itemCount: _slides.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => _SlidePage(
                          index: i,
                          pos: _pos,
                          active: _page == i,
                        ),
                      ),
                    ),
                  ),
                  _PageIndicator(pos: _pos),
                  const SizedBox(height: 20),
                  _CtaButton(pos: _pos, isLast: isLast, onTap: _next),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Top bar, halaman, indikator, tombol
// -----------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isLast, required this.onSkip});

  final bool isLast;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/images/logo.jpg', width: 36, height: 36),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Zenime',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            AnimatedOpacity(
              opacity: isLast ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: isLast,
                child: GestureDetector(
                  onTap: onSkip,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: Text(
                      'Lewati',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlidePage extends StatelessWidget {
  const _SlidePage({required this.index, required this.pos, required this.active});

  final int index;
  final ValueNotifier<double> pos;
  final bool active;

  InlineSpan _titleSpan(_Slide s) {
    const base = TextStyle(
      fontSize: 30,
      height: 38 / 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    );
    final i = s.title.indexOf(s.highlight);
    if (i < 0) {
      return TextSpan(text: s.title, style: base.copyWith(color: Colors.white));
    }
    final shader = LinearGradient(colors: [s.a, s.b])
        .createShader(const Rect.fromLTWH(0, 0, 220, 40));
    return TextSpan(
      style: base,
      children: [
        TextSpan(
          text: s.title.substring(0, i),
          style: const TextStyle(color: Colors.white),
        ),
        TextSpan(
          text: s.highlight,
          style: TextStyle(foreground: Paint()..shader = shader),
        ),
        TextSpan(
          text: s.title.substring(i + s.highlight.length),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }

  Widget _illustration(_Slide s) {
    switch (index) {
      case 0:
        return _PosterStackIllustration(active: active, a: s.a, b: s.b);
      case 1:
        return _OfflineIllustration(active: active, a: s.a, b: s.b);
      case 2:
        return _DonghuaIllustration(active: active, a: s.a, b: s.b);
      case 3:
        return _ChatIllustration(active: active, a: s.a, b: s.b);
      case 4:
        return _LevelIllustration(active: active, a: s.a, b: s.b);
      default:
        return _PremiumIllustration(active: active, a: s.a, b: s.b);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _slides[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AnimatedBuilder(
                animation: pos,
                builder: (context, child) {
                  // Parallax: ilustrasi gerak lebih pelan dari teks.
                  final off = pos.value - index;
                  final k = 1 - off.abs().clamp(0.0, 1.0).toDouble();
                  return Transform.translate(
                    offset: Offset(off * _stage * 0.35, 0),
                    child: Opacity(
                      opacity: k,
                      child: Transform.scale(
                        scale: 0.85 + 0.15 * k,
                        child: child,
                      ),
                    ),
                  );
                },
                // Skala turun otomatis di layar kecil biar ilustrasi gak kepotong.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: _stage,
                    height: _stage,
                    child: _illustration(s),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _Reveal(
            active: active,
            child: Text.rich(_titleSpan(s), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          _Reveal(
            active: active,
            delayMs: 120,
            child: Text(
              s.desc,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 16,
                height: 24 / 16,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.pos});

  final ValueNotifier<double> pos;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: pos,
      builder: (context, p, _) {
        final accent = _accentAt(p, (s) => s.a);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _slides.length; i++)
              Builder(builder: (context) {
                final near = (1 - (p - i).abs()).clamp(0.0, 1.0).toDouble();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: 8 + 22 * near,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    color: Color.lerp(Colors.white.withValues(alpha: 0.2), accent, near),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _CtaButton extends StatefulWidget {
  const _CtaButton({required this.pos, required this.isLast, required this.onTap});

  final ValueNotifier<double> pos;
  final bool isLast;
  final VoidCallback onTap;

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ValueListenableBuilder<double>(
        valueListenable: widget.pos,
        builder: (context, p, _) {
          final a = _accentAt(p, (s) => s.a);
          final b = _accentAt(p, (s) => s.b);
          return GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _pressed ? 0.96 : 1,
              duration: const Duration(milliseconds: 120),
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(colors: [a, b]),
                  boxShadow: [
                    BoxShadow(
                      color: a.withValues(alpha: 0.55),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: _Loop(
                          period: const Duration(milliseconds: 2800),
                          builder: (context, t) => CustomPaint(
                            painter: _SheenPainter(-0.6 + 2.2 * t),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.4),
                                  end: Offset.zero,
                                ).animate(anim),
                                child: child,
                              ),
                            ),
                            child: Text(
                              widget.isLast ? 'Mulai Sekarang' : 'Lanjut',
                              key: ValueKey(widget.isLast),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _Loop(
                            period: const Duration(milliseconds: 700),
                            reverse: true,
                            builder: (context, t) => Transform.translate(
                              offset: Offset(Curves.easeInOut.transform(t) * 4, 0),
                              child: const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SheenPainter extends CustomPainter {
  _SheenPainter(this.x);

  /// Posisi kilau, dalam fraksi lebar tombol.
  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = x * size.width;
    final shader = LinearGradient(
      colors: [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0.28),
        Colors.white.withValues(alpha: 0),
      ],
    ).createShader(
      Rect.fromPoints(
        Offset(cx - size.width * 0.25, 0),
        Offset(cx + size.width * 0.25, size.height),
      ),
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.x != x;
}

// -----------------------------------------------------------------------------
// Background: aurora glow + bintang berkedip
// -----------------------------------------------------------------------------

class _Star {
  const _Star(this.x, this.y, this.r, this.phase, this.alpha);

  final double x;
  final double y;
  final double r;
  final double phase;
  final double alpha;
}

class _AuroraBackground extends StatefulWidget {
  const _AuroraBackground({required this.pos});

  final ValueNotifier<double> pos;

  @override
  State<_AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<_AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 40))
        ..repeat();

  late final List<_Star> _stars = () {
    final rnd = math.Random(11);
    return List<_Star>.generate(36, (_) {
      return _Star(
        rnd.nextDouble(),
        rnd.nextDouble(),
        0.7 + rnd.nextDouble() * 1.6,
        rnd.nextDouble() * 6.2832,
        0.35 + rnd.nextDouble() * 0.6,
      );
    });
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(t: _c, pos: widget.pos, stars: _stars),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.t, required this.pos, required this.stars})
      : super(repaint: Listenable.merge([t, pos]));

  final Animation<double> t;
  final ValueNotifier<double> pos;
  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pos.value;
    final a = _accentAt(p, (s) => s.a);
    final b = _accentAt(p, (s) => s.b);
    final w = size.width;
    final h = size.height;
    final drift = t.value;
    final twinkle = t.value * 2 * math.pi * 10;
    final breathe = 0.5 + 0.5 * math.sin(t.value * 2 * math.pi * 7);

    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.backgroundDark);

    void glow(Offset c, double r, Color color, double alpha) {
      final shader = RadialGradient(
        colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, Paint()..shader = shader);
    }

    glow(
      Offset(w * (0.30 + 0.08 * math.sin(p * 1.7)), h * 0.20),
      w * (0.95 + 0.10 * breathe),
      a,
      0.40,
    );
    glow(
      Offset(w * (0.85 - 0.06 * math.sin(p * 1.3)), h * 0.72),
      w * (0.85 + 0.10 * (1 - breathe)),
      b,
      0.32,
    );

    final star = Paint();
    for (final s in stars) {
      final y = ((s.y - drift + 1) % 1) * h;
      final tw = 0.5 + 0.5 * math.sin(twinkle + s.phase);
      star.color = Colors.white.withValues(alpha: s.alpha * (0.25 + 0.75 * tw));
      canvas.drawCircle(Offset(s.x * w, y), s.r, star);
    }

    // Redam bagian bawah biar tombol & indikator tetap kebaca jelas.
    final fade = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.backgroundDark.withValues(alpha: 0),
        AppColors.backgroundDark.withValues(alpha: 0.85),
      ],
    ).createShader(Rect.fromLTRB(0, h * 0.6, w, h));
    canvas.drawRect(Rect.fromLTRB(0, h * 0.6, w, h), Paint()..shader = fade);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => true;
}

// -----------------------------------------------------------------------------
// Helper animasi & komponen kecil
// -----------------------------------------------------------------------------

/// Loop animasi: [builder] dipanggil tiap frame dengan t di 0..1.
class _Loop extends StatefulWidget {
  const _Loop({
    required this.period,
    required this.builder,
    this.reverse = false,
    this.delay = Duration.zero,
  });

  final Duration period;
  final bool reverse;
  final Duration delay;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.repeat(reverse: widget.reverse);
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.repeat(reverse: widget.reverse);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => widget.builder(context, _c.value),
    );
  }
}

/// Melayang naik-turun pelan.
class _Floating extends StatelessWidget {
  const _Floating({
    required this.child,
    this.periodMs = 3200,
    this.startMs = 0,
    this.amplitude = 8,
  });

  final Widget child;
  final int periodMs;
  final int startMs;
  final double amplitude;

  @override
  Widget build(BuildContext context) {
    return _Loop(
      period: Duration(milliseconds: periodMs),
      delay: Duration(milliseconds: startMs),
      reverse: true,
      builder: (context, t) => Transform.translate(
        offset: Offset(0, (Curves.easeInOut.transform(t) * 2 - 1) * amplitude),
        child: child,
      ),
    );
  }
}

/// Muncul saat [active] (fade + geser naik + opsional membesar), balik saat tidak.
class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.active,
    required this.child,
    this.delayMs = 0,
    this.dy = 28,
    this.scaleFrom = 1,
    this.durationMs = 600,
    this.curve = Curves.easeOutCubic,
    this.alignment = Alignment.bottomCenter,
  });

  final bool active;
  final Widget child;
  final int delayMs;
  final double dy;
  final double scaleFrom;
  final int durationMs;
  final Curve curve;
  final Alignment alignment;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final int _total = widget.durationMs + widget.delayMs;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: _total));
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.delayMs / _total, 1, curve: widget.curve),
    reverseCurve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.forward();
  }

  @override
  void didUpdateWidget(_Reveal old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (widget.active) {
        _c.forward();
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (context, child) {
        final v = _a.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, (1 - v) * widget.dy),
            child: Transform.scale(
              scale: widget.scaleFrom + (1 - widget.scaleFrom) * v,
              alignment: widget.alignment,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

BoxDecoration _glass(double radius) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.13),
          Colors.white.withValues(alpha: 0.05),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
    );

class _GlowOrb extends StatelessWidget {
  const _GlowOrb(this.color, this.size);

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _FloatChip extends StatelessWidget {
  const _FloatChip({
    required this.icon,
    required this.label,
    required this.tint,
    this.periodMs = 3200,
    this.startMs = 0,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final int periodMs;
  final int startMs;

  @override
  Widget build(BuildContext context) {
    return _Floating(
      periodMs: periodMs,
      startMs: startMs,
      amplitude: 7,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _glass(50),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tint, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip yang muncul membal saat slide aktif.
class _PopChip extends StatelessWidget {
  const _PopChip({
    required this.active,
    required this.delayMs,
    required this.icon,
    required this.label,
    required this.tint,
    this.startMs = 0,
  });

  final bool active;
  final int delayMs;
  final IconData icon;
  final String label;
  final Color tint;
  final int startMs;

  @override
  Widget build(BuildContext context) {
    return _Reveal(
      active: active,
      delayMs: delayMs,
      dy: 18,
      scaleFrom: 0.6,
      durationMs: 500,
      curve: _backOut,
      child: _FloatChip(icon: icon, label: label, tint: tint, startMs: startMs),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.a, required this.b, this.stroke = 12});

  final double progress;
  final Color a;
  final Color b;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.10),
    );
    final shader = SweepGradient(
      colors: [a, b, a],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0).toDouble(),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.a != a || old.b != b || old.stroke != stroke;
}

// -----------------------------------------------------------------------------
// Slide 1: tumpukan poster anime
// -----------------------------------------------------------------------------

class _PosterStackIllustration extends StatelessWidget {
  const _PosterStackIllustration({required this.active, required this.a, required this.b});

  final bool active;
  final Color a;
  final Color b;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: active ? 1 : 0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutBack,
      builder: (context, spread, _) {
        Widget side(String url, Color tint, double dir) {
          return Transform.translate(
            offset: Offset(84 * dir * spread, 22 * spread),
            child: Transform.rotate(
              angle: dir * 13 * math.pi / 180 * spread,
              child: Transform.scale(
                scale: 0.86,
                child: _Poster(url: url, tint: tint),
              ),
            ),
          );
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            _GlowOrb(a, 280),
            side(kLoginPosters[2], b, -1),
            side(kLoginPosters[3], a, 1),
            _Floating(
              periodMs: 3600,
              amplitude: 6,
              child: _Poster(url: kLoginPosters[0], tint: a, showPlay: true),
            ),
          ],
        );
      },
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.tint, this.showPlay = false});

  final String url;
  final Color tint;
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(url),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.backgroundDark.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            if (showPlay) Center(child: _PlayPulse(tint: tint)),
          ],
        ),
      ),
    );
  }
}

class _PlayPulse extends StatelessWidget {
  const _PlayPulse({required this.tint});

  final Color tint;

  @override
  Widget build(BuildContext context) {
    return _Loop(
      period: const Duration(milliseconds: 1800),
      builder: (context, t) {
        return SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + 0.6 * t,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tint.withValues(alpha: 0.45 * (1 - t)),
                  ),
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint,
                  boxShadow: [
                    BoxShadow(color: tint.withValues(alpha: 0.6), blurRadius: 16),
                  ],
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Slide 2: download & offline
// -----------------------------------------------------------------------------

class _OfflineIllustration extends StatelessWidget {
  const _OfflineIllustration({required this.active, required this.a, required this.b});

  final bool active;
  final Color a;
  final Color b;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _GlowOrb(a, 280),
        _Reveal(
          active: active,
          dy: 0,
          scaleFrom: 0.7,
          durationMs: 700,
          curve: _backOut,
          alignment: Alignment.center,
          child: SizedBox(
            width: 190,
            height: 190,
            child: _Loop(
              period: const Duration(milliseconds: 3200),
              builder: (context, t) {
                // Progres "mengunduh" naik pelan lalu mengulang.
                final progress = Curves.easeInOut.transform(t);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(190, 190),
                      painter: _RingPainter(progress: progress, a: a, b: b),
                    ),
                    Container(
                      width: 128,
                      height: 128,
                      decoration: _glass(64),
                      child: const Icon(Icons.download_rounded, color: Colors.white, size: 58),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 34,
          child: _PopChip(
            active: active,
            delayMs: 250,
            icon: Icons.wifi_off_rounded,
            label: 'Tanpa kuota',
            tint: a,
          ),
        ),
        Positioned(
          right: 4,
          bottom: 40,
          child: _PopChip(
            active: active,
            delayMs: 400,
            icon: Icons.hd_rounded,
            label: '1080p',
            tint: b,
            startMs: 500,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Slide 3: donghua
// -----------------------------------------------------------------------------

class _DonghuaIllustration extends StatelessWidget {
  const _DonghuaIllustration({required this.active, required this.a, required this.b});

  final bool active;
  final Color a;
  final Color b;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: active ? 1 : 0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutBack,
      builder: (context, spread, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            _GlowOrb(a, 280),
            // Poster komik (belakang, miring ke kiri).
            Transform.translate(
              offset: Offset(-62 * spread, 22 * spread),
              child: Transform.rotate(
                angle: -11 * math.pi / 180 * spread,
                child: Transform.scale(
                  scale: 0.86,
                  child: _Poster(url: _kComicPoster, tint: b),
                ),
              ),
            ),
            // Poster donghua (depan, melayang, ada tombol play).
            Transform.translate(
              offset: Offset(36 * spread, 0),
              child: _Floating(
                periodMs: 3600,
                amplitude: 6,
                child: _Poster(url: _kDonghuaPoster, tint: a, showPlay: true),
              ),
            ),
            Positioned(
              right: 0,
              top: 20,
              child: _PopChip(
                active: active,
                delayMs: 250,
                icon: Icons.local_fire_department_rounded,
                label: 'Donghua',
                tint: _gold,
              ),
            ),
            Positioned(
              left: 0,
              bottom: 26,
              child: _PopChip(
                active: active,
                delayMs: 400,
                icon: Icons.menu_book_rounded,
                label: 'Komik',
                tint: b,
                startMs: 500,
              ),
            ),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Slide 4: chat & clan
// -----------------------------------------------------------------------------

class _ChatIllustration extends StatelessWidget {
  const _ChatIllustration({required this.active, required this.a, required this.b});

  final bool active;
  final Color a;
  final Color b;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _GlowOrb(a, 280),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Bubble(
                active: active,
                delayMs: 100,
                mine: false,
                a: a,
                b: b,
                text: 'Ada rekomendasi anime baru?',
              ),
              const SizedBox(height: 12),
              _Bubble(
                active: active,
                delayMs: 450,
                mine: true,
                a: a,
                b: b,
                text: 'Coba yang lagi rame minggu ini 🔥',
              ),
              const SizedBox(height: 12),
              _Reveal(
                active: active,
                delayMs: 800,
                dy: 18,
                scaleFrom: 0.6,
                durationMs: 500,
                curve: _backOut,
                alignment: Alignment.bottomLeft,
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: _TypingDots(),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 0,
          top: 22,
          child: _PopChip(
            active: active,
            delayMs: 300,
            icon: Icons.shield_rounded,
            label: 'Clan',
            tint: b,
          ),
        ),
        Positioned(
          left: 0,
          bottom: 20,
          child: _PopChip(
            active: active,
            delayMs: 500,
            icon: Icons.person_add_alt_1_rounded,
            label: 'Teman',
            tint: a,
            startMs: 600,
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.active,
    required this.delayMs,
    required this.mine,
    required this.a,
    required this.b,
    required this.text,
  });

  final bool active;
  final int delayMs;
  final bool mine;
  final Color a;
  final Color b;
  final String text;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: mine ? [b, a] : [a, b]),
      ),
      child: Icon(
        mine ? Icons.face_5_rounded : Icons.face_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: mine
            ? BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
                gradient: LinearGradient(colors: [a, b]),
              )
            : _glass(18).copyWith(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(18),
                ),
              ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
        ),
      ),
    );

    return _Reveal(
      active: active,
      delayMs: delayMs,
      dy: 18,
      scaleFrom: 0.6,
      durationMs: 500,
      curve: _backOut,
      alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft,
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: mine
            ? [bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble],
      ),
    );
  }
}

class _TypingDots extends StatelessWidget {
  const _TypingDots();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 42),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _glass(18),
      child: _Loop(
        period: const Duration(milliseconds: 1200),
        builder: (context, t) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  margin: EdgeInsets.only(right: i == 2 ? 0 : 5),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: 0.35 + 0.65 * (0.5 + 0.5 * math.sin((t - i * 0.15) * 2 * math.pi)),
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

// -----------------------------------------------------------------------------
// Slide 5: level & XP
// -----------------------------------------------------------------------------

class _LevelIllustration extends StatelessWidget {
  const _LevelIllustration({required this.active, required this.a, required this.b});

  final bool active;
  final Color a;
  final Color b;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _GlowOrb(a, 280),
        _Floating(
          periodMs: 3800,
          amplitude: 5,
          child: SizedBox(
            width: 200,
            height: 200,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: active ? 0.72 : 0),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(200, 200),
                    painter: _RingPainter(progress: v, a: a, b: b, stroke: 14),
                  ),
                  Container(
                    width: 136,
                    height: 136,
                    decoration: _glass(68),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'LEVEL',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          '${(v / 0.72 * 25).round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 28,
          child: _PopChip(
            active: active,
            delayMs: 300,
            icon: Icons.bolt_rounded,
            label: '+70 XP',
            tint: _gold,
          ),
        ),
        Positioned(
          left: 0,
          bottom: 34,
          child: _PopChip(
            active: active,
            delayMs: 480,
            icon: Icons.emoji_events_rounded,
            label: 'Leaderboard',
            tint: b,
            startMs: 500,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Slide 6: premium
// -----------------------------------------------------------------------------

class _PremiumIllustration extends StatelessWidget {
  const _PremiumIllustration({required this.active, required this.a, required this.b});

  final bool active;
  final Color a;
  final Color b;

  Widget _sparkle(double left, double top, double size, double phase) {
    return Positioned(
      left: left,
      top: top,
      child: _Loop(
        period: const Duration(milliseconds: 2400),
        builder: (context, t) {
          final k = 0.5 + 0.5 * math.sin((t + phase) * 2 * math.pi);
          return Opacity(
            opacity: 0.25 + 0.75 * k,
            child: Transform.scale(
              scale: 0.7 + 0.5 * k,
              child: Icon(Icons.auto_awesome_rounded, color: _gold, size: size),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _GlowOrb(_gold, 280),
        _sparkle(52, 56, 22, 0),
        _sparkle(228, 78, 18, 0.35),
        _sparkle(70, 214, 16, 0.65),
        _sparkle(214, 196, 24, 0.15),
        _Reveal(
          active: active,
          dy: 20,
          scaleFrom: 0.6,
          durationMs: 700,
          curve: _backOut,
          alignment: Alignment.center,
          child: _Floating(
            periodMs: 3400,
            amplitude: 8,
            child: Image.asset(
              'assets/images/ic_premium_badge.png',
              width: 170,
              height: 170,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 120,
          child: _PopChip(
            active: active,
            delayMs: 300,
            icon: Icons.block_rounded,
            label: 'Tanpa iklan',
            tint: a,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 52,
          child: _PopChip(
            active: active,
            delayMs: 480,
            icon: Icons.bolt_rounded,
            label: 'XP ×2',
            tint: b,
            startMs: 500,
          ),
        ),
      ],
    );
  }
}
