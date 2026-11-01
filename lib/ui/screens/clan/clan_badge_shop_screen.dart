import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/clan_badge_cache.dart';
import '../../../data/models/clan_models.dart';
import '../../../data/repository/clan_repository.dart';
import '../../../providers.dart';
import '../../components/clan_badge_styles.dart';
import '../../components/game_badges.dart' show ClanRainbowBadge;
import '../../glass/glass.dart';
import 'clan_widgets.dart';

String _zc(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Toko badge tag clan (khusus leader): beli pakai saldo donasi clan, lalu
/// pasang salah satu badge yang sudah dimiliki. Badge terpasang tampil di
/// semua tempat tag clan muncul (chat, komentar, profil, leaderboard).
class ClanBadgeShopScreen extends ConsumerStatefulWidget {
  const ClanBadgeShopScreen({super.key, required this.clanId});

  final String clanId;

  @override
  ConsumerState<ClanBadgeShopScreen> createState() => _ClanBadgeShopScreenState();
}

class _ClanBadgeShopScreenState extends ConsumerState<ClanBadgeShopScreen> {
  List<ClanBadgeOffer>? _offers;
  String? _error;
  String? _busyId; // id badge yang sedang diproses ('' = default)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final offers = await ref.read(clanRepositoryProvider).getBadgeShop(widget.clanId);
      if (mounted) setState(() {
        _offers = offers;
        _error = null;
      });
    } on ClanException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _afterChange(Clan clan, String? style) {
    ClanBadgeCache.instance.prime(clan.tag, style);
    ref.invalidate(clanDetailProvider(widget.clanId));
    ref.invalidate(allClansProvider);
  }

  Future<void> _buy(Clan clan, ClanBadgeOffer offer, ClanBadgeStyle style) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Beli ${style.label}?', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: ClanStyledBadge(text: clan.tag, style: style, height: 30)),
            const SizedBox(height: 16),
            Text(
              '${_zc(offer.price)} ZCoin diambil dari saldo donasi clan '
              '(sisa ${_zc(clan.treasuryBalance - offer.price)}). '
              'Badge langsung dipasang dan jadi milik clan selamanya.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Beli', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = offer.id);
    try {
      await ref.read(clanRepositoryProvider).buyBadge(clan.id, offer.id);
      HapticFeedback.mediumImpact();
      _afterChange(clan, offer.id);
      await _load();
      _toast('${style.label} dibeli dan dipasang');
    } on ClanException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _equip(Clan clan, String? badgeId, String label) async {
    setState(() => _busyId = badgeId ?? '');
    try {
      await ref.read(clanRepositoryProvider).equipBadge(clan.id, badgeId);
      HapticFeedback.selectionClick();
      _afterChange(clan, badgeId);
      _toast('$label dipasang');
    } on ClanException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clan = ref.watch(clanDetailProvider(widget.clanId)).valueOrNull?.clan;

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        title: const Text('Badge Clan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: _body(clan),
    );
  }

  Widget _body(Clan? clan) {
    final offers = _offers;
    if (clan == null || (offers == null && _error == null)) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3));
    }
    if (offers == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  _load();
                },
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final byId = {for (final o in offers) o.id: o};
    final items = <(ClanBadgeStyle, ClanBadgeOffer)>[
      for (final st in ClanBadgeStyle.values)
        if (byId[st.id] case final o? when o.active || o.owned) (st, o),
    ];
    final current = clan.badgeStyle;

    return RefreshIndicator(
      color: AppColors.accentViolet,
      onRefresh: () async {
        ref.invalidate(clanDetailProvider(widget.clanId));
        await _load();
      },
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + MediaQuery.paddingOf(context).bottom),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Badge tampil di depan nama semua member: chat, komentar, profil, dan leaderboard.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: clanGemBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: clanGemBlue.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond_rounded, size: 14, color: clanGemBlue),
                    const SizedBox(width: 4),
                    Text(
                      _zc(clan.treasuryBalance),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _BadgeCard(
            title: 'Pelangi (bawaan)',
            preview: (h) => ClanRainbowBadge(text: clan.tag, height: h),
            clanName: clan.name,
            trailing: current == null
                ? const _Equipped()
                : _ActionButton(
                    label: 'Pakai',
                    busy: _busyId == '',
                    onTap: _busyId != null ? null : () => _equip(clan, null, 'Badge bawaan'),
                  ),
            highlighted: current == null,
          ),
          for (final (st, o) in items) ...[
            const SizedBox(height: 10),
            _BadgeCard(
              title: st.label,
              preview: (h) => ClanStyledBadge(text: clan.tag, style: st, height: h),
              clanName: clan.name,
              highlighted: current == st.id,
              trailing: current == st.id
                  ? const _Equipped()
                  : o.owned
                      ? _ActionButton(
                          label: 'Pakai',
                          busy: _busyId == o.id,
                          onTap: _busyId != null ? null : () => _equip(clan, o.id, st.label),
                        )
                      : clan.treasuryBalance < o.price
                          ? _PriceTag(price: o.price, enough: false)
                          : _ActionButton(
                              label: 'Beli ${_zc(o.price)}',
                              icon: Icons.diamond_rounded,
                              primary: true,
                              busy: _busyId == o.id,
                              onTap: _busyId != null ? null : () => _buy(clan, o, st),
                            ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Badge dibeli pakai saldo donasi clan dan jadi milik clan selamanya. '
            'Level clan tidak berkurang.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({
    required this.title,
    required this.preview,
    required this.clanName,
    required this.trailing,
    required this.highlighted,
  });

  final String title;
  final Widget Function(double height) preview;
  final String clanName;
  final Widget trailing;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
      decoration: BoxDecoration(
        color: clanSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? const Color(0xFF34D399).withValues(alpha: 0.7) : clanBorder,
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ),
              trailing,
            ],
          ),
          const SizedBox(height: 12),
          // Tiga ukuran seperti aslinya dipakai: kecil, di samping nama, besar.
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              preview(14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  preview(20),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      clanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              preview(32),
            ],
          ),
        ],
      ),
    );
  }
}

class _Equipped extends StatelessWidget {
  const _Equipped();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF34D399).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF34D399)),
          SizedBox(width: 4),
          Text('Terpasang', style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price, required this.enough});

  final int price;
  final bool enough;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.diamond_rounded, size: 13, color: clanGemBlue),
            const SizedBox(width: 3),
            Text(_zc(price), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
        if (!enough)
          const Text('Saldo donasi kurang', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.busy = false,
    this.primary = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: primary
                  ? const LinearGradient(colors: [AppColors.accentViolet, Color(0xFFFF6B4A)])
                  : null,
              color: primary ? null : Colors.white.withValues(alpha: 0.08),
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                      ],
                      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
