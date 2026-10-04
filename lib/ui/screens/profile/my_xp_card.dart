import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/xp_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../xp/xp_leaderboard_screen.dart';

/// Kartu ringkas "Level nonton" di Profil: progress XP ke level berikutnya +
/// tombol ke leaderboard (port MyXpCard.kt). Belum pernah nonton = belum ada
/// baris user_xp, ditampilkan sebagai Level 1 / 0 XP supaya fiturnya terlihat.
class MyXpCard extends ConsumerWidget {
  const MyXpCard({super.key, required this.firebaseUid});

  final String firebaseUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xp = ref.watch(myXpProvider(firebaseUid)).valueOrNull;
    final level = xp?.level ?? 1;
    final totalXp = xp?.totalXp ?? 0;
    final p = XpLevelFormula.progress(totalXp, level);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context)
              .push<void>(fadeRoute(const XpLeaderboardScreen())),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentViolet,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Level $level',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'dari nonton anime',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ),
                    const Text(
                      'Leaderboard ›',
                      style: TextStyle(
                        color: AppColors.accentVioletLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.fraction,
                    minHeight: 8,
                    color: AppColors.accentViolet,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${p.xpIntoLevel} / ${p.xpNeededForLevel} XP ke Level ${level + 1}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
