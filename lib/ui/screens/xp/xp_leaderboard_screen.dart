import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers.dart';
import '../../components/role_badges.dart';
import '../profile/public_profile_screen.dart';
import '../../glass/glass.dart';
import '../../components/clan_tag_badge.dart';
import '../../components/user_level_badge.dart';
import '../../redesign/podium_kit.dart';
import '../../redesign/z_kit.dart';

/// Leaderboard XP (redesain): tiga kartu podium tinggi bergradien (perak,
/// emas, perunggu) dengan karangan daun + peringkat, lalu panel daftar
/// peringkat 4+ dengan lencana karangan daun di kanan. XP yang tampil adalah
/// XP nonton BULAN BERJALAN (reset tiap tanggal 1 WIB); level tetap kumulatif.
class XpLeaderboardScreen extends ConsumerWidget {
  const XpLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(xpLeaderboardProvider);
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid;

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Leaderboard', style: ZFont.display(size: 18)),
            const Text(
              'XP bulan ini · reset tiap tanggal 1',
              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w500),
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
              const Text('Gagal ambil leaderboard', style: TextStyle(color: AppColors.textSecondary)),
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
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              // 0 = podium, 1 = kepala panel, lalu baris 4+, terakhir kaki panel.
              itemCount: 2 + rest.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ZPodium(
                    items: [
                      for (final e in top3)
                        ZPodiumItem(
                          rank: top3.indexOf(e) + 1,
                          uid: e.firebaseUid,
                          username: e.username,
                          avatarUrl: e.avatarUrl,
                          isMe: e.firebaseUid == myUid,
                          value: e.xp,
                          valueText: zGroupInt,
                          nameTrailing: UserCheckBadge(firebaseUid: e.firebaseUid, isPremium: e.isPremium, size: 13),
                          extra: (e.clanTag != null && e.clanTag!.isNotEmpty) ? ClanTagBadge(text: e.clanTag!) : null,
                        ),
                    ],
                    onTap: (it) => openPublicProfile(context, it.uid),
                  );
                }
                if (i == 1) return const ZPanelTop();
                if (i == rest.length + 2) return const ZPanelBottom();
                final idx = i - 2;
                final e = rest[idx];
                return ZStaggerIn(
                  index: idx,
                  child: ZRankRow(
                    rank: idx + 4,
                    uid: e.firebaseUid,
                    username: e.username,
                    avatarUrl: e.avatarUrl,
                    isMe: e.firebaseUid == myUid,
                    last: idx == rest.length - 1,
                    nameTrailing: UserCheckBadge(firebaseUid: e.firebaseUid, isPremium: e.isPremium, size: 15),
                    value: ZGemValue(zGroupInt(e.xp)),
                    badges: [
                      UserLevelBadge(uid: e.firebaseUid, level: e.level),
                      if (e.clanTag != null && e.clanTag!.isNotEmpty) ClanTagBadge(text: e.clanTag!),
                    ],
                    onTap: () => openPublicProfile(context, e.firebaseUid),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Warna medali & aksen.
