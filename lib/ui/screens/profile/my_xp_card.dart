import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/xp_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../xp/xp_leaderboard_screen.dart';

/// Progress bar XP ke level berikutnya di Profil. Cuma bar: tanpa card,
/// tanpa border radius. Fill beranimasi tiap progress berubah + kilau yang
/// menyapu terus. Tap = buka leaderboard.
class MyXpCard extends ConsumerStatefulWidget {
  const MyXpCard({super.key, required this.firebaseUid});

  final String firebaseUid;

  @override
  ConsumerState<MyXpCard> createState() => _MyXpCardState();
}

class _MyXpCardState extends ConsumerState<MyXpCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final xp = ref.watch(myXpProvider(widget.firebaseUid)).valueOrNull;
    final level = xp?.level ?? 1;
    final totalXp = xp?.totalXp ?? 0;
    final p = XpLevelFormula.progress(totalXp, level);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context)
            .push<void>(fadeRoute(const XpLeaderboardScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.white12),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: p.fraction),
                  duration: const Duration(milliseconds: 1100),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v,
                    child: ClipRect(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.accentViolet,
                                  AppColors.accentVioletLight,
                                ],
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _shine,
                            builder: (context, _) => FractionallySizedBox(
                              alignment: Alignment(-1 + 3 * _shine.value, 0),
                              widthFactor: 0.35,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0x00FFFFFF),
                                      Color(0x66FFFFFF),
                                      Color(0x00FFFFFF),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
