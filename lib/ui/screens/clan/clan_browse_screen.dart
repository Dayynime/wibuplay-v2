import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/game_badges.dart';
import '../auth/login_screen.dart';
import 'clan_screen.dart';
import 'create_clan_screen.dart';
import 'clan_widgets.dart';

enum ClanBrowseMode { all, leaderboard, mine }

/// Daftar clan: Semua Clan / Leaderboard / Clan Saya + pencarian
/// (port BrowseClansScreen.kt, tampilan dimodernkan).
class ClanBrowseScreen extends ConsumerStatefulWidget {
  const ClanBrowseScreen({super.key, this.initialMode = ClanBrowseMode.leaderboard});

  final ClanBrowseMode initialMode;

  @override
  ConsumerState<ClanBrowseScreen> createState() => _ClanBrowseScreenState();
}

class _ClanBrowseScreenState extends ConsumerState<ClanBrowseScreen> {
  late ClanBrowseMode _mode = widget.initialMode;
  String _query = '';

  Future<void> _openCreateClan() async {
    var user = ref.read(authUserProvider).valueOrNull;
    if (user == null) {
      final ok = await Navigator.of(context).push<bool>(fadeRoute(const LoginScreen()));
      if (ok != true || !mounted) return;
      user = ref.read(authUserProvider).valueOrNull;
      if (user == null) return;
    }
    // Sudah punya clan -> tidak bisa bikin lagi (server juga menolak).
    final myClanId = ref.read(myClanMembershipProvider).valueOrNull?.clanId;
    if (myClanId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kamu sudah punya clan. Keluar dulu untuk bikin clan baru.')),
      );
      return;
    }
    final clanId = await Navigator.of(context).push<String>(
      fadeRoute(CreateClanScreen(firebaseUid: user.uid)),
    );
    if (clanId == null || !mounted) return;
    ref.invalidate(allClansProvider);
    ref.invalidate(myClanMembershipProvider);
    await Navigator.of(context).push<void>(fadeRoute(ClanScreen(clanId: clanId)));
  }

  @override
  Widget build(BuildContext context) {
    final clans = ref.watch(allClansProvider);
    final myClanId = ref.watch(myClanMembershipProvider).valueOrNull?.clanId;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        title: const Text('Clan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateClan,
        backgroundColor: AppColors.accentViolet,
        foregroundColor: Colors.white,
        tooltip: 'Buat Clan',
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: AppColors.accentViolet,
              decoration: InputDecoration(
                hintText: 'Cari clan (nama atau tag)',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                filled: true,
                fillColor: clanSurface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: clanBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.accentViolet),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ModeSwitch(
              mode: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: clans.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
              ),
              error: (e, _) => _RetryView(
                message: 'Gagal ambil daftar clan',
                onRetry: () => ref.invalidate(allClansProvider),
              ),
              data: (all) {
                final q = _query.trim().toLowerCase();
                var list = all.where((c) {
                  if (_mode == ClanBrowseMode.mine && c.id != myClanId) return false;
                  return q.isEmpty ||
                      c.name.toLowerCase().contains(q) ||
                      c.tag.toLowerCase().contains(q);
                }).toList();
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      _mode == ClanBrowseMode.mine && myClanId == null
                          ? 'Kamu belum gabung clan mana pun.'
                          : 'Clan tidak ditemukan.',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  );
                }
                final ranked = _mode == ClanBrowseMode.leaderboard && q.isEmpty;
                return RefreshIndicator(
                  color: AppColors.accentViolet,
                  onRefresh: () async => ref.refresh(allClansProvider.future),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _ClanCard(
                      clan: list[i],
                      rank: ranked ? i + 1 : null,
                      isMine: list[i].id == myClanId,
                      onTap: () => Navigator.of(context).push<void>(
                        fadeRoute(ClanScreen(clanId: list[i].id)),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final ClanBrowseMode mode;
  final ValueChanged<ClanBrowseMode> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (ClanBrowseMode.all, 'Semua Clan'),
      (ClanBrowseMode.leaderboard, 'Leaderboard'),
      (ClanBrowseMode.mine, 'Clan Saya'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: clanSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: clanBorder),
      ),
      child: Row(
        children: [
          for (final (m, label) in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: m == mode
                        ? const LinearGradient(
                            colors: [AppColors.accentViolet, Color(0xFFB06CF0)],
                          )
                        : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: m == mode ? Colors.white : AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClanCard extends StatelessWidget {
  const _ClanCard({
    required this.clan,
    required this.rank,
    required this.isMine,
    required this.onTap,
  });

  final Clan clan;
  final int? rank;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final medal = rank == null ? null : clanMedal(rank!);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: clanSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isMine ? AppColors.accentViolet.withValues(alpha: 0.7) : clanBorder,
            ),
          ),
          child: Row(
            children: [
              if (rank != null) ...[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: medal ?? Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      color: medal != null ? const Color(0xFF1B1200) : AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              ClanAvatar(tag: clan.tag, url: clan.photoUrl, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            clan.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentViolet.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'KAMU',
                              style: TextStyle(
                                color: AppColors.accentVioletLight,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ClanRainbowBadge(text: clan.tag),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Lv ${clan.level} · ${clan.memberCount}/${clan.memberLimit} member',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetryView extends StatelessWidget {
  const _RetryView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
