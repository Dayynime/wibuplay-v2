import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../auth/login_screen.dart';
import 'clan_screen.dart';
import 'create_clan_screen.dart';
import 'clan_widgets.dart';
import '../../glass/glass.dart';
import '../../components/clan_tag_badge.dart';
import '../../redesign/podium_kit.dart';
import '../../redesign/z_kit.dart';

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

  static const _modes = [ClanBrowseMode.all, ClanBrowseMode.leaderboard, ClanBrowseMode.mine];

  @override
  Widget build(BuildContext context) {
    final clans = ref.watch(allClansProvider);
    final myClanId = ref.watch(myClanMembershipProvider).valueOrNull?.clanId;

    // Isi panel: pesan (loading/gagal/kosong) atau baris clan.
    Widget? message;
    List<Clan> list = const [];
    var ranked = false;
    clans.when<void>(
      loading: () {
        message = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3)),
        );
      },
      error: (e, _) {
        message = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: _RetryView(
          message: 'Gagal ambil daftar clan',
          onRetry: () => ref.invalidate(allClansProvider),
        ),
        );
      },
      data: (all) {
        final q = _query.trim().toLowerCase();
        list = all.where((c) {
          if (_mode == ClanBrowseMode.mine && c.id != myClanId) return false;
          // Clan khusus (mis. admin) tidak ikut diperingkat.
          if (_mode == ClanBrowseMode.leaderboard && c.leaderboardHidden) return false;
          return q.isEmpty || c.name.toLowerCase().contains(q) || c.tag.toLowerCase().contains(q);
        }).toList();
        ranked = _mode == ClanBrowseMode.leaderboard && q.isEmpty;
        if (list.isEmpty) {
          message = Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                _mode == ClanBrowseMode.mine && myClanId == null
                    ? 'Kamu belum gabung clan mana pun.'
                    : 'Clan tidak ditemukan.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          );
        }
      },
    );

    final dividerText = switch (_mode) {
      ClanBrowseMode.leaderboard => 'Peringkat Teratas',
      ClanBrowseMode.all => 'Semua Clan',
      ClanBrowseMode.mine => 'Clan Saya',
    };
    // 0 kepala panel, 1 segmen, 2 judul pemisah, lalu isi, terakhir kaki panel.
    final bodyCount = message != null ? 1 : list.length;

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text('Clan', style: ZFont.display(size: 18)),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: AppColors.accentViolet,
              decoration: InputDecoration(
                hintText: 'Cari clan (nama atau tag)',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceDark,
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
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accentViolet,
              onRefresh: () async => ref.refresh(allClansProvider.future),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                itemCount: 3 + bodyCount + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return const ZPanelTop();
                  if (i == 1) {
                    return ZPanelBody(
                      child: ZPanelSegment(
                        labels: const ['Semua Clan', 'Leaderboard', 'Clan Saya'],
                        index: _modes.indexOf(_mode),
                        onChanged: (k) => setState(() => _mode = _modes[k]),
                      ),
                    );
                  }
                  if (i == 2) return ZPanelBody(child: ZPanelDivider(dividerText));
                  if (i == 3 + bodyCount) return const ZPanelBottom();
                  if (message != null) return ZPanelBody(child: message!);
                  final idx = i - 3;
                  final c = list[idx];
                  final isMine = c.id == myClanId;
                  return ZStaggerIn(
                    key: ValueKey('${_mode.name}-${c.id}'),
                    index: idx,
                    child: ZRankRow(
                      rank: idx + 1,
                      uid: c.id,
                      username: c.name,
                      isMe: isMine,
                      last: idx == list.length - 1,
                      avatar: ClanAvatar(tag: c.tag, url: c.photoUrl, size: 46),
                      nameTrailing: isMine ? const ZChip('KAMU', tone: ZTone.brand) : null,
                      value: ZGemValue(zGroupInt(c.totalXp), icon: Icons.shield_rounded),
                      badges: [
                        ClanTagBadge.known(text: c.tag, styleId: c.badgeStyle),
                        Text(
                          'Lv ${c.level} · ${c.memberCount}/${c.memberLimit}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                        ),
                      ],
                      // Tidak diperingkat (Semua/Clan Saya/hasil cari): panah biasa.
                      trailing: ranked
                          ? null
                          : const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                      onTap: () => Navigator.of(context).push<void>(
                        fadeRoute(ClanScreen(clanId: c.id)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
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
