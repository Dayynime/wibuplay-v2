import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../../data/repository/clan_repository.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';
import '../../components/role_badges.dart';
import '../../app_routes.dart';
import '../../components/hero_slides.dart' show heroGold;
import 'clan_chat_screen.dart';
import 'clan_daily_card.dart';
import 'clan_manage_screen.dart';
import 'clan_widgets.dart';
import '../profile/public_profile_screen.dart';
import '../../glass/glass.dart';
import '../../components/clan_tag_badge.dart';
import '../../components/user_level_badge.dart';
import '../../components/net_image.dart';
import '../../redesign/z_kit.dart';

String _thousands(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Detail clan: header (nama, tag, level, progress XP, statistik), tombol
/// aksi (join / donasi / keluar), tab Members dan Donasi hari ini dengan
/// pencarian, filter role, dan urutan. Port ClanScreen.kt.
///
/// Kelola Clan ada di clan_manage_screen.dart, Buat Clan di
/// create_clan_screen.dart (tombol + di halaman daftar clan).
class ClanScreen extends ConsumerStatefulWidget {
  const ClanScreen({super.key, required this.clanId});

  final String clanId;

  @override
  ConsumerState<ClanScreen> createState() => _ClanScreenState();
}

class _ClanScreenState extends ConsumerState<ClanScreen> {
  int _tab = 0; // 0 = Members, 1 = Donasi
  String _query = '';
  String? _roleFilter;
  bool _sortAsc = false;
  bool _joining = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _refreshAll() {
    ref.invalidate(clanDetailProvider(widget.clanId));
    ref.invalidate(allClansProvider);
    ref.invalidate(myClanMembershipProvider);
  }

  Future<void> _join(String? joinMode) async {
    setState(() => _joining = true);
    try {
      await ref.read(clanRepositoryProvider).submitJoinRequest(widget.clanId);
      _refreshAll();
      _toast(joinMode == ClanJoinMode.open
          ? 'Selamat, kamu sekarang anggota clan ini!'
          : 'Request join terkirim, tunggu di-approve leader/officer ya');
    } on ClanException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _donate() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _DonateDialog(
        onSubmit: (amount) =>
            ref.read(clanRepositoryProvider).donate(widget.clanId, amount),
      ),
    );
    if (done == true) {
      _refreshAll();
      _toast('Donasi berhasil, terima kasih!');
    }
  }

  Future<void> _openManage(ClanDetailData d) async {
    final deleted = await Navigator.of(context).push<bool>(
      fadeRoute(ClanManageScreen(clanId: widget.clanId, myRole: d.myRole ?? ClanRoles.member)),
    );
    if (deleted == true) {
      // Clan sudah dibubarkan leader: jangan refetch clan yang sudah tidak ada.
      ref.invalidate(allClansProvider);
      ref.invalidate(myClanMembershipProvider);
      if (!mounted) return;
      _toast('Clan berhasil dibubarkan');
      Navigator.of(context).maybePop();
      return;
    }
    // Balik dari Kelola Clan: member/kuota mungkin berubah.
    _refreshAll();
  }

  Future<void> _memberAction(ClanDetailData d, ClanMemberDisplay m) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _MemberActionDialog(
        clanId: widget.clanId,
        target: m,
        actorRole: d.myRole,
      ),
    );
    if (changed == true) _refreshAll();
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Keluar Clan?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Kamu akan keluar dari clan ini. Kontribusi donasimu tidak dikembalikan.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar', style: TextStyle(color: Color(0xFFFF8A98))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(clanRepositoryProvider).leaveClan(widget.clanId);
      ref.invalidate(allClansProvider);
      ref.invalidate(myClanMembershipProvider);
      if (!mounted) return;
      _toast('Kamu sudah keluar dari clan');
      Navigator.of(context).maybePop();
    } on ClanException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(clanDetailProvider(widget.clanId));
    // Tanpa app bar: banner clan sampai ke atas layar, tombol kembali
    // mengambang di atas banner (tata letak preview).
    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: detail.when(
        loading: () => _bare(
          const Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3)),
        ),
        error: (e, _) => _bare(
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e is ClanException ? e.message : 'Gagal ambil data clan',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(clanDetailProvider(widget.clanId)),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
        data: _content,
      ),
    );
  }

  /// Layar loading / gagal: tetap ada tombol kembali.
  Widget _bare(Widget child) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _FloatingIcon(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _content(ClanDetailData d) {
    final q = _query.trim().toLowerCase();

    final members = d.members.where((m) {
      if (_roleFilter != null && m.role != _roleFilter) return false;
      return q.isEmpty ||
          m.username.toLowerCase().contains(q) ||
          m.firebaseUid.toLowerCase().contains(q) ||
          (m.userNumber?.toString().contains(q) ?? false);
    }).toList();
    if (_sortAsc) {
      // Urut role terendah dulu; index ikut jadi pembanding biar stabil.
      final indexed = members.asMap().entries.toList()
        ..sort((a, b) {
          final r = ClanRoles.rank(a.value.role).compareTo(ClanRoles.rank(b.value.role));
          return r != 0 ? r : a.key.compareTo(b.key);
        });
      members
        ..clear()
        ..addAll(indexed.map((e) => e.value));
    }

    final donations = d.donations.where((x) {
      return q.isEmpty ||
          x.username.toLowerCase().contains(q) ||
          x.firebaseUid.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => _sortAsc
          ? a.amountToday.compareTo(b.amountToday)
          : b.amountToday.compareTo(a.amountToday));

    // 3 donatur teratas hari ini (tidak ikut filter/cari).
    final topDonors = [...d.donations]..sort((a, b) => b.amountToday.compareTo(a.amountToday));

    final memberByUid = {for (final m in d.members) m.firebaseUid: m};
    final isMembersTab = _tab == 0;
    final itemCount = isMembersTab ? members.length : donations.length;
    final isMember = d.myRole != null;
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.accentViolet,
          edgeOffset: topPad,
          onRefresh: () async => ref.refresh(clanDetailProvider(widget.clanId).future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _HeaderCard(
                  data: d,
                  myLevel: d.myUid.isEmpty
                      ? null
                      : ref.watch(myXpProvider(d.myUid)).whenOrNull(data: (x) => x?.level ?? 1),
                  joining: _joining,
                  onJoin: () => _join(d.clan.joinMode),
                  onDonate: _donate,
                  onLeave: _leave,
                  onManage: () => _openManage(d),
                ),
              ),
              // Absen harian: hanya untuk anggota clan ini (server tetap memverifikasi).
              if (isMember)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: ClanDailyCard(),
                  ),
                ),
              if (topDonors.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: _TopDonors(
                      donors: topDonors.take(3).toList(),
                      onSeeAll: () => setState(() => _tab = 1),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                  child: Column(
                    children: [
                      ClanSegment(
                        labels: ['Member · ${d.members.length}', 'Donasi'],
                        selected: _tab,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                      const SizedBox(height: 10),
                      if (!isMembersTab) ...[
                        _DonationSummary(data: d),
                        const SizedBox(height: 10),
                      ],
                      _SearchRow(
                        hint: isMembersTab ? 'Cari member (nama atau ID)' : 'Cari donatur',
                        sortAsc: _sortAsc,
                        onQuery: (v) => setState(() => _query = v),
                        onSort: () => setState(() => _sortAsc = !_sortAsc),
                      ),
                      if (isMembersTab) ...[
                        const SizedBox(height: 10),
                        _RoleFilterRow(
                          selected: _roleFilter,
                          onChanged: (r) => setState(() => _roleFilter = r),
                        ),
                      ],
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              if (itemCount == 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        isMembersTab ? 'Member tidak ditemukan.' : 'Belum ada donasi hari ini.',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, isMember ? 96 + bottomPad : 28 + bottomPad),
                  sliver: SliverList.builder(
                    itemCount: itemCount,
                    itemBuilder: (context, i) {
                      final Widget row;
                      if (isMembersTab) {
                        final m = members[i];
                        row = _MemberRow(
                          member: m,
                          clanTag: d.clan.tag,
                          level: d.levels[m.firebaseUid],
                          isPremium: d.premiumUids.contains(m.firebaseUid),
                          isMe: m.firebaseUid == d.myUid,
                          onAction: m.firebaseUid != d.myUid && ClanRoles.canActOn(d.myRole, m.role)
                              ? () => _memberAction(d, m)
                              : null,
                        );
                      } else {
                        final e = donations[i];
                        row = _DonationRow(
                          rank: i + 1,
                          entry: e,
                          member: memberByUid[e.firebaseUid],
                          showRank: !_sortAsc && q.isEmpty,
                          isMe: e.firebaseUid == d.myUid,
                        );
                      }
                      return _PanelRow(first: i == 0, last: i == itemCount - 1, child: row);
                    },
                  ),
                ),
            ],
          ),
        ),
        // Tombol kembali mengambang di atas banner.
        Positioned(
          top: topPad + 8,
          left: 12,
          child: _FloatingIcon(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
        ),
        // Chat Clan mengambang: hanya untuk member clan ini (server tetap
        // memverifikasi keanggotaan di setiap request).
        if (isMember)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + bottomPad,
            child: _ChatClanButton(
              onTap: () => Navigator.of(context).push<void>(
                fadeRoute(ClanChatScreen(clanName: d.clan.name, myRole: d.myRole!)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Satu baris di dalam panel daftar: sudut membulat di baris pertama/terakhir,
/// garis pemisah tipis di antara baris.
class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.first, required this.last, required this.child});

  final bool first;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: clanSurface,
        borderRadius: BorderRadius.vertical(
          top: first ? const Radius.circular(18) : Radius.zero,
          bottom: last ? const Radius.circular(18) : Radius.zero,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!first) const Divider(height: 1, thickness: 1, indent: 12, endIndent: 12, color: clanBorder),
          child,
        ],
      ),
    );
  }
}

class _FloatingIcon extends StatelessWidget {
  const _FloatingIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x8C06111D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20, color: Colors.white)),
      ),
    );
  }
}

class _ChatClanButton extends StatelessWidget {
  const _ChatClanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZPress(
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [AppColors.accentViolet, AppColors.accentVioletDark]),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentViolet.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 10),
              spreadRadius: -12,
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.forum_rounded, size: 20, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Chat Clan',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// Tiga donatur teratas hari ini (kartu emas / perak / perunggu).
class _TopDonors extends StatelessWidget {
  const _TopDonors({required this.donors, required this.onSeeAll});

  final List<ClanDonationEntry> donors;
  final VoidCallback onSeeAll;

  static const _medal = [Color(0xFFF6BE4F), Color(0xFFD5DEEC), Color(0xFFF0A35E)];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('寄付', style: ZFont.jp(size: 10)),
                  Text('Donatur hari ini', style: ZFont.display(size: 17)),
                ],
              ),
            ),
            GestureDetector(
              onTap: onSeeAll,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Text(
                  'Semua',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: i < donors.length
                    ? GestureDetector(
                        onTap: () => openPublicProfile(context, donors[i].firebaseUid),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: clanBorder),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [clanSurface, Color.lerp(clanSurface, _medal[i], 0.18)!],
                            ),
                          ),
                          child: Column(
                            children: [
                              Text('#${i + 1}', style: ZFont.display(size: 12.5, color: _medal[i])),
                              const SizedBox(height: 6),
                              RepaintBoundary(
                                child: UserAvatar(
                                  username: donors[i].username,
                                  url: donors[i].avatarUrl,
                                  size: 40,
                                  frameUid: donors[i].firebaseUid,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                donors[i].username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                _thousands(donors[i].amountToday),
                                style: const TextStyle(color: Color(0xFFF6BE4F), fontSize: 11.5, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ header

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.data,
    required this.myLevel,
    required this.joining,
    required this.onJoin,
    required this.onDonate,
    required this.onLeave,
    required this.onManage,
  });

  final ClanDetailData data;

  /// Level XP user yang login (null = belum termuat / tidak login).
  final int? myLevel;
  final bool joining;
  final VoidCallback onJoin;
  final VoidCallback onDonate;
  final VoidCallback onLeave;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final c = data.clan;
    final floor = clanXpFloor(c.level);
    final ceil = clanXpFloor(c.level + 1);
    final current = c.totalXp > floor ? c.totalXp - floor : 0;
    final needed = (ceil - floor) < 1 ? 1 : (ceil - floor);
    final progress = (current / needed).clamp(0.0, 1.0).toDouble();
    final topPad = MediaQuery.paddingOf(context).top;
    final hasPhoto = c.photoUrl != null && c.photoUrl!.isNotEmpty;
    final desc = (c.description ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner + lambang clan yang menimpa banner.
        SizedBox(
          height: topPad + 230,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: topPad + 170,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasPhoto) ...[
                      NetImage(c.photoUrl!),
                      // Digelapkan supaya teks & tombol tetap terbaca (tanpa Opacity
                      // layer yang mahal).
                      const ColoredBox(color: Color(0x9906111D)),
                    ] else
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF10345A), Color(0xFF0B1C33), Color(0xFF07121F)],
                          ),
                        ),
                      ),
                    const Positioned(right: -60, top: -70, child: ClanGlow(color: heroGold, size: 240)),
                    const Positioned(left: -70, bottom: -90, child: ClanGlow(color: AppColors.accentViolet, size: 240)),
                    const ZScreentone(opacity: 0.16),
                    // Tag clan besar & samar di pojok kanan bawah banner.
                    Positioned(
                      right: 14,
                      bottom: 6,
                      child: Text(
                        c.tag,
                        style: ZFont.display(size: 64, color: const Color(0x12FFFFFF), height: 1),
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.35, 0.75, 1],
                          colors: [Color(0x5906111D), Color(0x0006111D), Color(0x9906111D), AppColors.backgroundDark],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFF6BE4F), AppColors.accentViolet, AppColors.accentTeal],
                        ),
                        boxShadow: const [
                          BoxShadow(color: Color(0xCC000000), blurRadius: 26, offset: Offset(0, 14), spreadRadius: -12),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundDark,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: ClanAvatar(tag: c.tag, url: c.photoUrl, size: 80),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: ZFont.display(size: 23, height: 1.05),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ClanTagBadge.known(text: c.tag, styleId: c.badgeStyle),
                                LevelBadge(level: c.level),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AccessChips(clan: c),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  desc,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Menuju Level ${c.level + 1}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                  Text(
                    '${formatCompact(current)} / ${formatCompact(needed)} XP',
                    style: const TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0x14FFFFFF)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            gradient: LinearGradient(colors: [AppColors.accentViolet, AppColors.accentTeal]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Angka tanpa kartu, dipisah garis tipis.
              IntrinsicHeight(
                child: Row(
                  children: [
                    _Stat(value: formatCompact(c.totalXp), label: 'Total XP'),
                    const VerticalDivider(width: 1, thickness: 1, color: clanBorder),
                    _Stat(value: '${c.memberCount}/${c.memberLimit}', label: 'Member'),
                    const VerticalDivider(width: 1, thickness: 1, color: clanBorder),
                    _Stat(value: formatCompact(data.totalDonatedToday), label: 'Donasi hari ini'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _actions(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _joinAction(Clan c) {
    if (c.joinMode == ClanJoinMode.closed) {
      return const _StatusPill('Clan Tertutup', icon: Icons.lock_rounded,
          note: 'Clan ini sedang tidak menerima member baru.');
    }
    if (c.joinMode == ClanJoinMode.invite) {
      return const _StatusPill('Hanya Lewat Undangan', icon: Icons.mail_lock_rounded,
          note: 'Minta undangan ke member clan ini.');
    }
    final lvl = myLevel;
    if (lvl != null && lvl < c.minLevel) {
      return _StatusPill('Butuh Level ${c.minLevel}', icon: Icons.trending_up_rounded,
          note: 'Level kamu sekarang $lvl. Naikkan XP dengan menonton.');
    }
    final open = c.joinMode == ClanJoinMode.open;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClanGradientButton(
          text: open ? 'Gabung Sekarang' : 'Ajukan Gabung',
          icon: open ? Icons.login_rounded : Icons.person_add_alt_1_rounded,
          loading: joining,
          onTap: onJoin,
        ),
        const SizedBox(height: 8),
        Text(
          open ? 'Siapa saja bisa langsung gabung.' : 'Leader atau officer akan menyetujui permintaanmu.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _actions() {
    switch (data.cta) {
      case ClanCta.login:
        return const _StatusPill('Login dulu untuk gabung clan', icon: Icons.login_rounded);
      case ClanCta.join:
        return _joinAction(data.clan);
      case ClanCta.pending:
        return const _StatusPill('Menunggu Persetujuan', icon: Icons.schedule_rounded,
            note: 'Permintaan terkirim. Tunggu disetujui leader/officer.');
      case ClanCta.blockedOtherClan:
        return const _StatusPill('Kamu Sudah Gabung Clan Lain', icon: Icons.lock_rounded,
            note: 'Keluar dari clan lamamu dulu untuk gabung ke sini.');
      case ClanCta.member:
        return Row(
          children: [
            Expanded(
              child: ClanGradientButton(
                text: 'Donasi ZCoin',
                icon: Icons.diamond_rounded,
                gold: true,
                onTap: onDonate,
              ),
            ),
            // Officer ke atas boleh buka Kelola Clan.
            if (ClanRoles.canManageClan(data.myRole)) ...[
              const SizedBox(width: 8),
              ClanSquareButton(icon: Icons.settings_rounded, tooltip: 'Kelola Clan', onTap: onManage),
            ],
            // Leader tidak bisa keluar biasa: jadikan member lain Leader dulu
            // (ketuk nama member > Jadikan Leader), atau bubarkan clan.
            if (data.myRole != ClanRoles.leader) ...[
              const SizedBox(width: 8),
              ClanSquareButton(
                icon: Icons.logout_rounded,
                tooltip: 'Keluar Clan',
                color: const Color(0xFFFF8A98),
                onTap: onLeave,
              ),
            ],
          ],
        );
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, maxLines: 1, style: ZFont.display(size: 19, height: 1.1)),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text, {this.icon, this.note});

  final String text;
  final IconData? icon;

  /// Penjelasan singkat di bawah tombol.
  final String? note;

  @override
  Widget build(BuildContext context) {
    const color = AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariantDark,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: clanBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note!, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
        ],
      ],
    );
  }
}

/// Chip kecil: mode join clan + level minimal.
class _AccessChips extends StatelessWidget {
  const _AccessChips({required this.clan});

  final Clan clan;

  static (IconData, Color) _style(String? mode) {
    switch (mode) {
      case ClanJoinMode.open:
        return (Icons.lock_open_rounded, const Color(0xFF34D399));
      case ClanJoinMode.invite:
        return (Icons.mail_lock_rounded, const Color(0xFF60A5FA));
      case ClanJoinMode.closed:
        return (Icons.lock_rounded, const Color(0xFFFF8A98));
      default:
        return (Icons.how_to_reg_rounded, heroGold);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style(clan.joinMode);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _chip(icon, ClanJoinMode.label(clan.joinMode), color),
        if (clan.minLevel > 1)
          _chip(Icons.military_tech_rounded, 'Min. Level ${clan.minLevel}', AppColors.accentVioletLight),
      ],
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- tab / search / filter

class _DonationSummary extends StatelessWidget {
  const _DonationSummary({required this.data});

  final ClanDetailData data;

  @override
  Widget build(BuildContext context) {
    final memberCount =
        data.clan.memberCount > 0 ? data.clan.memberCount : data.members.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0x14F6BE4F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x38F6BE4F)),
      ),
      child: Text(
        'Hari ini · ${data.donations.length} dari $memberCount member donasi · ${_thousands(data.totalDonatedToday)} ZCoin',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.hint,
    required this.sortAsc,
    required this.onQuery,
    required this.onSort,
  });

  final String hint;
  final bool sortAsc;
  final ValueChanged<String> onQuery;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: onQuery,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: AppColors.accentViolet,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
              filled: true,
              fillColor: clanSurface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: clanBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.accentViolet),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: clanSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: clanBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onSort,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                sortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: AppColors.accentVioletLight,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleFilterRow extends StatelessWidget {
  const _RoleFilterRow({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? role) {
      final on = selected == role;
      final color = role == null ? AppColors.accentViolet : clanRoleColor(role);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onChanged(role),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: on ? color.withValues(alpha: 0.18) : clanSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? color.withValues(alpha: 0.6) : clanBorder),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: on ? Colors.white : AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('Semua', null),
          for (final r in ClanRoles.all)
            chip(r == ClanRoles.officer ? 'Officer' : _title(ClanRoles.label(r)), r),
        ],
      ),
    );
  }

  static String _title(String upper) => upper
      .toLowerCase()
      .split(' ')
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

// ---------------------------------------------------------------------- rows

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.clanTag,
    required this.level,
    required this.isPremium,
    required this.isMe,
    this.onAction,
  });

  final ClanMemberDisplay member;
  final String clanTag;
  final int? level;
  final bool isPremium;
  final bool isMe;

  /// Menu titik tiga (ubah role / kick); null = tidak punya izin.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openPublicProfile(context, member.firebaseUid),
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 10, onAction == null ? 12 : 4, 10),
        color: isMe ? AppColors.accentViolet.withValues(alpha: 0.08) : null,
        child: Row(
          children: [
            RepaintBoundary(
              child: UserAvatar(
                username: member.username,
                url: member.avatarUrl,
                size: 42,
                frameUid: member.firebaseUid,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // username > centang Premium > #ID (urutan sama seperti Chat Global).
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.username + (isMe ? ' (Kamu)' : ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: UserCheckBadge(firebaseUid: member.firebaseUid, isPremium: isPremium, size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (level != null) UserLevelBadge(uid: member.firebaseUid, level: level!),
                      if (member.userNumber != null)
                        Text('#${member.userNumber}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      GemPill(amount: member.totalContribution),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ClanRoleChip(role: member.role),
            if (onAction != null)
              IconButton(
                onPressed: onAction,
                tooltip: 'Kelola member',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 40),
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _DonationRow extends StatelessWidget {
  const _DonationRow({
    required this.rank,
    required this.entry,
    required this.member,
    required this.showRank,
    this.isMe = false,
  });

  final int rank;
  final ClanDonationEntry entry;
  final ClanMemberDisplay? member;
  final bool showRank;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final medal = showRank ? clanMedal(rank) : null;
    final joined = member == null ? '' : formatJoinShort(member!.joinedAt);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openPublicProfile(context, entry.firebaseUid),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        color: isMe ? AppColors.accentViolet.withValues(alpha: 0.08) : null,
        child: Row(
          children: [
            if (showRank) ...[
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: ZFont.display(size: 14, color: medal ?? AppColors.textMuted, height: 1),
                ),
              ),
              const SizedBox(width: 8),
            ],
            RepaintBoundary(
              child: UserAvatar(username: entry.username, url: entry.avatarUrl, size: 42, frameUid: entry.firebaseUid),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.username + (isMe ? ' (Kamu)' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      ClanRoleChip(role: entry.role),
                      if (member != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Total ${formatCompact(member!.totalContribution)}${joined.isEmpty ? '' : ' · Gabung $joined'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_thousands(entry.amountToday), style: ZFont.display(size: 15, color: const Color(0xFFF6BE4F))),
                const Text('ZCoin', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- dialog

class _DonateDialog extends StatefulWidget {
  const _DonateDialog({required this.onSubmit});

  final Future<void> Function(int amount) onSubmit;

  @override
  State<_DonateDialog> createState() => _DonateDialogState();
}

class _DonateDialogState extends State<_DonateDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_ctrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Masukin jumlah ZCoin yang valid');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(amount);
      if (mounted) Navigator.of(context).pop(true);
    } on ClanException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: const Text('Donasi ZCoin', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            style: const TextStyle(color: Colors.white),
            cursorColor: AppColors.accentViolet,
            decoration: const InputDecoration(
              labelText: 'Jumlah ZCoin',
              prefixIcon: Icon(Icons.diamond_rounded, color: clanGemBlue, size: 18),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF8A98), fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Donasi'),
        ),
      ],
    );
  }
}

/// Menu aksi member: ubah role (sesuai hierarki), jadikan leader (khusus
/// leader), atau kick (dengan konfirmasi). Pop(true) kalau ada perubahan.
class _MemberActionDialog extends ConsumerStatefulWidget {
  const _MemberActionDialog({
    required this.clanId,
    required this.target,
    required this.actorRole,
  });

  final String clanId;
  final ClanMemberDisplay target;
  final String? actorRole;

  @override
  ConsumerState<_MemberActionDialog> createState() => _MemberActionDialogState();
}

class _MemberActionDialogState extends ConsumerState<_MemberActionDialog> {
  bool _confirmKick = false;
  bool _confirmTransfer = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } on ClanException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    final repo = ref.read(clanRepositoryProvider);
    final assignable = ClanRoles.assignableRoles(widget.actorRole, t.role);
    final canKick = ClanRoles.canKick(widget.actorRole, t.role);
    final canTransfer = widget.actorRole == ClanRoles.leader;
    final confirming = _confirmKick || _confirmTransfer;

    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: Text(t.username, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_confirmKick)
            Text(
              'Yakin mau kick ${t.username} dari clan?',
              style: const TextStyle(color: AppColors.textSecondary),
            )
          else if (_confirmTransfer)
            Text(
              '${t.username} akan jadi Leader clan ini. Kamu turun jadi Vice Leader '
              'dan tidak bisa mengambil jabatan Leader kembali tanpa diberikan olehnya.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
            )
          else ...[
            Row(
              children: [
                const Text(
                  'Role sekarang:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(width: 8),
                ClanRoleChip(role: t.role),
              ],
            ),
            if (assignable.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Ubah jadi:',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              for (final role in assignable)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => repo.setMemberRole(widget.clanId, t.firebaseUid, role)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: clanRoleColor(role).withValues(alpha: 0.6)),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        ClanRoles.label(role),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
            ],
            if (canTransfer) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => setState(() => _confirmTransfer = true),
                  icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                  label: const Text('Jadikan Leader', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: clanRoleColor(ClanRoles.leader).withValues(alpha: 0.8)),
                    foregroundColor: clanRoleColor(ClanRoles.leader),
                  ),
                ),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF8A98), fontSize: 12)),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  if (confirming) {
                    setState(() {
                      _confirmKick = false;
                      _confirmTransfer = false;
                    });
                  } else {
                    Navigator.of(context).pop(false);
                  }
                },
          child: Text(confirming ? 'Batal' : 'Tutup'),
        ),
        if (_confirmTransfer)
          TextButton(
            onPressed: _busy ? null : () => _run(() => repo.transferLeader(widget.clanId, t.firebaseUid)),
            child: Text(
              'Jadikan Leader',
              style: TextStyle(color: clanRoleColor(ClanRoles.leader), fontWeight: FontWeight.w800),
            ),
          )
        else if (_confirmKick)
          TextButton(
            onPressed: _busy ? null : () => _run(() => repo.kickMember(widget.clanId, t.firebaseUid)),
            child: const Text(
              'Kick',
              style: TextStyle(color: Color(0xFFFF8A98), fontWeight: FontWeight.w800),
            ),
          )
        else if (canKick)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _confirmKick = true),
            child: const Text(
              'Kick Member',
              style: TextStyle(color: Color(0xFFFF8A98), fontWeight: FontWeight.w800),
            ),
          ),
      ],
    );
  }
}
