import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Port ShimmerBox/shimmerBrush (Shimmer.kt): gradien 3 warna dari (0,0) ke
/// (t,t), t bergerak 0 -> 1000 (px) selama 850ms, FastOutSlowIn, restart.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({super.key, this.width, this.height, this.borderRadius});

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final radius = widget.borderRadius ?? BorderRadius.circular(12);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.fastOutSlowIn.transform(_c.value) * 1000 / dpr;
            return CustomPaint(painter: _ShimmerPainter(t));
          },
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(t, t),
        [
          AppColors.surfaceDark.withValues(alpha: 0.9),
          AppColors.surfaceElevated.withValues(alpha: 0.6),
          AppColors.surfaceDark.withValues(alpha: 0.9),
        ],
        const [0.0, 0.5, 1.0],
        TileMode.clamp,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}

class AnimeCardSkeleton extends StatelessWidget {
  const AnimeCardSkeleton({super.key, this.width = 140});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ShimmerBox(borderRadius: AppShapes.card),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.85,
            child: ShimmerBox(height: 14, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 4),
          FractionallySizedBox(
            widthFactor: 0.5,
            child: ShimmerBox(height: 12, borderRadius: BorderRadius.circular(4)),
          ),
        ],
      ),
    );
  }
}

class HeroBannerSkeleton extends StatelessWidget {
  const HeroBannerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 210,
      child: ShimmerBox(borderRadius: AppShapes.card),
    );
  }
}

class AnimeRowSkeleton extends StatelessWidget {
  const AnimeRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            const AnimeCardSkeleton(),
          ],
        ],
      ),
    );
  }
}
