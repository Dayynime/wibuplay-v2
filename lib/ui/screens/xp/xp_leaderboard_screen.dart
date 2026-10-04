import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/xp_models.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';

/// Leaderboard XP: podium top-3 + daftar (port XpLeaderboardScreen.kt).
/// XP yang tampil adalah XP nonton BULAN BERJALAN (reset tiap tanggal 1 WIB);
/// level tetap kumulatif dan tidak ikut reset.
class XpLeaderboardScreen extends ConsumerWidget {
  const XpLeaderboardScreen({super.key});

  static const Color _gold = Color(0xFFFFD700);
  static const Color _silver = Color(0xFFC0C0C0);
  static const Color _bronze = Color(0xFFCD7F32);
  static const Color _xpColor = Color(0xFFFFC107);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(xpLeaderboardProvider);
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Leaderboard XP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(
              'Bulan ini • reset tiap tanggal 1',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: board.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gagal ambil leaderboard',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(xpLeaderboardProvider),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada yang nonton bulan ini.\nJadi yang pertama naik XP!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            );
          }
          final top3 = entries.take(3).toList();
          final rest = entries.skip(3).toList();
          return RefreshIndicator(
            color: AppColors.accentViolet,
            onRefresh: () async => ref.refresh(xpLeaderboardProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _podium(top3, myUid),
                const SizedBox(height: 14),
                for (var i = 0; i < rest.length; i++) ...[
                  _row(i + 4, rest[i], rest[i].firebaseUid == myUid),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _podium(List<UserXpDisplay> top3, String? myUid) {
    UserXpDisplay? at(int i) => i < top3.length ? top3[i] : null;
    final first = at(0), second = at(1), third = at(2);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accentViolet.withValues(alpha: 0.25),
            AppColors.backgroundDarkSecondary,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _podiumCard(second, 2, second.firebaseUid == myUid, 60, _silver),
          ),
          Expanded(
            child: first == null
                ? const SizedBox.shrink()
                : _podiumCard(first, 1, first.firebaseUid == myUid, 76, _gold, crown: true),
          ),
          Expanded(
            child: third == null
                ? const SizedBox.shrink()
                : _podiumCard(third, 3, third.firebaseUid == myUid, 60, _bronze),
          ),
        ],
      ),
    );
  }

  Widget _podiumCard(
    UserXpDisplay e,
    int rank,
    bool isMe,
    double avatarSize,
    Color ring, {
    bool crown = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (crown) const Icon(Icons.emoji_events, color: _gold, size: 22),
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
              child: UserAvatar(username: e.username, url: e.avatarUrl, size: avatarSize),
            ),
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                e.username + (isMe ? ' (Kamu)' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (e.isPremium) ...[
              const SizedBox(width: 3),
              const PremiumCheckBadge(size: 14),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${e.xp} XP',
          style: TextStyle(color: ring, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _row(int rank, UserXpDisplay e, bool isMe) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.accentViolet.withValues(alpha: 0.15)
            : AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '#$rank',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          UserAvatar(username: e.username, url: e.avatarUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.username + (isMe ? ' (Kamu)' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (e.isPremium) ...[
                      const SizedBox(width: 4),
                      const PremiumCheckBadge(size: 16),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                LevelBadge(level: e.level),
              ],
            ),
          ),
          Text(
            '${e.xp} XP',
            style: const TextStyle(
              color: _xpColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
