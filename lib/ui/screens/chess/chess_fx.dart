import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'chess_board.dart';

// Efek visual layar catur: overlay hasil (menang / kalah / remis), cahaya
// giliran, dan kedip skak. Semua digambar sendiri (tanpa aset / Lottie).

const Color _gold = Color(0xFFFFC94A);
const Color _goldDeep = Color(0xFFE79A12);
const Color _win = Color(0xFF22C55E);
const Color _lose = Color(0xFFE4344A);
const Color _silver = Color(0xFFC9D2E3);

// ============================================================================
// Overlay hasil permainan
// ============================================================================

/// Overlay penuh saat permainan selesai. [outcome]: 'win' | 'loss' | 'draw'.
/// Tap di luar tombol = tutup (papan terlihat lagi).
class ChessResultOverlay extends StatefulWidget {
  const ChessResultOverlay({
    super.key,
    required this.outcome,
    required this.reason,
    required this.myColor,
    required this.onClose,
    required this.rematchLabel,
    this.onRematch,
  });

  final String outcome;
  final String reason;

  /// 'w' / 'b' (warna raja yang ditampilkan).
  final String myColor;
  final VoidCallback onClose;
  final String rematchLabel;
  final VoidCallback? onRematch;

  @override
  State<ChessResultOverlay> createState() => _ChessResultOverlayState();
}

class _ChessResultOverlayState extends State<ChessResultOverlay> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final AnimationController _particles = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );
  late final List<_Particle> _bits = _makeParticles(widget.outcome);

  bool get _isWin => widget.outcome == 'win';
  bool get _isLoss => widget.outcome == 'loss';

  @override
  void initState() {
    super.initState();
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduce) {
      _intro.value = 1;
    } else {
      _intro.forward();
      _loop.repeat();
      _particles.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    _particles.dispose();
    super.dispose();
  }

  Color get _accent => _isWin ? _gold : (_isLoss ? _lose : _silver);

  String get _title => _isWin ? 'MENANG!' : (_isLoss ? 'KALAH' : 'REMIS');

  String get _subtitle => _isWin
      ? 'Skakmat! Kamu juaranya.'
      : (_isLoss ? 'Jangan menyerah, coba lagi!' : 'Sama kuat, seri!');

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.25, curve: Curves.easeOut));
    return FadeTransition(
      opacity: fade,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _loop, _particles]),
          builder: (context, _) {
            // Kalah: layar sedikit bergetar di awal.
            var shake = 0.0;
            if (_isLoss) {
              final t = (_intro.value / 0.45).clamp(0.0, 1.0);
              shake = math.sin(t * math.pi * 7) * 9 * (1 - t);
            }
            return Transform.translate(
              offset: Offset(shake, 0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Latar gelap dengan cahaya warna hasil di tengah.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.25),
                        radius: 1.1,
                        colors: [
                          _accent.withValues(alpha: _isLoss ? 0.22 : 0.30),
                          const Color(0xF20B0E14),
                          const Color(0xFA05070B),
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                  // Partikel: confetti (menang), abu jatuh (kalah), kilau (remis).
                  CustomPaint(painter: _ParticlePainter(_bits, _particles.value, widget.outcome)),
                  SafeArea(child: Center(child: _content())),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _content() {
    final pop = CurvedAnimation(parent: _intro, curve: const Interval(0.1, 0.6, curve: Curves.elasticOut));
    final rise = CurvedAnimation(parent: _intro, curve: const Interval(0.35, 0.8, curve: Curves.easeOutCubic));
    final buttons = CurvedAnimation(parent: _intro, curve: const Interval(0.6, 1, curve: Curves.easeOutCubic));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!_isLoss)
                  Transform.rotate(
                    angle: _loop.value * 2 * math.pi,
                    child: CustomPaint(
                      size: const Size.square(220),
                      painter: _RaysPainter(_accent.withValues(alpha: 0.35 * pop.value.clamp(0.0, 1.0))),
                    ),
                  ),
                Transform.scale(scale: pop.value.clamp(0.0, 1.3), child: _emblem()),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: rise.value,
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - rise.value)),
              child: Column(
                children: [
                  _shimmerTitle(),
                  const SizedBox(height: 6),
                  Text(
                    _subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.reason,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Opacity(
            opacity: buttons.value,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - buttons.value)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: widget.onClose,
                    child: const Text('Lihat papan'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isWin ? _goldDeep : AppColors.accentViolet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: widget.onRematch,
                    child: Text(widget.rematchLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lambang tengah: mahkota + raja emas (menang), raja tumbang (kalah),
  /// dua raja berdampingan (remis).
  Widget _emblem() {
    final glow = 0.5 + 0.5 * math.sin(_loop.value * 2 * math.pi * 3);
    if (_isWin) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: Offset(0, -4 * glow),
            child: const Icon(Icons.emoji_events_rounded, color: _gold, size: 44),
          ),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0xFFFFE59A), _goldDeep]),
              boxShadow: [
                BoxShadow(color: _gold.withValues(alpha: 0.45 + 0.3 * glow), blurRadius: 40, spreadRadius: 6),
              ],
            ),
            alignment: Alignment.center,
            child: ChessPieceGlyph(piece: widget.myColor == 'b' ? 'k' : 'K', size: 74),
          ),
        ],
      );
    }
    if (_isLoss) {
      // Raja jatuh miring ke kanan.
      final fall = Curves.bounceOut.transform(((_intro.value - 0.15) / 0.5).clamp(0.0, 1.0));
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1F2B),
          border: Border.all(color: _lose.withValues(alpha: 0.6), width: 2),
          boxShadow: [BoxShadow(color: _lose.withValues(alpha: 0.35), blurRadius: 30)],
        ),
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: fall * math.pi / 2.1,
          alignment: const Alignment(0, 0.7),
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.33, 0.33, 0.33, 0, 0, //
              0.33, 0.33, 0.33, 0, 0, //
              0.33, 0.33, 0.33, 0, 0, //
              0, 0, 0, 1, 0,
            ]),
            child: ChessPieceGlyph(piece: widget.myColor == 'b' ? 'k' : 'K', size: 74),
          ),
        ),
      );
    }
    return Container(
      width: 130,
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: const Color(0xFF1A1F2B),
        border: Border.all(color: _silver.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: _silver.withValues(alpha: 0.2 + 0.15 * glow), blurRadius: 30)],
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(angle: -0.15, child: const ChessPieceGlyph(piece: 'K', size: 56)),
          Transform.rotate(angle: 0.15, child: const ChessPieceGlyph(piece: 'k', size: 56)),
        ],
      ),
    );
  }

  Widget _shimmerTitle() {
    final base = _accent;
    final t = _loop.value * 3 % 1;
    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [base, Colors.white, base],
        stops: [(t - 0.2).clamp(0.0, 1.0), t, (t + 0.2).clamp(0.0, 1.0)],
      ).createShader(rect),
      child: Text(
        _title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 46,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
          shadows: [Shadow(color: base.withValues(alpha: 0.6), blurRadius: 24)],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- partikel

class _Particle {
  _Particle(this.x, this.y, this.vx, this.vy, this.size, this.color, this.spin, this.delay, this.shape);
  final double x, y, vx, vy, size, spin, delay;
  final Color color;
  final int shape; // 0 kotak, 1 bulat, 2 pita
}

List<_Particle> _makeParticles(String outcome) {
  final r = math.Random();
  final out = <_Particle>[];
  if (outcome == 'win') {
    const colors = [_gold, _win, Color(0xFF38BDF8), Color(0xFFF472B6), Colors.white, _lose];
    // Dua semburan dari bawah kiri & kanan + hujan dari atas.
    for (var i = 0; i < 70; i++) {
      final left = i.isEven;
      out.add(_Particle(
        left ? -0.02 : 1.02,
        0.95,
        (left ? 1 : -1) * (0.25 + r.nextDouble() * 0.45),
        -(1.1 + r.nextDouble() * 0.7),
        5 + r.nextDouble() * 6,
        colors[r.nextInt(colors.length)],
        (r.nextDouble() - 0.5) * 20,
        r.nextDouble() * 0.12,
        r.nextInt(3),
      ));
    }
    for (var i = 0; i < 60; i++) {
      out.add(_Particle(
        r.nextDouble(),
        -0.05 - r.nextDouble() * 0.3,
        (r.nextDouble() - 0.5) * 0.1,
        0.15 + r.nextDouble() * 0.2,
        4 + r.nextDouble() * 5,
        colors[r.nextInt(colors.length)],
        (r.nextDouble() - 0.5) * 16,
        0.15 + r.nextDouble() * 0.5,
        r.nextInt(3),
      ));
    }
  } else if (outcome == 'loss') {
    for (var i = 0; i < 45; i++) {
      out.add(_Particle(
        r.nextDouble(),
        -0.05 - r.nextDouble() * 0.4,
        (r.nextDouble() - 0.5) * 0.05,
        0.12 + r.nextDouble() * 0.12,
        2 + r.nextDouble() * 3,
        Color.lerp(const Color(0xFF6B7280), _lose, r.nextDouble() * 0.4)!,
        0,
        r.nextDouble() * 0.6,
        1,
      ));
    }
  } else {
    for (var i = 0; i < 40; i++) {
      out.add(_Particle(
        r.nextDouble(),
        0.2 + r.nextDouble() * 0.7,
        0,
        -0.05 - r.nextDouble() * 0.08,
        2 + r.nextDouble() * 3,
        _silver,
        0,
        r.nextDouble() * 0.7,
        1,
      ));
    }
  }
  return out;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.bits, this.t, this.outcome);

  final List<_Particle> bits;
  final double t;
  final String outcome;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final paint = Paint();
    final gravity = outcome == 'win' ? 1.6 : 0.0;
    for (final b in bits) {
      final lt = ((t - b.delay) * 1.4).clamp(0.0, 1.6);
      if (lt <= 0) continue;
      final x = (b.x + b.vx * lt) * size.width;
      final y = (b.y + b.vy * lt + 0.5 * gravity * lt * lt) * size.height;
      if (y > size.height + 20 || y < -40) continue;
      final fadeOut = outcome == 'win' ? (1 - ((t - 0.75) / 0.25).clamp(0.0, 1.0)) : math.sin(lt / 1.6 * math.pi);
      paint.color = b.color.withValues(alpha: (outcome == 'win' ? 0.95 : 0.55) * fadeOut);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * lt);
      switch (b.shape) {
        case 0:
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.6), paint);
        case 1:
          if (outcome == 'draw') {
            // Kilau bintang kecil.
            final s = b.size;
            final path = Path()
              ..moveTo(0, -s)
              ..lineTo(s * 0.25, -s * 0.25)
              ..lineTo(s, 0)
              ..lineTo(s * 0.25, s * 0.25)
              ..lineTo(0, s)
              ..lineTo(-s * 0.25, s * 0.25)
              ..lineTo(-s, 0)
              ..lineTo(-s * 0.25, -s * 0.25)
              ..close();
            canvas.drawPath(path, paint);
          } else {
            canvas.drawCircle(Offset.zero, b.size / 2, paint);
          }
        default:
          // Pita: berkibar (lebar berubah mengikuti putaran).
          final w = b.size * 0.4 * (0.4 + 0.6 * math.cos(b.spin * lt * 2).abs());
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: b.size * 1.4), const Radius.circular(1)),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(
        Rect.fromCircle(center: c, radius: r),
      );
    const n = 12;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a - 0.11), c.dy + r * math.sin(a - 0.11))
        ..lineTo(c.dx + r * math.cos(a + 0.11), c.dy + r * math.sin(a + 0.11))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}

// ============================================================================
// Bingkai papan: cahaya giliran & kedip skak
// ============================================================================

/// Bingkai papan. [myTurn] = cahaya aksen lembut berdenyut, [inCheck] =
/// kedip merah. Anak (papan) dibulatkan sudutnya.
class ChessBoardFrame extends StatefulWidget {
  const ChessBoardFrame({super.key, required this.child, this.myTurn = false, this.inCheck = false});

  final Widget child;
  final bool myTurn;
  final bool inCheck;

  @override
  State<ChessBoardFrame> createState() => _ChessBoardFrameState();
}

class _ChessBoardFrameState extends State<ChessBoardFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ChessBoardFrame old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final want = widget.myTurn || widget.inCheck;
    if (want && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!want && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final p = Curves.easeInOut.transform(_pulse.value);
        final color = widget.inCheck ? _lose : AppColors.accentViolet;
        final active = widget.myTurn || widget.inCheck;
        return Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: active
                  ? [color.withValues(alpha: 0.55 + 0.35 * p), const Color(0xFF2A3142), color.withValues(alpha: 0.35 + 0.3 * p)]
                  : const [Color(0xFF2A3142), Color(0xFF1A1F2B), Color(0xFF2A3142)],
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 10)),
              if (active)
                BoxShadow(
                  color: color.withValues(alpha: (widget.inCheck ? 0.45 : 0.22) * (0.5 + 0.5 * p)),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(13), child: child),
        );
      },
      child: widget.child,
    );
  }
}
