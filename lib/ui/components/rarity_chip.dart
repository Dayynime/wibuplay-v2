import 'package:flutter/material.dart';

import '../../data/models/wallpaper_models.dart';

/// Chip rarity wallpaper. Rarity biasa = warna polos / gradient statis.
/// Rarity Limited = silver metalik + garis kilau yang menyapu terus-menerus
/// dan pinggiran terang, supaya kelihatan "mengkilap" di atas Mythic.
class RarityChip extends StatelessWidget {
  const RarityChip({super.key, required this.rarity, this.opacity = 1.0, this.fontSize = 10});

  final WallpaperRarity rarity;

  /// Transparansi warna polos (dipakai di atas wallpaper komentar).
  final double opacity;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (rarity.isShiny) return _ShinyChip(rarity: rarity, fontSize: fontSize);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: rarity.gradient == null ? rarity.color.withValues(alpha: opacity) : null,
        gradient: rarity.gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        rarity.label,
        style: TextStyle(color: rarity.onColor, fontSize: fontSize, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ShinyChip extends StatefulWidget {
  const _ShinyChip({required this.rarity, required this.fontSize});

  final WallpaperRarity rarity;
  final double fontSize;

  @override
  State<_ShinyChip> createState() => _ShinyChipState();
}

class _ShinyChipState extends State<_ShinyChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hormati setting "reduce motion" di perangkat.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0.5;
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
    final r = widget.rarity;
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x66E8ECF2), blurRadius: 8)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Dasar silver metalik
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: r.gradient))),
              // Garis kilau menyapu dari kiri ke kanan, diam sebentar, lalu ulang.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) {
                    // 0..0.6 = menyapu, 0.6..1 = jeda
                    final t = (_c.value / 0.6).clamp(0.0, 1.0);
                    final x = -1.6 + t * 3.2;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(x - 0.5, -1),
                          end: Alignment(x + 0.5, 1),
                          colors: const [Color(0x00FFFFFF), Color(0xE6FFFFFF), Color(0x00FFFFFF)],
                          stops: const [0.35, 0.5, 0.65],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Pinggiran terang
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xCCFFFFFF), width: 0.8),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: widget.fontSize + 1, color: r.onColor),
                    const SizedBox(width: 3),
                    Text(
                      r.label,
                      style: TextStyle(
                        color: r.onColor,
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
