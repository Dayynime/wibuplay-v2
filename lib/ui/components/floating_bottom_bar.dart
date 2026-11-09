import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

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

/// Bottom bar melayang (redesain Samudra). Latar padat 94% tanpa blur, jadi
/// tidak ada BackdropFilter yang dihitung ulang tiap frame saat scroll.
/// Tab aktif ditandai pill lembut yang bergeser halus ke tab baru.
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

class _FloatingBottomBarState extends State<FloatingBottomBar> {
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final n = BottomTab.all.length;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + bottomInset),
      child: RepaintBoundary(
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x14FFFFFF)),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -12),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final slot = c.maxWidth / n;
              return Stack(
                children: [
                  // Pill tab aktif.
                  AnimatedPositioned(
                    duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
                    curve: Curves.easeOutQuint,
                    left: widget.currentIndex * slot + 4,
                    top: 9,
                    bottom: 9,
                    width: slot - 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.accentViolet.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
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
                  scale: isSelected ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutQuint,
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
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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
