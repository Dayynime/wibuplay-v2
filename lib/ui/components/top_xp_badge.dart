import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

/// Tag "TOP XP #posisi" untuk user yang masuk top XP bulanan.
/// Tidak render apa-apa kalau user tidak ada di leaderboard.
class TopXpBadge extends ConsumerWidget {
  const TopXpBadge({super.key, required this.firebaseUid, this.height = 20});

  final String firebaseUid;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (firebaseUid.isEmpty) return const SizedBox.shrink();
    final rank = ref.watch(topXpRankProvider(firebaseUid));
    if (rank == null) return const SizedBox.shrink();
    return TopXpChip(rank: rank, height: height);
  }
}

/// Desain "Potongan holo" cyan-ungu (pasangan TopGiverBadge yang emas): sudut dipotong, permukaan holografik yang
/// bergerak, garis scan halus, ikon petir yang meloncat, dan angka posisi.
class TopXpChip extends StatefulWidget {
  const TopXpChip({super.key, required this.rank, this.height = 20});

  final int rank;
  final double height;

  @override
  State<TopXpChip> createState() => _TopXpChipState();
}

class _TopXpChipState extends State<TopXpChip>
    with SingleTickerProviderStateMixin {
  static const Color _c1 = Color(0xFF9FE8FF);
  static const Color _c2 = Color(0xFF7C4DFF);
  static const Color _ink = Color(0xFF080B1F);
  static const double _span = 2.6; // lebar gradien = 2.6x badge

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hormati setting "reduce motion" di perangkat.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final compact = h < 18;
    final cut = compact ? 5.0 : 6.0;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Loncatan ikon: 2x per putaran, aktif di 55%-100% tiap siklus.
          final p = (_c.value * 2) % 1.0;
          final lift = p > 0.55 ? math.sin(math.pi * (p - 0.55) / 0.45) : 0.0;

          return ClipPath(
            clipper: _CutClipper(cut),
            child: CustomPaint(
              foregroundPainter: _ScanlinePainter(),
              child: Container(
                height: h,
                padding: EdgeInsets.only(left: compact ? 6 : 8, right: compact ? 3 : 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment(-1 + 2 * _span, 0),
                    tileMode: TileMode.repeated,
                    colors: const [_c2, _c1, Colors.white, _c1, _c2],
                    stops: const [0.0, 0.25, 0.48, 0.75, 1.0],
                    transform: _SlideTransform(_c.value * _span),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, -2 * lift),
                      child: Transform.scale(
                        scale: 1 + 0.15 * lift,
                        child: Icon(Icons.bolt, size: compact ? 9 : 11, color: _ink),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'TOP XP',
                      style: TextStyle(
                        color: _ink,
                        fontSize: compact ? 8 : 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(width: compact ? 4 : 5),
                    Container(
                      height: h - (compact ? 6 : 8),
                      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '#${widget.rank}',
                        style: TextStyle(
                          color: _c1,
                          fontSize: compact ? 8 : 9,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Geser gradien ke kiri sebesar [shift] x lebar badge (efek holo bergerak).
class _SlideTransform extends GradientTransform {
  const _SlideTransform(this.shift);
  final double shift;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(-bounds.width * shift, 0, 0);
}

/// Potong sudut kiri-atas dan kanan-bawah.
class _CutClipper extends CustomClipper<Path> {
  const _CutClipper(this.c);
  final double c;

  @override
  Path getClip(Size s) => Path()
    ..moveTo(c, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height - c)
    ..lineTo(s.width - c, s.height)
    ..lineTo(0, s.height)
    ..lineTo(0, c)
    ..close();

  @override
  bool shouldReclip(_CutClipper old) => old.c != c;
}

/// Garis scan tipis tiap 3px.
class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (double y = 1; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
