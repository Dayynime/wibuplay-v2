import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../data/models/wallpaper_models.dart';
import '../../../data/repository/wallpaper_repository.dart';
import '../../../providers.dart';
import '../comments/comments_section.dart' show CommentWallpaperFrame;

/// Wallpaper Komentar: spin (gacha) pakai ZCoin + koleksi untuk dipasang.
///
/// Hasil spin SELALU ditentukan server (RPC wp_spin, CSPRNG). Animasi reel di
/// sini cuma pertunjukan: hasilnya sudah diketahui sebelum reel berputar.
class WallpaperScreen extends ConsumerStatefulWidget {
  const WallpaperScreen({super.key});

  @override
  ConsumerState<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends ConsumerState<WallpaperScreen> {
  static const double _tileW = 132;
  static const double _gap = 10;
  static const double _pad = 16;
  static const int _resultIndex = 32;

  final ScrollController _reel = ScrollController();
  final Random _rnd = Random();

  WallpaperState? _state;
  bool _loading = true;
  String? _error;
  int _tab = 0;
  bool _spinning = false;
  bool _equipping = false;
  List<WallpaperItem> _reelItems = const [];

  WallpaperRepository get _repo => ref.read(wallpaperRepositoryProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _reel.dispose();
    super.dispose();
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
        if (_reelItems.isEmpty && s.pool.isNotEmpty) {
          _reelItems = List.generate(12, (i) => s.pool[i % s.pool.length]);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is WallpaperException ? e.message : 'Gagal memuat, coba lagi';
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

  Future<void> _spin() async {
    final s = _state;
    if (_spinning || s == null) return;
    if (s.pool.isEmpty) {
      _snack('Belum ada wallpaper di pool spin.');
      return;
    }
    if (s.balance < s.spinCost) {
      _snack('ZCoin kamu tidak cukup (butuh ${formatZCoin(s.spinCost)}).');
      return;
    }

    setState(() => _spinning = true);
    SpinResult r;
    try {
      r = await _repo.spin();
    } catch (e) {
      if (mounted) {
        setState(() => _spinning = false);
        _snack(e is WallpaperException ? e.message : 'Spin gagal, coba lagi');
      }
      return;
    }
    if (!mounted) return;

    final pool = s.pool;
    setState(() {
      _reelItems = List.generate(
        _resultIndex + 5,
        (i) => i == _resultIndex ? r.item : pool[_rnd.nextInt(pool.length)],
      );
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_reel.hasClients) return;
    _reel.jumpTo(0);
    final viewport = _reel.position.viewportDimension;
    final target = _pad + _resultIndex * (_tileW + _gap) + _tileW / 2 - viewport / 2;
    await _reel.animateTo(
      target.clamp(0, _reel.position.maxScrollExtent).toDouble(),
      duration: const Duration(milliseconds: 3800),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;

    setState(() {
      _spinning = false;
      _state = s.copyWith(
        balance: r.balance,
        inventory: r.duplicate ? s.inventory : [r.item, ...s.inventory],
      );
    });
    _refreshCoins();
    await _showResult(r);
  }

  Future<void> _showResult(SpinResult r) async {
    final equipNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              r.duplicate ? 'Duplikat!' : 'Wallpaper baru!',
              style: const TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(imageUrl: r.item.url, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              r.item.name,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            _RarityPill(rarity: r.item.rarity),
            if (r.duplicate) ...[
              const SizedBox(height: 8),
              Text(
                r.refund > 0
                    ? 'Kamu sudah punya ini. Refund ${formatZCoin(r.refund)} ZCoin.'
                    : 'Kamu sudah punya wallpaper ini.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Oke')),
          if (_state?.equippedId != r.item.id)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pakai sekarang'),
            ),
        ],
      ),
    );
    if (equipNow == true) await _equip(r.item.id);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Wallpaper Komentar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        actions: [
          if (_state != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Image.asset('assets/images/ic_zcoin_badge.png', width: 18, height: 18),
                  const SizedBox(width: 6),
                  Text(
                    formatZCoin(_state!.balance),
                    style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Gagal memuat', style: const TextStyle(color: AppColors.textSecondary)),
            TextButton(onPressed: _load, child: const Text('Coba lagi')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accentViolet,
      onRefresh: _spinning ? () async {} : _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: _Tabs(
              labels: ['Spin', 'Koleksiku (${s.inventory.length})'],
              selected: _tab,
              onChanged: _spinning ? null : (i) => setState(() => _tab = i),
            ),
          ),
          if (_tab == 0) ..._spinTab(s) else _collectionTab(s),
        ],
      ),
    );
  }

  List<Widget> _spinTab(WallpaperState s) {
    final byRarity = s.chanceByRarity;
    return [
      SizedBox(
        height: 96,
        child: Stack(
          children: [
            ListView.separated(
              controller: _reel,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              itemCount: _reelItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: _gap),
              itemBuilder: (_, i) {
                final w = _reelItems[i];
                return Container(
                  width: _tileW,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: w.rarity.color, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: w.previewUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceDark),
                    ),
                  ),
                );
              },
            ),
            // Penanda tengah
            Align(
              alignment: Alignment.center,
              child: IgnorePointer(
                child: Container(width: 3, height: 96, color: Colors.white.withValues(alpha: 0.9)),
              ),
            ),
          ],
        ),
      ),
      if (s.pool.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Belum ada wallpaper di pool spin. Tunggu admin menambahkan ya!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _spinning || s.pool.isEmpty ? null : _spin,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentViolet,
              shape: const StadiumBorder(),
            ),
            icon: _spinning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.casino_outlined),
            label: Text(
              _spinning ? 'Memutar…' : 'Spin • ${formatZCoin(s.spinCost)} ZCoin',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
      if (s.dupRefundPercent > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Dapat duplikat? ${s.dupRefundPercent}% ZCoin dikembalikan.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      const SizedBox(height: 22),
      // Transparansi peluang
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Peluang', style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final r in WallpaperRarity.values.reversed)
                if (byRarity[r] != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        _RarityPill(rarity: r),
                        const Spacer(),
                        Text(
                          '${byRarity[r]!.toStringAsFixed(2)}%',
                          style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Lihat semua (${s.pool.length})',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  iconColor: AppColors.textSecondary,
                  collapsedIconColor: AppColors.textSecondary,
                  children: [
                    for (final w in s.pool)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: w.rarity.color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(w.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textWhite, fontSize: 12)),
                            ),
                            Text('${(w.chancePercent ?? 0).toStringAsFixed(2)}%',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

class _RarityPill extends StatelessWidget {
  const _RarityPill({required this.rarity});

  final WallpaperRarity rarity;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: rarity.color, borderRadius: BorderRadius.circular(20)),
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
