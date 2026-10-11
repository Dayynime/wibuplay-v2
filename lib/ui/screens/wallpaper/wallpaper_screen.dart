import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../data/models/wallpaper_models.dart';
import '../../../data/repository/wallpaper_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart' show fadeRoute;
import '../store/coin_screen.dart';
import '../comments/comments_section.dart' show CommentWallpaperFrame;

/// Wallpaper Komentar: gacha pakai ZCoin + koleksi untuk dipasang.
///
/// Hasil spin SELALU ditentukan server (RPC wp_spin_multi, CSPRNG). Animasi
/// "pemanggilan" & kartu terbalik di sini cuma pertunjukan: hasilnya sudah
/// diketahui sebelum animasi dimulai.
class WallpaperScreen extends ConsumerStatefulWidget {
  const WallpaperScreen({super.key});

  @override
  ConsumerState<WallpaperScreen> createState() => _WallpaperScreenState();
}

/// Aksi yang dipilih user di layar hasil spin.
class _RevealAction {
  const _RevealAction({this.equipId, this.openCollection = false, this.spinAgain = false});

  final String? equipId;
  final bool openCollection;
  final bool spinAgain;
}

class _WallpaperScreenState extends ConsumerState<WallpaperScreen> {
  WallpaperState? _state;
  bool _loading = true;
  String? _error;
  int _tab = 0;
  bool _spinning = false;
  bool _equipping = false;

  /// Indeks wallpaper unggulan yang sedang tampil di panggung.
  int _hero = 0;
  Timer? _heroTimer;

  WallpaperRepository get _repo => ref.read(wallpaperRepositoryProvider);

  /// Wallpaper unggulan: rarity tertinggi dulu, maksimal 6.
  List<WallpaperItem> get _showcase {
    final pool = [...?_state?.pool];
    pool.sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
    return pool.take(6).toList();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    super.dispose();
  }

  void _startHeroTimer() {
    _heroTimer?.cancel();
    if (_showcase.length < 2) return;
    _heroTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _spinning || _tab != 0) return;
      setState(() => _hero = (_hero + 1) % _showcase.length);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _repo.getState();
      if (!mounted) return;
      setState(() {
        _state = s;
        _loading = false;
        _hero = 0;
      });
      _startHeroTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is WallpaperException ? e.message : 'Gagal memuat. Tarik ke bawah untuk coba lagi.';
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _refreshCoins() {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid != null) ref.invalidate(coinBalanceProvider(uid));
  }

  // ------------------------------------------------------------ spin

  /// [count] 1 atau 10.
  Future<void> _spin(int count) async {
    final s = _state;
    if (_spinning || s == null) return;
    if (s.pool.isEmpty) {
      _snack('Belum ada wallpaper yang bisa didapat.');
      return;
    }
    final cost = count == 10 ? s.spin10Cost : s.spinCost;
    if (s.balance < cost) {
      _snack('ZCoin kurang ${formatZCoin(cost - s.balance)} untuk Spin ${count}x.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _spinning = true);
    SpinResult r;
    try {
      r = await _repo.spin(count: count);
    } catch (e) {
      if (mounted) {
        setState(() => _spinning = false);
        _snack(e is WallpaperException ? e.message : 'Spin gagal. Saldo tidak terpotong, coba lagi.');
      }
      return;
    }
    if (!mounted) return;

    final ownedIds = s.inventory.map((w) => w.id).toSet();
    final fresh = <WallpaperItem>[];
    for (final e in r.entries) {
      if (!e.duplicate && ownedIds.add(e.item.id)) fresh.add(e.item);
    }
    setState(() {
      _state = s.copyWith(balance: r.balance, inventory: [...fresh.reversed, ...s.inventory]);
    });
    _refreshCoins();

    final next = _state!;
    final action = await Navigator.of(context).push<_RevealAction>(
      PageRouteBuilder<_RevealAction>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _SpinRevealPage(
          result: r,
          count: count,
          equippedId: next.equippedId,
          canSpinAgain: next.balance >= cost,
          cost: cost,
        ),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    if (!mounted) return;
    setState(() => _spinning = false);

    if (action == null) return;
    if (action.equipId != null) {
      await _equip(action.equipId);
    } else if (action.openCollection) {
      setState(() => _tab = 1);
    } else if (action.spinAgain) {
      await _spin(count);
    }
  }

  Future<void> _openCatalog(WallpaperState s) async {
    final equipId = await Navigator.of(context).push<String>(
      fadeRoute(_CatalogPage(
        pool: s.pool,
        ownedIds: s.inventory.map((w) => w.id).toSet(),
        equippedId: s.equippedId,
      )),
    );
    if (equipId != null && mounted) await _equip(equipId);
  }

  // ------------------------------------------------------------ equip

  Future<void> _equip(String? id) async {
    if (_equipping) return;
    setState(() => _equipping = true);
    try {
      await _repo.equip(id);
      if (!mounted) return;
      setState(() => _state = _state?.copyWith(equippedId: () => id));
      _snack(id == null ? 'Wallpaper dilepas' : 'Wallpaper terpasang di komentarmu');
    } catch (e) {
      if (mounted) _snack(e is WallpaperException ? e.message : 'Gagal, coba lagi');
    } finally {
      if (mounted) setState(() => _equipping = false);
    }
  }

  void _openItem(WallpaperItem w) {
    final equipped = _state?.equippedId == w.id;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.backgroundDarkSecondary,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(w.name, style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              _RarityPill(rarity: w.rarity),
              const SizedBox(height: 12),
              // Pratinjau persis seperti di kolom komentar.
              CommentWallpaperFrame(
                wallpaper: CommentWallpaper(id: w.id, rarity: w.rarity, url: w.url),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 30),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(radius: 17, backgroundColor: AppColors.surfaceElevated),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kamu', style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700, fontSize: 13)),
                            SizedBox(height: 4),
                            Text('Begini tampilan komentarmu nanti ✨', style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: equipped ? AppColors.surfaceElevated : AppColors.accentViolet,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _equip(equipped ? null : w.id);
                    },
                    child: Text(equipped ? 'Lepas wallpaper' : 'Pakai wallpaper ini'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ UI

  Future<void> _openTopUp() async {
    await Navigator.of(context).push<void>(fadeRoute(const CoinScreen()));
    if (mounted) {
      _refreshCoins();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text('Gacha Wallpaper', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        actions: [
          if (s != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _BalancePill(balance: s.balance, onTap: _openTopUp),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final s = _state;
    if (_loading && s == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentViolet));
    }
    if (s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Gagal memuat', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Muat ulang')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accentViolet,
      onRefresh: _spinning ? () async {} : _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _Tabs(
              labels: ['Spin', 'Koleksiku (${s.inventory.length})'],
              selected: _tab,
              onChanged: _spinning ? null : (i) => setState(() => _tab = i),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _tab == 0
                ? Column(key: const ValueKey('spin'), children: _spinTab(s))
                : KeyedSubtree(key: const ValueKey('koleksi'), child: _collectionTab(s)),
          ),
        ],
      ),
    );
  }

  List<Widget> _spinTab(WallpaperState s) {
    final showcase = _showcase;
    final hero = showcase.isEmpty ? null : showcase[_hero % showcase.length];
    return [
      // ---- panggung: wallpaper unggulan berganti tiap 5 detik
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _HeroStage(
          item: hero,
          index: showcase.isEmpty ? 0 : _hero % showcase.length,
          total: showcase.length,
          poolSize: s.pool.length,
          onTap: s.pool.isEmpty ? null : () => _openCatalog(s),
        ),
      ),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: _SpinButton(
                label: 'Spin 1x',
                cost: s.spinCost,
                busy: _spinning,
                enabled: !_spinning && s.pool.isNotEmpty,
                primary: false,
                onTap: () => _spin(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SpinButton(
                label: 'Spin 10x',
                cost: s.spin10Cost,
                busy: _spinning,
                enabled: !_spinning && s.pool.isNotEmpty,
                primary: true,
                onTap: () => _spin(10),
              ),
            ),
          ],
        ),
      ),
      if (s.dupRefundPercent > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.autorenew_rounded, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                'Dapat yang sudah dimiliki? ${s.dupRefundPercent}% ZCoin kembali',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _OddsCard(state: s),
      ),
    ];
  }

  Widget _collectionTab(WallpaperState s) {
    if (s.inventory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(
          child: Text('Belum punya wallpaper. Coba spin dulu!', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return Column(
      children: [
        if (s.equippedId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _equipping ? null : () => _equip(null),
                icon: const Icon(Icons.layers_clear_outlined, size: 18),
                label: const Text('Lepas wallpaper'),
              ),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: s.inventory.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 16 / 11,
          ),
          itemBuilder: (_, i) {
            final w = s.inventory[i];
            final on = s.equippedId == w.id;
            return GestureDetector(
              onTap: () => _openItem(w),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: on ? AppColors.accentViolet : w.rarity.color.withValues(alpha: 0.6), width: on ? 2.5 : 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: w.previewUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceDark),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xCC000000)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 6,
                        child: Text(w.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      Positioned(top: 6, left: 6, child: _RarityPill(rarity: w.rarity)),
                      if (on)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(Icons.check_circle, color: AppColors.accentViolet, size: 20),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ================================================================ widgets

class _BalancePill extends StatelessWidget {
  const _BalancePill({required this.balance, required this.onTap});

  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDark,
      shape: const StadiumBorder(side: BorderSide(color: Color(0x1FFFFFFF))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/ic_zcoin_badge.png', width: 20, height: 20),
              const SizedBox(width: 6),
              Text(
                formatZCoin(balance),
                style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(width: 6),
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(color: AppColors.accentViolet, shape: BoxShape.circle),
                child: const Icon(Icons.add, size: 15, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panggung wallpaper unggulan (rarity tertinggi dulu), berganti pelan.
class _HeroStage extends StatelessWidget {
  const _HeroStage({
    required this.item,
    required this.index,
    required this.total,
    required this.poolSize,
    this.onTap,
  });

  final WallpaperItem? item;
  final int index;
  final int total;
  final int poolSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final w = item;
    final glow = w?.rarity.color ?? AppColors.surfaceElevated;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: glow.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.28), blurRadius: 32, spreadRadius: -4)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: w == null
              ? const ColoredBox(
                  color: AppColors.surfaceDark,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_outlined, color: AppColors.textMuted, size: 40),
                          SizedBox(height: 10),
                          Text(
                            'Belum ada wallpaper yang bisa didapat.\nCek lagi nanti.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: onTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 900),
                        switchInCurve: Curves.easeOut,
                        child: CachedNetworkImage(
                          key: ValueKey(w.id),
                          imageUrl: w.url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => CachedNetworkImage(imageUrl: w.previewUrl, fit: BoxFit.cover),
                          errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceDark),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x33000000), Colors.transparent, Color(0xE6070A10)],
                            stops: [0, 0.4, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                          decoration: BoxDecoration(
                            color: const Color(0x99000000),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0x33FFFFFF)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Lihat semua $poolSize wallpaper',
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.white, size: 16),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.bottomLeft,
                                  children: [...previous, if (current != null) current],
                                ),
                                child: Column(
                                  key: ValueKey('t-${w.id}'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _RarityPill(rarity: w.rarity),
                                    const SizedBox(height: 6),
                                    Text(
                                      w.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (total > 1)
                              Row(
                                children: [
                                  for (var i = 0; i < total; i++)
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      margin: const EdgeInsets.only(left: 4),
                                      width: i == index ? 16 : 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: i == index ? Colors.white : Colors.white38,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                ],
                              ),
                          ],
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

class _SpinButton extends StatefulWidget {
  const _SpinButton({
    required this.label,
    required this.cost,
    required this.busy,
    required this.enabled,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final int cost;
  final bool busy;
  final bool enabled;
  final bool primary;
  final VoidCallback onTap;

  @override
  State<_SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<_SpinButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.enabled || widget.busy ? 1 : 0.45,
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: primary
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF8B3DFF), Color(0xFFE4344A)],
                    )
                  : null,
              color: primary ? null : AppColors.surfaceVariantDark,
              border: Border.all(color: primary ? const Color(0x40FFFFFF) : const Color(0x1FFFFFFF)),
              boxShadow: primary
                  ? const [BoxShadow(color: Color(0x668B3DFF), blurRadius: 20, offset: Offset(0, 6))]
                  : null,
            ),
            child: Center(
              child: widget.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/images/ic_zcoin_badge.png', width: 14, height: 14),
                            const SizedBox(width: 5),
                            Text(
                              formatZCoin(widget.cost),
                              style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Peluang per rarity: bar tersegmen + legenda, daftar lengkap bisa dibuka.
class _OddsCard extends StatefulWidget {
  const _OddsCard({required this.state});

  final WallpaperState state;

  @override
  State<_OddsCard> createState() => _OddsCardState();
}

class _OddsCardState extends State<_OddsCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final by = s.chanceByRarity;
    final rarities = WallpaperRarity.values.reversed.where((r) => (by[r] ?? 0) > 0).toList();
    final pool = [...s.pool]..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Peluang', style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          if (rarities.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in rarities.reversed)
                      Expanded(
                        flex: math.max(1, ((by[r] ?? 0) * 100).round()),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: r.gradient == null ? r.color : null, gradient: r.gradient),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          for (final r in rarities)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: r.gradient == null ? r.color : null,
                      gradient: r.gradient,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(r.label, style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    '${(by[r] ?? 0).toStringAsFixed(2)}%',
                    style: TextStyle(color: r.color, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Text(
                    _open ? 'Sembunyikan daftar' : 'Lihat semua ${pool.length} wallpaper',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (final w in pool)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 56,
                                  height: 35,
                                  child: CachedNetworkImage(
                                    imageUrl: w.previewUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceVariantDark),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      w.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
                                    ),
                                    Text(w.rarity.label, style: TextStyle(color: w.rarity.color, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Text(
                                '${(w.chancePercent ?? 0).toStringAsFixed(2)}%',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ================================================================ reveal

/// Layar hasil spin: fase "pemanggilan" (cincin berputar yang warnanya
/// berubah ke rarity tertinggi), lalu kartu terbalik satu per satu.
/// Ketuk di mana saja untuk mempercepat.
class _SpinRevealPage extends StatefulWidget {
  const _SpinRevealPage({
    required this.result,
    required this.count,
    required this.equippedId,
    required this.canSpinAgain,
    required this.cost,
  });

  final SpinResult result;
  final int count;
  final String? equippedId;
  final bool canSpinAgain;
  final int cost;

  @override
  State<_SpinRevealPage> createState() => _SpinRevealPageState();
}

class _SpinRevealPageState extends State<_SpinRevealPage> with TickerProviderStateMixin {
  late final bool _reduce =
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  late final AnimationController _charge = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _reduce ? 250 : 1600),
  );
  late final AnimationController _cards = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: _reduce ? 250 : 500 + widget.result.entries.length * 140 + 350,
    ),
  );
  bool _revealed = false;

  WallpaperRarity get _best => widget.result.best.item.rarity;

  @override
  void initState() {
    super.initState();
    _charge.forward().whenComplete(_startCards);
  }

  void _startCards() {
    if (!mounted || _revealed) return;
    setState(() => _revealed = true);
    if (_best.index >= WallpaperRarity.epic.index) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    _cards.forward();
  }

  void _skip() {
    if (!_revealed) {
      _charge.stop();
      _startCards();
    } else if (_cards.isAnimating) {
      _cards.value = 1;
    }
  }

  @override
  void dispose() {
    _charge.dispose();
    _cards.dispose();
    super.dispose();
  }

  Animation<double> _cardAnim(int i) {
    final n = widget.result.entries.length;
    final total = 500 + n * 140 + 350;
    final start = (i * 140) / total;
    final end = math.min(1.0, (i * 140 + 500) / total);
    return CurvedAnimation(parent: _cards, curve: Interval(start, end, curve: Curves.easeOutCubic));
  }

  @override
  Widget build(BuildContext context) {
    final color = _best.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_charge, _cards]),
              builder: (_, __) {
                final glow = _revealed ? 0.55 : Curves.easeIn.transform(_charge.value) * 0.45;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 1.0,
                      colors: [color.withValues(alpha: glow), const Color(0xF5050608)],
                      stops: const [0, 0.75],
                    ),
                  ),
                );
              },
            ),
            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _revealed ? _results() : _charging(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _charging() {
    return Center(
      key: const ValueKey('charge'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 190,
            height: 190,
            child: AnimatedBuilder(
              animation: _charge,
              builder: (_, __) {
                final t = _charge.value;
                // Warna baru "bocor" ke rarity tertinggi di 40% akhir: rasa antisipasi.
                final mix = Curves.easeIn.transform(((t - 0.4) / 0.6).clamp(0.0, 1.0));
                final c = Color.lerp(const Color(0xCCFFFFFF), _best.color, mix)!;
                return CustomPaint(
                  painter: _RingPainter(progress: t, color: c),
                  child: Center(
                    child: Transform.scale(
                      scale: 0.9 + 0.15 * math.sin(t * math.pi * 4).abs(),
                      child: Icon(Icons.auto_awesome, size: 46, color: c),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          Text(
            widget.count == 10 ? 'Memanggil 10 wallpaper…' : 'Memanggil wallpaper…',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('Ketuk untuk lewati', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _results() {
    final r = widget.result;
    final single = r.entries.length == 1;
    final first = r.entries.first;
    final newCount = r.entries.where((e) => !e.duplicate).length;

    final String title;
    final String? sub;
    if (single) {
      title = first.duplicate ? 'Sudah kamu miliki' : 'Wallpaper baru!';
      sub = first.duplicate && r.refund > 0 ? '${formatZCoin(r.refund)} ZCoin dikembalikan' : null;
    } else {
      title = 'Hasil Spin 10x';
      sub = '$newCount baru${r.refund > 0 ? ', ${formatZCoin(r.refund)} ZCoin dikembalikan' : ''}';
    }

    final buttons = AnimatedBuilder(
      animation: _cards,
      builder: (_, child) => Opacity(
        opacity: Curves.easeOut.transform(((_cards.value - 0.8) / 0.2).clamp(0.0, 1.0)),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            if (single && widget.equippedId != first.item.id)
              Expanded(
                child: _RevealButton(
                  label: 'Pakai sekarang',
                  primary: !widget.canSpinAgain,
                  onTap: () => Navigator.pop(context, _RevealAction(equipId: first.item.id)),
                ),
              ),
            if (!single)
              Expanded(
                child: _RevealButton(
                  label: 'Lihat koleksi',
                  primary: !widget.canSpinAgain,
                  onTap: () => Navigator.pop(context, const _RevealAction(openCollection: true)),
                ),
              ),
            if (widget.canSpinAgain) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _RevealButton(
                  label: 'Spin ${widget.count}x lagi',
                  primary: true,
                  onTap: () => Navigator.pop(context, const _RevealAction(spinAgain: true)),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Column(
      key: const ValueKey('results'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Tutup',
              ),
            ],
          ),
        ),
        Expanded(
          child: single
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: _RevealCard(entry: first, t: _cardAnim(0), large: true),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: r.entries.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 16 / 10,
                  ),
                  itemBuilder: (_, i) => _RevealCard(entry: r.entries[i], t: _cardAnim(i), large: false),
                ),
        ),
        buttons,
      ],
    );
  }
}

class _RevealButton extends StatelessWidget {
  const _RevealButton({required this.label, required this.primary, required this.onTap});

  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: primary
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentViolet,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0x59FFFFFF)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
    );
  }
}

/// Kartu hasil: mulai dari sisi belakang (warna rarity), lalu terbalik.
class _RevealCard extends StatelessWidget {
  const _RevealCard({required this.entry, required this.t, required this.large});

  final SpinEntry entry;
  final Animation<double> t;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final rarity = entry.item.rarity;
    final high = rarity.index >= WallpaperRarity.epic.index;
    return AnimatedBuilder(
      animation: t,
      builder: (_, __) {
        final v = t.value;
        final angle = (1 - v) * math.pi;
        final front = angle <= math.pi / 2;
        return Opacity(
          opacity: (v * 4).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.86 + 0.14 * v,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(angle),
              child: front ? _front(rarity, high, v) : _back(rarity),
            ),
          ),
        );
      },
    );
  }

  Widget _back(WallpaperRarity rarity) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceVariantDark, rarity.color.withValues(alpha: 0.55)],
        ),
        border: Border.all(color: rarity.color.withValues(alpha: 0.8), width: 2),
      ),
      child: Center(child: Icon(Icons.auto_awesome, color: rarity.color, size: large ? 48 : 28)),
    );
  }

  Widget _front(WallpaperRarity rarity, bool high, double v) {
    final w = entry.item;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rarity.color, width: 2),
        boxShadow: high
            ? [BoxShadow(color: rarity.color.withValues(alpha: 0.6 * v), blurRadius: 26, spreadRadius: 1)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: large ? w.url : w.previewUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceDark),
              errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceDark),
            ),
            if (entry.duplicate) const ColoredBox(color: Color(0x80000000)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xD9000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
            Positioned(top: 6, left: 6, child: _RarityPill(rarity: rarity)),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: entry.duplicate ? const Color(0xCC262D3B) : AppColors.successGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  entry.duplicate ? 'Dimiliki' : 'Baru',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Text(
                w.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: large ? 16 : 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x1FFFFFFF),
    );

    final rect = Rect.fromCircle(center: c, radius: r);
    final start = progress * math.pi * 6;
    canvas.drawArc(
      rect,
      start,
      math.pi * 1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          endAngle: math.pi * 1.4,
          colors: [color.withValues(alpha: 0), color],
          transform: GradientRotation(start),
        ).createShader(rect),
    );

    canvas.drawCircle(
      c,
      r * (0.45 + 0.1 * math.sin(progress * math.pi * 4).abs()),
      Paint()..color = color.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

// ================================================================ katalog

/// Daftar semua wallpaper yang bisa didapat dari spin, dengan filter rarity.
/// Pop dengan id wallpaper = user ingin memasangnya.
class _CatalogPage extends StatefulWidget {
  const _CatalogPage({required this.pool, required this.ownedIds, required this.equippedId});

  final List<WallpaperItem> pool;
  final Set<String> ownedIds;
  final String? equippedId;

  @override
  State<_CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<_CatalogPage> {
  WallpaperRarity? _rarity; // null = semua
  bool _missingOnly = false;

  List<WallpaperItem> get _sorted {
    final list = [...widget.pool];
    list.sort((a, b) {
      final r = b.rarity.index.compareTo(a.rarity.index);
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final all = _sorted;
    final counts = <WallpaperRarity, int>{};
    for (final w in all) {
      counts[w.rarity] = (counts[w.rarity] ?? 0) + 1;
    }
    final owned = all.where((w) => widget.ownedIds.contains(w.id)).length;
    final shown = all
        .where((w) => _rarity == null || w.rarity == _rarity)
        .where((w) => !_missingOnly || !widget.ownedIds.contains(w.id))
        .toList();
    final progress = all.isEmpty ? 0.0 : owned / all.length;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text('Daftar Wallpaper', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: CustomScrollView(
        slivers: [
          // ---- progres koleksi
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$owned',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(
                            '/ ${all.length} dimiliki',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        children: [
                          Container(height: 8, color: AppColors.surfaceVariantDark),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: progress),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => FractionallySizedBox(
                              widthFactor: v,
                              child: Container(
                                height: 8,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(colors: [Color(0xFF8B3DFF), Color(0xFFE4344A)]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ---- filter rarity
          SliverToBoxAdapter(
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(
                    label: 'Semua',
                    count: all.length,
                    selected: _rarity == null,
                    onTap: () => setState(() => _rarity = null),
                  ),
                  for (final r in WallpaperRarity.values.reversed)
                    if ((counts[r] ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: r.label,
                        count: counts[r]!,
                        rarity: r,
                        selected: _rarity == r,
                        onTap: () => setState(() => _rarity = _rarity == r ? null : r),
                      ),
                    ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${shown.length} wallpaper',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  const Text('Belum dimiliki saja', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  Switch(
                    value: _missingOnly,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.accentViolet,
                    onChanged: (v) => setState(() => _missingOnly = v),
                  ),
                ],
              ),
            ),
          ),

          // ---- grid
          if (shown.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppColors.textMuted, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      _missingOnly
                          ? 'Semua wallpaper di filter ini sudah kamu miliki.'
                          : 'Tidak ada wallpaper di filter ini.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final w = shown[i];
                    return TweenAnimationBuilder<double>(
                      key: ValueKey('${_rarity?.name}-$_missingOnly-${w.id}'),
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 260 + math.min(i, 8) * 40),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
                      ),
                      child: _CatalogCard(
                        item: w,
                        owned: widget.ownedIds.contains(w.id),
                        equipped: widget.equippedId == w.id,
                        onTap: () => _openDetail(w),
                      ),
                    );
                  },
                  childCount: shown.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openDetail(WallpaperItem w) {
    final owned = widget.ownedIds.contains(w.id);
    final equipped = widget.equippedId == w.id;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.backgroundDarkSecondary,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: w.url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => CachedNetworkImage(imageUrl: w.previewUrl, fit: BoxFit.cover),
                      errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceDark),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            w.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _RarityPill(rarity: w.rarity),
                              const SizedBox(width: 8),
                              Text(
                                'Peluang ${(w.chancePercent ?? 0).toStringAsFixed(2)}%',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // pratinjau di kolom komentar
              CommentWallpaperFrame(
                wallpaper: CommentWallpaper(id: w.id, rarity: w.rarity, url: w.url),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 30),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(radius: 17, backgroundColor: AppColors.surfaceElevated),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kamu', style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700, fontSize: 13)),
                            SizedBox(height: 4),
                            Text('Contoh tampilan di kolom komentar', style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: owned
                      ? FilledButton(
                          onPressed: equipped
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  Navigator.pop(context, w.id);
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentViolet,
                            disabledBackgroundColor: AppColors.surfaceElevated,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                            equipped ? 'Sedang dipakai' : 'Pakai wallpaper ini',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x59FFFFFF)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.casino_outlined, size: 18),
                          label: const Text('Dapatkan lewat spin', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.rarity,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final WallpaperRarity? rarity;

  @override
  Widget build(BuildContext context) {
    final r = rarity;
    final color = r?.color ?? AppColors.accentViolet;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? (r?.gradient == null ? color : null) : AppColors.surfaceDark,
          gradient: selected ? r?.gradient : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : (r.gradient == null ? color : null),
                  gradient: selected ? null : r.gradient,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textWhite,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                color: selected ? const Color(0xCCFFFFFF) : AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.onTap,
  });

  final WallpaperItem item;
  final bool owned;
  final bool equipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = item.rarity;
    final high = r.index >= WallpaperRarity.epic.index;
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: r.color.withValues(alpha: equipped ? 1 : 0.5), width: equipped ? 2 : 1.2),
            boxShadow: high ? [BoxShadow(color: r.color.withValues(alpha: 0.22), blurRadius: 16)] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: item.previewUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceVariantDark),
                      ),
                      Positioned(top: 6, left: 6, child: _RarityPill(rarity: r)),
                      if (owned)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: equipped ? AppColors.accentViolet : AppColors.successGreen,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              equipped ? 'Dipakai' : 'Dimiliki',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Peluang ${(item.chancePercent ?? 0).toStringAsFixed(2)}%',
                      style: TextStyle(color: r.color, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RarityPill extends StatelessWidget {
  const _RarityPill({required this.rarity});

  final WallpaperRarity rarity;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: rarity.gradient == null ? rarity.color : null,
          gradient: rarity.gradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          rarity.label,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
        ),
      );
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.selected, required this.onChanged});

  final List<String> labels;
  final int selected;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onChanged == null ? null : () => onChanged!(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: i == selected
                        ? const LinearGradient(colors: [AppColors.accentViolet, Color(0xFFFF6B4A)])
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == selected ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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
