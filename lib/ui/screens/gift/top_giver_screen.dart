import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/support_models.dart';
import '../../../providers.dart';
import '../../components/top_giver_badge.dart';
import '../profile/public_profile_screen.dart' show openPublicProfile;
import '../../glass/glass.dart';
import '../../components/clan_tag_badge.dart';
import '../../components/user_level_badge.dart';
import '../../redesign/podium_kit.dart';
import '../../redesign/z_kit.dart';

String _days(int d) => '${zGroupInt(d)} hari';

/// Halaman Top Giver (redesain, sama dengan Leaderboard XP): podium 3 kartu
/// bergradien medali + karangan daun, lalu panel peringkat 4+.
class TopGiverScreen extends ConsumerWidget {
  const TopGiverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(topGiversProvider);
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid;
    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Top Giver', style: ZFont.display(size: 18)),
            const Text(
              'Hari Premium yang dibagikan',
              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.accentViolet,
        onRefresh: () => ref.refresh(topGiversProvider.future),
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
          ),
          error: (_, __) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(child: Text('Gagal memuat. Tarik untuk coba lagi.', style: TextStyle(color: AppColors.textSecondary))),
            ],
          ),
          data: (data) {
            final g = data.givers;
            if (g.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'Belum ada yang memberi Premium.\nJadi yang pertama lewat Giveaway!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              );
            }
            final top3 = g.take(3).toList();
            final rest = g.skip(3).toList();
            Widget? clanOf(TopGiver x) {
              final c = data.clanTags[x.firebaseUid];
              return (c ?? '').isEmpty ? null : ClanTagBadge(text: c!);
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              // 0 = podium, 1 = kepala panel, lalu baris 4+ (atau info kosong), kaki panel.
              itemCount: 2 + (rest.isEmpty ? 1 : rest.length) + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ZPodium(
                    items: [
                      for (var k = 0; k < top3.length; k++)
                        ZPodiumItem(
                          rank: k + 1,
                          uid: top3[k].firebaseUid,
                          username: top3[k].username,
                          avatarUrl: top3[k].avatarUrl,
                          isMe: top3[k].firebaseUid == myUid,
                          value: top3[k].days,
                          valueText: _days,
                          icon: Icons.card_giftcard_rounded,
                          extra: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (clanOf(top3[k]) case final c?) ...[c, const SizedBox(width: 4)],
                              TopGiverChip(rank: top3[k].rank, height: 16),
                            ],
                          ),
                        ),
                    ],
                    onTap: (it) => openPublicProfile(context, it.uid),
                  );
                }
                if (i == 1) return const ZPanelTop();
                final count = rest.isEmpty ? 1 : rest.length;
                if (i == count + 2) return const ZPanelBottom();
                if (rest.isEmpty) {
                  return const ColoredBox(
                    color: AppColors.surfaceDark,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      child: Text(
                        'Peringkat 4 dan seterusnya akan muncul di sini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                      ),
                    ),
                  );
                }
                final idx = i - 2;
                final x = rest[idx];
                final level = data.levels[x.firebaseUid];
                return ZStaggerIn(
                  index: idx,
                  child: ZRankRow(
                    rank: x.rank,
                    uid: x.firebaseUid,
                    username: x.username,
                    avatarUrl: x.avatarUrl,
                    isMe: x.firebaseUid == myUid,
                    last: idx == rest.length - 1,
                    nameTrailing: x.userNumber == null
                        ? null
                        : Text('#${x.userNumber}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    value: ZGemValue(_days(x.days), icon: Icons.card_giftcard_rounded),
                    badges: [
                      if (level != null) UserLevelBadge(uid: x.firebaseUid, level: level),
                      if (clanOf(x) case final c?) c,
                      TopGiverChip(rank: x.rank, height: 16),
                    ],
                    onTap: () => openPublicProfile(context, x.firebaseUid),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
