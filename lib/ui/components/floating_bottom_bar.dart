import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

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
    BottomTab('cuplix', 'Cuplix', Icons.video_library_outlined),
    BottomTab('profile', 'Profil', Icons.person_outline),
  ];
}

class FloatingBottomBar extends StatelessWidget {
  const FloatingBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: AppShapes.pill,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceDark.withValues(alpha: 0.96),
              const Color(0xF0080B10),
            ],
          ),
          border: Border.all(
            color: AppColors.surfaceElevated.withValues(alpha: 0.6),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < BottomTab.all.length; i++)
              _TabItem(
                tab: BottomTab.all[i],
                isSelected: i == currentIndex,
                onTap: () => onTabSelected(i),
              ),
          ],
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
    final tint = isSelected ? AppColors.accentViolet : AppColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentViolet.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: AppShapes.pill,
        ),
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
                  scale: isSelected ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: Icon(tab.icon, color: c, size: 22),
                ),
                const SizedBox(height: 2),
                Text(
                  tab.title,
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
