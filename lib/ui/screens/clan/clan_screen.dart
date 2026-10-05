import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../../data/repository/clan_repository.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';
import '../../app_routes.dart';
import '../../components/hero_slides.dart' show heroGold;
import 'clan_manage_screen.dart';
import 'clan_widgets.dart';

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
/// Belum dipindah dari Zenime: Kelola Clan (kick, ubah role, terima request
/// join) dan Buat Clan.
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

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      await ref.read(clanRepositoryProvider).submitJoinRequest(widget.clanId);
      _refreshAll();
      _toast('Request join terkirim, tunggu di-approve leader/officer ya');
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
    await Navigator.of(context).push<void>(
      fadeRoute(ClanManageScreen(clanId: widget.clanId, myRole: d.myRole ?? ClanRoles.member)),
    );
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
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        title: const Text('Clan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: detail.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
        ),
        error: (e, _) => Center(
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
        data: _content,
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

    final memberByUid = {for (final m in d.members) m.firebaseUid: m};
    final isMembersTab = _tab == 0;
    final itemCount = isMembersTab ? members.length : donations.length;

    return RefreshIndicator(
      color: AppColors.accentViolet,
      onRefresh: () async => ref.refresh(clanDetailProvider(widget.clanId).future),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: _HeaderCard(
                data: d,
                joining: _joining,
                onJoin: _join,
                onDonate: _donate,
                onLeave: _leave,
                onManage: () => _openManage(d),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _TabSwitch(selected: _tab, onChanged: (t) => setState(() => _tab = t)),
                  const SizedBox(height: 12),
                  if (!isMembersTab) ...[
                    _DonationSummary(data: d),
                    const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
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
                    isMembersTab
                        ? 'Member tidak ditemukan.'
                        : 'Belum ada donasi hari ini.',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverList.separated(
                itemCount: itemCount,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  if (isMembersTab) {
                    final m = members[i];
                    return _MemberRow(
                      member: m,
                      clanTag: d.clan.tag,
                      level: d.levels[m.firebaseUid],
                      isPremium: d.premiumUids.contains(m.firebaseUid),
                      isMe: m.firebaseUid == d.myUid,
                      onAction: m.firebaseUid != d.myUid && ClanRoles.canActOn(d.myRole, m.role)
                          ? () => _memberAction(d, m)
                          : null,
                    );
                  }
                  final e = donations[i];
                  return _DonationRow(
                    rank: i + 1,
                    entry: e,
                    member: memberByUid[e.firebaseUid],
                    showRank: !_sortAsc && q.isEmpty,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ header

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.data,
    required this.joining,
    required this.onJoin,
    required this.onDonate,
    required this.onLeave,
    required this.onManage,
  });

  final ClanDetailData data;
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

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2A4C), Color(0xFF0E1428)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(right: -60, top: -70, child: ClanGlow(color: heroGold, size: 200)),
          const Positioned(
            left: -70,
            bottom: -90,
            child: ClanGlow(color: AppColors.accentViolet, size: 230),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClanAvatar(tag: c.tag, url: c.photoUrl, size: 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ClanRainbowBadge(text: c.tag),
                              const SizedBox(width: 8),
                              LevelBadge(level: c.level),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Menuju Level ${c.level + 1}',
                      style: const TextStyle(color: Color(0xA6FFFFFF), fontSize: 12),
                    ),
                    Text(
                      '${formatCompact(current)} / ${formatCompact(needed)} XP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: Stack(
                    children: [
                      Container(height: 8, color: const Color(0x1FFFFFFF)),
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          height: 8,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.accentViolet, Color(0xFFFF5C8A)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Stat(
                      icon: Icons.bolt_rounded,
                      color: const Color(0xFF4FC3F7),
                      value: formatCompact(c.totalXp),
                      label: 'Total XP',
                    ),
                    const SizedBox(width: 8),
                    _Stat(
                      icon: Icons.groups_rounded,
                      color: AppColors.accentVioletLight,
                      value: '${c.memberCount}/${c.memberLimit}',
                      label: 'Member',
                    ),
                    const SizedBox(width: 8),
                    _Stat(
                      icon: Icons.diamond_rounded,
                      color: clanGemBlue,
                      value: formatCompact(data.totalDonatedToday),
                      label: 'Donasi hari ini',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _actions(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    switch (data.cta) {
      case ClanCta.login:
        return const _StatusPill('Login dulu untuk gabung clan');
      case ClanCta.join:
        return ClanGradientButton(
          text: 'Join Clan',
          icon: Icons.person_add_alt_1_rounded,
          loading: joining,
          onTap: onJoin,
        );
      case ClanCta.pending:
        return const _StatusPill('Menunggu Persetujuan');
      case ClanCta.blockedOtherClan:
        return const _StatusPill('Kamu Sudah Gabung Clan Lain');
      case ClanCta.member:
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ClanGradientButton(
                    text: 'Donasi ZCoin',
                    icon: Icons.diamond_rounded,
                    onTap: onDonate,
                  ),
                ),
                // Officer ke atas boleh buka Kelola Clan.
                if (ClanRoles.canManageClan(data.myRole)) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _GlassButton(text: 'Kelola Clan', onTap: onManage)),
                ],
              ],
            ),
            // Leader tidak bisa keluar biasa (harus transfer/bubarkan clan dulu).
            if (data.myRole != ClanRoles.leader)
              TextButton(
                onPressed: onLeave,
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                child: const Text(
                  'Keluar Clan',
                  style: TextStyle(color: Color(0xFFFF8A98), fontWeight: FontWeight.w700),
                ),
              ),
          ],
        );
    }
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x0FFFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0x8CFFFFFF),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ------------------------------------------------------- tab / search / filter

class _TabSwitch extends StatelessWidget {
  const _TabSwitch({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Members', 'Donasi'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: clanSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: clanBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: i == selected
                        ? const LinearGradient(
                            colors: [AppColors.accentViolet, Color(0xFFB06CF0)],
                          )
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == selected ? Colors.white : AppColors.textSecondary,
                      fontSize: 14,
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
        color: AppColors.accentViolet.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentViolet.withValues(alpha: 0.35)),
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
              color: on ? color.withValues(alpha: 0.22) : Colors.transparent,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: on ? color : clanBorder),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: clanSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? AppColors.accentViolet.withValues(alpha: 0.7) : clanBorder,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 58,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                UserAvatar(username: member.username, url: member.avatarUrl, size: 48),
                Positioned(
                  bottom: 0,
                  left: -12,
                  right: -12,
                  child: Center(child: ClanRoleChip(role: member.role)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // username > centang Premium > #ID (urutan sama seperti Chat Global).
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isPremium) ...[
                      const SizedBox(width: 4),
                      const PremiumCheckBadge(size: 15),
                    ],
                    if (member.userNumber != null) ...[
                      const SizedBox(width: 5),
                      Text(
                        '#${member.userNumber}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ClanRainbowBadge(text: clanTag),
                    if (level != null) ...[
                      const SizedBox(width: 6),
                      LevelBadge(level: level!),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GemPill(amount: member.totalContribution),
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
    );
  }
}

class _DonationRow extends StatelessWidget {
  const _DonationRow({
    required this.rank,
    required this.entry,
    required this.member,
    required this.showRank,
  });

  final int rank;
  final ClanDonationEntry entry;
  final ClanMemberDisplay? member;
  final bool showRank;

  @override
  Widget build(BuildContext context) {
    final medal = showRank ? clanMedal(rank) : null;
    final joined = member == null ? '' : formatJoinShort(member!.joinedAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: clanSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: clanBorder),
      ),
      child: Row(
        children: [
          if (showRank) ...[
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: medal ?? Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  color: medal != null ? const Color(0xFF1B1200) : AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          UserAvatar(username: entry.username, url: entry.avatarUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
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
          GemPill(amount: entry.amountToday),
        ],
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

/// Menu aksi member: ubah role (sesuai hierarki) atau kick (dengan konfirmasi).
/// Pop(true) kalau ada perubahan.
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
                  if (_confirmKick) {
                    setState(() => _confirmKick = false);
                  } else {
                    Navigator.of(context).pop(false);
                  }
                },
          child: Text(_confirmKick ? 'Batal' : 'Tutup'),
        ),
        if (_confirmKick)
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
