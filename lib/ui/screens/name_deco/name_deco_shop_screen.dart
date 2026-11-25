import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/name_deco_cache.dart';
import '../../../data/repository/name_deco_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/name_deco_styles.dart';
import '../../glass/glass.dart';
import '../store/coin_screen.dart';

String _zc(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

const Color _kSurface = Color(0xFF151A27);
const Color _kBorder = Color(0x14FFFFFF);
const Color _kGreen = Color(0xFF34D399);

/// Shop Dekorasi Nama: beli gaya nama futuristik pakai ZCoin sendiri, lalu pasang.
/// Dekorasi terpasang tampil di chat, komentar, profil, leaderboard, teman, dan clan.
class NameDecoShopScreen extends ConsumerStatefulWidget {
  const NameDecoShopScreen({super.key});

  @override
  ConsumerState<NameDecoShopScreen> createState() => _NameDecoShopScreenState();
}

class _NameDecoShopScreenState extends ConsumerState<NameDecoShopScreen> {
  NameDecoShop? _shop;
  String? _error;
  String? _busyId; // '' = bawaan

  String get _uid => ref.read(authUserProvider).valueOrNull?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final shop = await ref.read(nameDecoRepositoryProvider).getShop(_uid);
      if (!mounted) return;
      NameDecoCache.instance.prime(_uid, shop.equipped);
      setState(() {
        _shop = shop;
        _error = null;
      });
    } on NameDecoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _buy(NameDecoOffer offer, NameDecoStyle style, String name, int balance) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Beli ${style.label}?', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: NameDecoText(name: name, style: style, fontSize: 18, maxWidth: 240)),
            const SizedBox(height: 16),
            Text(
              '${_zc(offer.price)} ZCoin dipotong dari saldomu (sisa ${_zc(balance - offer.price)}). '
              'Dekorasi langsung dipasang dan jadi milikmu selamanya.',
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
      await ref.read(nameDecoRepositoryProvider).buy(offer.id);
      HapticFeedback.mediumImpact();
      NameDecoCache.instance.prime(_uid, offer.id);
      ref.invalidate(coinBalanceProvider(_uid));
      await _load();
      _toast('${style.label} dibeli dan dipasang');
    } on NameDecoException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _equip(String? badgeId, String label) async {
    setState(() => _busyId = badgeId ?? '');
    try {
      await ref.read(nameDecoRepositoryProvider).equip(badgeId);
      HapticFeedback.selectionClick();
      NameDecoCache.instance.prime(_uid, badgeId);
      await _load();
      _toast('$label dipasang');
    } on NameDecoException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final balance = uid.isEmpty ? null : ref.watch(coinBalanceProvider(uid)).valueOrNull;
    final chatName = uid.isEmpty ? '' : (ref.watch(chatProfileProvider(uid)).valueOrNull?.username ?? '');
    final authName = ref.watch(authUserProvider).valueOrNull?.displayName ?? '';
    final name = chatName.trim().isNotEmpty ? chatName.trim() : (authName.trim().isNotEmpty ? authName.trim() : 'Zenime');

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textWhite),
        ),
        title: const Text(
          'Dekorasi Nama',
          style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: _body(uid, name, balance),
    );
  }

  Widget _body(String uid, String name, int? balance) {
    final shop = _shop;
    if (uid.isEmpty) {
      return const Center(
        child: Text('Login dulu untuk membeli dekorasi nama', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    if (shop == null) {
      if (_error == null) {
        return const Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3));
      }
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

    final byId = {for (final o in shop.offers) o.id: o};
    final items = <(NameDecoStyle, NameDecoOffer)>[
      for (final st in NameDecoStyle.values)
        if (byId[st.id] case final o? when o.active || o.owned) (st, o),
    ];
    final current = shop.equipped;
    final bal = balance ?? 0;

    return RefreshIndicator(
      color: AppColors.accentViolet,
      onRefresh: () async {
        ref.invalidate(coinBalanceProvider(uid));
        await _load();
      },
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        // Kartu di luar layar tidak dibangun (dan tidak animasi) dulu.
        cacheExtent: 120,
        padding: EdgeInsets.fromLTRB(16, 6, 16, 28 + MediaQuery.paddingOf(context).bottom),
        children: [
          // Saldo + ajakan top up.
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.of(context).push<void>(fadeRoute(const CoinScreen())).then((_) {
                if (mounted) ref.invalidate(coinBalanceProvider(uid));
              }),
              child: Ink(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: [Color(0xFF2A1A4A), AppColors.surfaceCard]),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Image.asset('assets/images/ic_zcoin_badge.png', width: 30, height: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Saldo ZCoin', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          Text(
                            balance == null ? '—' : _zc(bal),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const Text('Top up',
                        style: TextStyle(color: Color(0xFFB79BFF), fontWeight: FontWeight.w800, fontSize: 13)),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFFB79BFF)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Nama bergaya futuristik dan beranimasi, tampil di Chat Global, komentar, profil, '
            'leaderboard, teman, dan clan.',
            style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'Nama biasa',
            highlighted: current == null,
            mine: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w700)),
            tier: null,
            trailing: current == null
                ? const _Equipped()
                : _Btn(
                    label: 'Pakai',
                    busy: _busyId == '',
                    onTap: _busyId != null ? null : () => _equip(null, 'Nama biasa'),
                  ),
          ),
          for (final (st, o) in items) ...[
            const SizedBox(height: 10),
            _Card(
              title: st.label,
              highlighted: current == st.id,
              mine: NameDecoText(name: name, style: st, fontSize: 16, maxWidth: 230),
              tier: st.tier,
              trailing: current == st.id
                  ? const _Equipped()
                  : o.owned
                      ? _Btn(
                          label: 'Pakai',
                          busy: _busyId == o.id,
                          onTap: _busyId != null ? null : () => _equip(o.id, st.label),
                        )
                      : balance != null && bal < o.price
                          ? _Price(price: o.price)
                          : _Btn(
                              label: 'Beli ${_zc(o.price)}',
                              coin: true,
                              primary: true,
                              busy: _busyId == o.id,
                              onTap: _busyId != null || balance == null
                                  ? null
                                  : () => _buy(o, st, name, bal),
                            ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Dekorasi yang sudah dibeli jadi milikmu selamanya dan bisa diganti kapan saja tanpa bayar lagi.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.highlighted,
    required this.mine,
    required this.tier,
    required this.trailing,
  });

  final String title;
  final bool highlighted;

  /// Nama user sendiri dengan dekorasi ini.
  final Widget mine;

  /// Tier dekorasi (null = nama biasa).
  final NameDecoTier? tier;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? _kGreen.withValues(alpha: 0.7) : _kBorder,
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
                    if (tier != null)
                      Text(tier!.label.toUpperCase(),
                          style: TextStyle(
                              color: tier!.color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
                  ],
                ),
              ),
              trailing,
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Align(alignment: Alignment.centerLeft, child: mine),
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
      decoration: BoxDecoration(color: _kGreen.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 15, color: _kGreen),
          SizedBox(width: 4),
          Text('Terpasang', style: TextStyle(color: _kGreen, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({required this.price});

  final int price;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/ic_zcoin_badge.png', width: 14, height: 14),
            const SizedBox(width: 3),
            Text(_zc(price), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
        const Text('ZCoin belum cukup', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.label,
    required this.onTap,
    this.busy = false,
    this.primary = false,
    this.coin = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool primary;
  final bool coin;

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
                  ? const LinearGradient(colors: [Color(0xFF8B5CF6), AppColors.accentViolet])
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
                      if (coin) ...[
                        Image.asset('assets/images/ic_zcoin_badge.png', width: 14, height: 14),
                        const SizedBox(width: 4),
                      ],
                      Text(label,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
