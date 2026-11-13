import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/clan_tag_badge.dart';
import '../../components/net_image.dart';
import '../clan/clan_browse_screen.dart';
import '../clan/clan_chat_screen.dart';
import '../clan/clan_screen.dart';

/// Info singkat clan untuk bar pintasan di atas chat clan.
final _clanShortcutProvider = FutureProvider.autoDispose.family<Clan, String>(
  (ref, id) => ref.watch(clanRepositoryProvider).getClan(id),
);

/// Tab "Clan" di Chat Global: chat internal clan milik user. Kalau user belum
/// gabung clan, tampil ajakan cari clan (server tetap menolak akses non-member).
class ClanChatTab extends ConsumerWidget {
  const ClanChatTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(myClanMembershipProvider);
    return membership.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      ),
      error: (_, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Gagal memuat data clan',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(myClanMembershipProvider),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
      data: (m) {
        if (m == null) return _NoClan(onFind: () => _openBrowse(context, ref));
        // key per clan: pindah clan = controller & state chat baru.
        return Column(
          children: [
            _ClanShortcutBar(clanId: m.clanId),
            Expanded(
              child: ClanChatPane(key: ValueKey('clan-chat-${m.clanId}'), myRole: m.role),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openBrowse(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(fadeRoute(const ClanBrowseScreen()));
    // Balik dari daftar clan: user mungkin baru join.
    ref.invalidate(myClanMembershipProvider);
  }
}

class _NoClan extends StatelessWidget {
  const _NoClan({required this.onFind});

  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            const Text(
              'Kamu belum gabung clan',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gabung atau bikin clan dulu buat ikut chat internal clan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
              onPressed: onFind,
              child: const Text('Cari Clan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pintasan ke halaman Clan dari tab Clan di chat (saran user).
class _ClanShortcutBar extends ConsumerWidget {
  const _ClanShortcutBar({required this.clanId});

  final String clanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clan = ref.watch(_clanShortcutProvider(clanId)).valueOrNull;
    final photo = clan?.photoUrl ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.of(context).push<void>(fadeRoute(ClanScreen(clanId: clanId)));
            // Balik dari halaman clan: mungkin keluar / pindah clan.
            ref.invalidate(myClanMembershipProvider);
            ref.invalidate(_clanShortcutProvider(clanId));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: photo.isEmpty
                        ? const ColoredBox(
                            color: AppColors.surfaceVariantDark,
                            child: Icon(Icons.shield_rounded, size: 18, color: AppColors.textMuted),
                          )
                        : NetImage(photo),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (clan != null && clan.tag.isNotEmpty) ...[
                            ClanTagBadge.known(text: clan.tag, styleId: clan.badgeStyle, height: 15),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              clan?.name ?? 'Clan kamu',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textWhite,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (clan != null)
                        Text(
                          'Lv ${clan.level} · ${clan.memberCount}/${clan.memberLimit} anggota',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Buka Clan',
                  style: TextStyle(
                    color: AppColors.accentViolet,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.accentViolet),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
