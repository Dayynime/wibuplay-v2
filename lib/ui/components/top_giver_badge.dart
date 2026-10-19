import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

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
    return TopGiverChip(height: height);
  }
}

/// Desain "Cincin orbit" hijau teal: badge gelap, garis tepi gradien yang
/// berputar, teks gradien, dan glow yang berdenyut.
class TopGiverChip extends StatefulWidget {
  const TopGiverChip({super.key, this.height = 20});

  final double height;

  @override
  State<TopGiverChip> createState() => _TopGiverChipState();
}

class _TopGiverChipState extends State<TopGiverChip>
    with SingleTickerProviderStateMixin {
  static const Color _c1 = Color(0xFF5EEAD4);
  static const Color _c2 = Color(0xFF0D9488);
  static const Color _fill = Color(0xFF0C171A);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
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
    const ring = 1.5;
    final inner = Container(
      height: h - ring * 2,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular((h - ring * 2) / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.card_giftcard, size: compact ? 9 : 11, color: _c1),
          const SizedBox(width: 3),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) =>
                const LinearGradient(colors: [_c1, _c2]).createShader(r),
            child: Text(
              'TOP GIVER',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 8 : 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: inner,
        builder: (context, child) {
          final glow = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi * 1.33));
          return Container(
            padding: const EdgeInsets.all(ring),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(h / 2),
              gradient: SweepGradient(
                transform: GradientRotation(_c.value * 2 * math.pi),
                colors: const [_c1, Color(0x330D9488), _c2, Color(0x330D9488), _c1],
                stops: const [0.0, 0.3, 0.55, 0.8, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: _c1.withValues(alpha: glow),
                  blurRadius: 8,
                ),
              ],
            ),
            child: child,
          );
        },
      ),
    );
  }
}
