import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../glass/glass.dart';

/// Port BottomTab + FloatingBottomBar (FloatingBottomBar.kt).
class BottomTab {
  const BottomTab(this.route, this.title, this.icon);

  final String route;
  final String title;
  final IconData icon;

  static const List<BottomTab> all = [
    BottomTab('home', 'Beranda', Icons.home_outlined),
    BottomTab('explore', 'Jelajah', Icons.explore_outlined),
    BottomTab('schedule', 'Jadwal', Icons.calendar_month_outlined),
    BottomTab('menu', 'Menu', Icons.grid_view_rounded),
    BottomTab('profile', 'Profil', Icons.person_outline),
  ];
}

/// Kurva pegas: melewati target sedikit lalu kembali.
const Curve _spring = Cubic(0.34, 1.3, 0.64, 1);

/// Bottom bar melayang. Tab aktif ditandai lensa kaca yang meluncur ke tab
/// baru sambil melar lalu memantul seperti tetesan cairan.
class FloatingBottomBar extends StatefulWidget {
  const FloatingBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  @override
  State<FloatingBottomBar> createState() => _FloatingBottomBarState();
}

class _FloatingBottomBarState extends State<FloatingBottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lens = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 1,
  );
  late int _from = widget.currentIndex;

  @override
  void didUpdateWidget(FloatingBottomBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _from = old.currentIndex;
      if (MediaQuery.disableAnimationsOf(context)) {
        _lens.value = 1;
      } else {
        _lens.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final n = BottomTab.all.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
      child: GlassSurface(
        borderRadius: AppShapes.pill,
        blur: GlassBlur.thick,
        shadow: true,
        strength: 1.15,
        solidColor: AppColors.surfaceDark,
        padding: const EdgeInsets.all(6),
        child: LayoutBuilder(
          builder: (context, c) {
            final slot = c.maxWidth / n;
            return Stack(
              children: [
                // Lensa kaca di belakang ikon tab aktif.
                AnimatedBuilder(
                  animation: _lens,
                  builder: (context, _) {
                    final t = _lens.value;
                    final x = ui.lerpDouble(
                      _from * slot,
                      widget.currentIndex * slot,
                      _spring.transform(t),
                    )!;
                    final w = math.sin(math.pi * t);
                    return Positioned(
                      left: x + 2,
                      top: 0,
                      bottom: 0,
                      width: slot - 4,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(1 + 0.22 * w, 1 - 0.14 * w, 1),
                        child: const _Lens(),
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _TabItem(
                          tab: BottomTab.all[i],
                          isSelected: i == widget.currentIndex,
                          onTap: () => widget.onTabSelected(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Lensa kaca: bening dengan tepi atas memantulkan cahaya.
class _Lens extends StatelessWidget {
  const _Lens();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppShapes.pill,
        border: Border.all(color: const Color(0x2EFFFFFF)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            AppColors.accentViolet.withValues(alpha: 0.10),
          ],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.isSelected, required this.onTap});

  final BottomTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = isSelected ? AppColors.accentVioletLight : AppColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: tint),
          duration: const Duration(milliseconds: 250),
          builder: (context, color, _) {
            final c = color ?? tint;
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.14 : 1.0,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  child: Icon(tab.icon, color: c, size: 22),
                ),
                const SizedBox(height: 2),
                Text(
                  tab.title,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: c,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
