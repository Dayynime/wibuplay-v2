import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../data/models/avatar_frame_models.dart';
import '../../../data/repository/avatar_frame_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart' show fadeRoute;
import '../../components/avatar_frame.dart';
import '../../components/game_badges.dart' show UserAvatar;
import '../store/coin_screen.dart';

/// Toko Border Avatar: pratinjau di avatar sendiri, beli pakai ZCoin,
/// pasang / lepas. Harga & kepemilikan selalu dari server.
class AvatarFrameScreen extends ConsumerStatefulWidget {
  const AvatarFrameScreen({super.key});

  @override
  ConsumerState<AvatarFrameScreen> createState() => _AvatarFrameScreenState();
}

class _AvatarFrameScreenState extends ConsumerState<AvatarFrameScreen> {
  AvatarFrameState? _state;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _selected;

  AvatarFrameRepository get _repo => ref.read(avatarFrameRepositoryProvider);
  String get _uid => ref.read(authUserProvider).valueOrNull?.uid ?? '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _load();
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
        _selected ??= s.equippedId ?? (s.frames.isNotEmpty ? s.frames.first.id : null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  AvatarFrameItem? get _item {
    final s = _state;
    if (s == null || _selected == null) return null;
    for (final f in s.frames) {
      if (f.id == _selected) return f;
    }
    return null;
  }

  Future<void> _buy(AvatarFrameItem f) async {
    final s = _state!;
    if (s.balance < f.price) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          title: const Text('ZCoin kurang'),
          content: Text(
            'Border ${f.name} butuh ${formatZCoin(f.price)} ZCoin. '
            'Saldo kamu ${formatZCoin(s.balance)} ZCoin.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nanti')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Top up ZCoin')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.of(context).push<void>(fadeRoute(const CoinScreen()));
        if (mounted) _load();
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Beli ${f.name}?'),
        content: Text('${formatZCoin(f.price)} ZCoin akan dipotong dari saldo kamu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Beli')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final balance = await _repo.buy(f.id);
      await _repo.equip(f.id);
      final uid = _uid;
      if (uid.isNotEmpty) {
        ref.read(avatarFrameCacheProvider.notifier).setLocal(uid, f.id);
        ref.invalidate(coinBalanceProvider(uid));
      }
      if (!mounted) return;
      setState(() {
        _state = s.copyWith(
          balance: balance,
          equippedId: () => f.id,
          frames: [for (final x in s.frames) x.id == f.id ? x.copyWith(owned: true) : x],
        );
      });
      _toast('Border ${f.name} dibeli dan dipasang');
    } catch (e) {
      _toast(e.toString());
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _equip(String? id) async {
    final s = _state!;
    setState(() => _busy = true);
    try {
      await _repo.equip(id);
      final uid = _uid;
      if (uid.isNotEmpty) ref.read(avatarFrameCacheProvider.notifier).setLocal(uid, id);
      if (!mounted) return;
      setState(() => _state = s.copyWith(equippedId: () => id));
      _toast(id == null ? 'Border dilepas' : 'Border dipasang');
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final profile = uid.isEmpty ? null : ref.watch(chatProfileProvider(uid)).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        title: const Text('Border Avatar'),
        actions: [
          if (_state != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: _Balance(balance: _state!.balance)),
            ),
        ],
      ),
      body: _body(profile?.username ?? '', profile?.avatarUrl),
    );
  }

  Widget _body(String name, String? avatarUrl) {
    if (_loading && _state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Gagal memuat border',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }

    final s = _state!;
    final item = _item;
    return Column(
      children: [
        const SizedBox(height: 28),
        FramedAvatar.preview(
          frameId: _selected,
          size: 120,
          child: UserAvatar(username: name, url: avatarUrl, size: 120),
        ),
        const SizedBox(height: 22),
        Text(
          item?.name ?? '',
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item == null
              ? ''
              : s.equippedId == item.id
                  ? 'Sedang dipakai'
                  : item.owned
                      ? 'Sudah kamu miliki'
                      : '${formatZCoin(item.price)} ZCoin',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(width: double.infinity, height: 48, child: _action(s, item)),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: s.frames.length,
              itemBuilder: (_, i) {
                final f = s.frames[i];
                return _FrameTile(
                  item: f,
                  selected: f.id == _selected,
                  equipped: f.id == s.equippedId,
                  onTap: () => setState(() => _selected = f.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _action(AvatarFrameState s, AvatarFrameItem? item) {
    if (item == null) return const SizedBox.shrink();
    final child = _busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : null;
    if (s.equippedId == item.id) {
      return OutlinedButton(
        onPressed: _busy ? null : () => _equip(null),
        child: child ?? const Text('Lepas border'),
      );
    }
    if (item.owned) {
      return FilledButton(
        onPressed: _busy ? null : () => _equip(item.id),
        child: child ?? const Text('Pasang'),
      );
    }
    return FilledButton(
      onPressed: _busy ? null : () => _buy(item),
      child: child ?? Text('Beli ${formatZCoin(item.price)} ZCoin'),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/ic_zcoin_badge.png', width: 16, height: 16),
          const SizedBox(width: 6),
          Text(
            formatZCoin(balance),
            style: const TextStyle(
              color: AppColors.textWhite,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.item,
    required this.selected,
    required this.equipped,
    required this.onTap,
  });

  final AvatarFrameItem item;
  final bool selected;
  final bool equipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = equipped
        ? 'Dipakai'
        : item.owned
            ? 'Dimiliki'
            : formatZCoin(item.price);
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accentViolet : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: FramedAvatar.preview(
                    frameId: item.id,
                    size: 56,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceVariantDark,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!item.owned) ...[
                    Image.asset('assets/images/ic_zcoin_badge.png', width: 11, height: 11),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: equipped ? AppColors.successGreen : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
