import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Baris daftar game / dekorasi: thumbnail di kiri, judul, info kecil
/// (mis. "2–4 pemain"), panah di kanan. Dipakai Zenime Games & Zenime Decoration.
class GameListTile extends StatelessWidget {
  const GameListTile({
    super.key,
    required this.title,
    required this.info,
    required this.infoIcon,
    required this.colors,
    required this.preview,
    required this.onTap,
    this.badge,
  });

  final String title;

  /// Label kecil di samping judul, mis. "BETA" (null = tanpa label).
  final String? badge;
  final String info;
  final IconData infoIcon;

  /// Gradien latar thumbnail.
  final List<Color> colors;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 124,
                height: 72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: colors,
                        ),
                      ),
                    ),
                    RepaintBoundary(child: preview),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textWhite, fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD84D),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Color(0xFF3B2A06),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(infoIcon, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          info,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 26),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// Efek tekan: mengecil sedikit lalu membal balik.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
