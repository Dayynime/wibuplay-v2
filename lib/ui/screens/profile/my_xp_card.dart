import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decor_tick.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/xp_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../xp/xp_leaderboard_screen.dart';
import '../../redesign/z_kit.dart';

/// Progress bar XP ke level berikutnya di Profil + angka XP. Tanpa card,
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
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  /// Kilau digambar ulang maks DecorTick.fps (animasi tetap jalan).
  late final Listenable _tick = DecorTick(_shine);

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

    // "Level N" + angka XP di atas, bar 8px membulat dengan kilau pelan.
    // Tanpa kartu (transparan). Tap = buka leaderboard.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push<void>(fadeRoute(const XpLeaderboardScreen())),
      child: Container(
        // Transparan: tanpa latar/garis, cuma isi.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: p.xpIntoLevel),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, into, _) => Row(
                children: [
                  Text('Level $level', style: ZFont.display(size: 16)),
                  const Spacer(),
                  Text(
                    '$into / ${p.xpNeededForLevel} XP',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0x1AFFFFFF)),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: p.fraction),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: v,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [AppColors.accentViolet, AppColors.accentTeal],
                                  ),
                                ),
                              ),
                              AnimatedBuilder(
                                animation: _tick,
                                builder: (context, _) => FractionallySizedBox(
                                  alignment: Alignment(-1 + 3 * _shine.value, 0),
                                  widthFactor: 0.35,
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0x00FFFFFF),
                                          Color(0x73FFFFFF),
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
          ],
        ),
      ),
    );
  }
}
