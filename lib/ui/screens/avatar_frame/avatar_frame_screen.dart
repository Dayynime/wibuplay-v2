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

/// Toko Border Avatar: tab Shop/Koleksi, cari nama, filter tier,
/// pratinjau di avatar sendiri, beli pakai ZCoin, pasang / lepas.
/// Harga, tier & kepemilikan selalu dari server.
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
  String? _busyId;
  bool _collection = false;
  AvatarFrameTier? _tier;
  String _query = '';
  final _search = TextEditingController();

  AvatarFrameRepository get _repo => ref.read(avatarFrameRepositoryProvider);
  String get _uid => ref.read(authUserProvider).valueOrNull?.uid ?? '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
        _selected ??= s.equippedId;
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

    setState(() {
      _busy = true;
      _busyId = f.id;
      _selected = f.id;
    });
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
      if (mounted) {
        setState(() {
          _busy = false;
          _busyId = null;
        });
      }
    }
  }

  Future<void> _equip(String? id, {String? busyId}) async {
    final s = _state!;
    setState(() {
      _busy = true;
      _busyId = busyId ?? id;
      if (id != null) _selected = id;
    });
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
      if (mounted) {
        setState(() {
          _busy = false;
          _busyId = null;
        });
      }
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
      ),
      body: _body(profile?.username ?? '', profile?.avatarUrl),
    );
  }

  List<AvatarFrameItem> _visible(AvatarFrameState s) {
    final q = _query.trim().toLowerCase();
    return [
      for (final f in s.frames)
        if ((!_collection || f.owned) &&
            (_tier == null || f.tier == _tier) &&
            (q.isEmpty || f.name.toLowerCase().contains(q) || f.id.contains(q)))
          f,
    ];
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
    final visible = _visible(s);
    final ownedCount = s.frames.where((f) => f.owned).length;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.list(
                children: [
                  _header(s, name, avatarUrl),
                  const SizedBox(height: 14),
                  _tabs(s.frames.length, ownedCount),
                  const SizedBox(height: 12),
                  _searchField(),
                  const SizedBox(height: 12),
                  _tierChips(),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                  child: Text(
                    _query.trim().isNotEmpty
                        ? 'Border "${_query.trim()}" tidak ditemukan'
                        : _collection
                            ? 'Koleksi kamu masih kosong.\nBeli border di tab Shop.'
                            : 'Belum ada border di tier ini',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.66,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final f = visible[i];
                    return _FrameCard(
                      item: f,
                      selected: f.id == _selected,
                      equipped: f.id == s.equippedId,
                      affordable: s.balance >= f.price,
                      busy: _busyId == f.id,
                      disabled: _busy,
                      onTap: () => setState(() => _selected = f.id),
                      onAction: () {
                        if (f.id == s.equippedId) {
                          _equip(null, busyId: f.id);
                        } else if (f.owned) {
                          _equip(f.id);
                        } else {
                          _buy(f);
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(AvatarFrameState s, String name, String? avatarUrl) {
    final item = _item;
    final equipped = s.equippedId;
    final previewing = item != null && item.id != equipped;
    String? equippedName;
    for (final f in s.frames) {
      if (f.id == equipped) equippedName = f.name;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceElevated),
      ),
      child: Row(
        children: [
          // Ruang ekstra supaya border berhiasan besar tidak terpotong.
          SizedBox(
            width: 92,
            height: 92,
            child: Center(
              child: FramedAvatar.preview(
                frameId: _selected ?? equipped,
                size: 92 / avatarFrameScale(_selected ?? equipped),
                child: UserAvatar(
                  username: name,
                  url: avatarUrl,
                  size: 92 / avatarFrameScale(_selected ?? equipped),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  previewing ? 'Pratinjau' : 'Border avatar',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  previewing ? item!.name : (equippedName ?? 'Belum dipakai'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Image.asset('assets/images/ic_zcoin_badge.png', width: 16, height: 16),
                    const SizedBox(width: 6),
                    Text(
                      formatZCoin(s.balance),
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('ZCoin',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          if (previewing)
            IconButton(
              tooltip: 'Batal pratinjau',
              onPressed: () => setState(() => _selected = equipped),
              icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _tabs(int total, int owned) {
    Widget tab(String label, IconData icon, int count, bool active, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 44,
            decoration: BoxDecoration(
              color: active ? AppColors.surfaceElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: active ? AppColors.textWhite : AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? AppColors.textWhite : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count',
                  style: TextStyle(
                    color: active ? AppColors.successGreen : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceElevated),
      ),
      child: Row(
        children: [
          tab('Shop', Icons.shopping_bag_rounded, total, !_collection,
              () => setState(() => _collection = false)),
          tab('Koleksi', Icons.face_retouching_natural_rounded, owned, _collection,
              () => setState(() => _collection = true)),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppColors.textWhite),
      decoration: InputDecoration(
        hintText: 'Cari nama border...',
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.surfaceElevated),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentViolet),
        ),
      ),
    );
  }

  Widget _tierChips() {
    Widget chip(String label, AvatarFrameTier? tier) {
      final active = _tier == tier;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _tier = tier),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: active ? AppColors.surfaceElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: active ? AppColors.textSecondary : AppColors.surfaceElevated,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? AppColors.textWhite : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Semua', null),
          for (final t in AvatarFrameTier.values) chip(t.label, t),
        ],
      ),
    );
  }
}

Color _tierColor(AvatarFrameTier t) => switch (t) {
      AvatarFrameTier.basic => AppColors.textSecondary,
      AvatarFrameTier.standard => const Color(0xFF4FA3FF),
      AvatarFrameTier.premium => const Color(0xFFF5C451),
    };

class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.item,
    required this.selected,
    required this.equipped,
    required this.affordable,
    required this.busy,
    required this.disabled,
    required this.onTap,
    required this.onAction,
  });

  final AvatarFrameItem item;
  final bool selected;
  final bool equipped;
  final bool affordable;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColor(item.tier);
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.accentViolet : AppColors.surfaceElevated,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const RadialGradient(
                      colors: [AppColors.surfaceVariantDark, AppColors.backgroundDarkSecondary],
                      radius: 0.9,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: FramedAvatar.preview(
                          frameId: item.id,
                          // Border selalu muat di kotak, apa pun ukuran kanvasnya.
                          size: 96 / avatarFrameScale(item.id),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceElevated,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundDark.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: tierColor.withValues(alpha: 0.8)),
                          ),
                          child: Text(
                            item.tier.label,
                            style: TextStyle(
                              color: tierColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (equipped)
                        const Positioned(
                          right: 8,
                          top: 8,
                          child: Icon(Icons.check_circle_rounded,
                              size: 18, color: AppColors.successGreen),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, height: 44, child: _button()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button() {
    const spinner = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
    final onPressed = disabled ? null : onAction;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

    if (equipped) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: shape,
          side: const BorderSide(color: AppColors.successGreen),
          foregroundColor: AppColors.successGreen,
          padding: EdgeInsets.zero,
        ),
        child: busy ? spinner : const Text('Dipakai · Lepas', style: TextStyle(fontSize: 12)),
      );
    }
    if (item.owned) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(shape: shape, padding: EdgeInsets.zero),
        child: busy ? spinner : const Text('Pasang'),
      );
    }

    final price = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/ic_zcoin_badge.png', width: 13, height: 13),
        const SizedBox(width: 4),
        Text(formatZCoin(item.price),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ],
    );
    if (!affordable) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: shape,
          backgroundColor: AppColors.warningAmber.withValues(alpha: 0.12),
          side: BorderSide(color: AppColors.warningAmber.withValues(alpha: 0.7)),
          foregroundColor: AppColors.warningAmber,
          padding: EdgeInsets.zero,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ZCoin kurang', style: TextStyle(fontSize: 10)),
            price,
          ],
        ),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(shape: shape, padding: EdgeInsets.zero),
      child: busy ? spinner : price,
    );
  }
}
