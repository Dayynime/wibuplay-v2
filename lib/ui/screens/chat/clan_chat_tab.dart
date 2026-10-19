import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../clan/clan_browse_screen.dart';
import '../clan/clan_chat_screen.dart';

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
        return ClanChatPane(key: ValueKey('clan-chat-${m.clanId}'), myRole: m.role);
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
