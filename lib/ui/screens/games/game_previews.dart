import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/avatar_frame_models.dart';
import '../../../data/models/profile_effect_models.dart';
import '../../../data/models/tree_models.dart';
import '../../../data/models/wallpaper_models.dart';
import '../../../providers.dart';
import '../../components/avatar_frame.dart';
import '../../components/game_badges.dart' show UserAvatar;
import '../../components/profile_effect.dart';
import '../tree/tree_scene.dart';

/// Thumbnail "live" untuk kartu di hub Zenime Games. Semua pakai data asli
/// user (wallpaper gacha, pohon, border, efek) dan punya fallback kalau
/// server gagal / belum login, jadi kartu tidak pernah kosong.

// ============================================================ data

/// Wallpaper unggulan (rarity tertinggi dulu) untuk thumbnail Gacha.
final gachaPreviewProvider = FutureProvider.autoDispose<List<WallpaperItem>>((ref) async {
  final s = await ref.watch(wallpaperRepositoryProvider).getState();
  final pool = [...s.pool]..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
  return pool.take(5).toList();
});

/// Pohon milik user (level, buah, dekorasi).
final treePreviewProvider = FutureProvider.autoDispose<TreeState>((ref) {
  return ref.watch(treeRepositoryProvider).get();
});

/// Border yang diputar di thumbnail: yang dipakai dulu, lalu tier tertinggi.
final _framePreviewProvider = FutureProvider.autoDispose<List<_FrameRef>>((ref) async {
  final s = await ref.watch(avatarFrameRepositoryProvider).getState();
  final frames = [...s.frames]..sort((a, b) => b.tier.index.compareTo(a.tier.index));
  final out = <_FrameRef>[];
  final eq = s.equippedId;
  if (eq != null) {
    for (final f in frames) {
      if (f.id == eq) out.add(_FrameRef(f.id, f.name));
    }
  }
  for (final f in frames) {
    if (f.id != eq && avatarFrameImage(f.id) != null) out.add(_FrameRef(f.id, f.name));
    if (out.length >= 6) break;
  }
  return out;
});

/// Efek yang diputar: yang dipakai, kalau belum ada pakai yang paling mahal.
final effectPreviewProvider = FutureProvider.autoDispose<ProfileEffectItem?>((ref) async {
  final s = await ref.watch(profileEffectRepositoryProvider).getState();
  final eq = s.equipped;
  if (eq != null && eq.layers.isNotEmpty) return eq;
  final list = s.effects.where((e) => e.layers.isNotEmpty).toList()
    ..sort((a, b) => b.price.compareTo(a.price));
  return list.isEmpty ? null : list.first;
});

/// Panggil setelah kembali dari salah satu game supaya thumbnail ikut update.
void refreshGamePreviews(WidgetRef ref) {
  ref.invalidate(gachaPreviewProvider);
  ref.invalidate(treePreviewProvider);
  ref.invalidate(_framePreviewProvider);
  ref.invalidate(effectPreviewProvider);
}

class _FrameRef {
  const _FrameRef(this.id, this.name);
  final String id;
  final String name;
}

// ============================================================ helper

/// Ganti-ganti [count] item tiap [interval] dengan crossfade.
class _Cycler extends StatefulWidget {
  const _Cycler({required this.count, required this.builder, this.interval = const Duration(seconds: 3)});

  final int count;
  final Duration interval;
  final Widget Function(BuildContext context, int index) builder;

  @override
  State<_Cycler> createState() => _CyclerState();
}

class _CyclerState extends State<_Cycler> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant _Cycler old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) {
      _i = 0;
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    if (widget.count < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) return;
      setState(() => _i = (_i + 1) % widget.count);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) return const SizedBox.shrink();
    final i = _i % widget.count;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, if (cur != null) cur]),
      child: KeyedSubtree(key: ValueKey(i), child: widget.builder(context, i)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.color = Colors.white});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
      ),
    );
  }
}

class _IconFallback extends StatelessWidget {
  const _IconFallback(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Center(child: Icon(icon, size: 48, color: Colors.white.withValues(alpha: 0.35)));
}

// ============================================================ gacha

class GachaPreview extends ConsumerWidget {
  const GachaPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(gachaPreviewProvider).valueOrNull ?? const <WallpaperItem>[];
    if (items.isEmpty) return const _IconFallback(Icons.casino_rounded);
    return _Cycler(
      count: items.length,
      builder: (_, i) {
        final w = items[i];
        return Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: w.previewUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceVariantDark),
              errorWidget: (_, __, ___) => const _IconFallback(Icons.casino_rounded),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x99000000)],
                ),
              ),
            ),
            Positioned(left: 8, bottom: 8, right: 8, child: Align(
              alignment: Alignment.centerLeft,
              child: _Pill(w.rarity.label, color: w.rarity.color),
            )),
          ],
        );
      },
    );
  }
}

// ============================================================ pohon

class TreePreview extends ConsumerStatefulWidget {
  const TreePreview({super.key});

  @override
  ConsumerState<TreePreview> createState() => _TreePreviewState();
}

class _TreePreviewState extends ConsumerState<TreePreview> {
  final _scene = TreeSceneController();

  @override
  void initState() {
    super.initState();
    // Tampilan default sebelum data datang.
    _scene.sync(4, 6, 2);
    ref.listenManual<AsyncValue<TreeState>>(treePreviewProvider, (_, next) {
      final t = next.valueOrNull;
      if (t == null) return;
      _scene.sync(t.fruits, t.capacity, t.level);
      final look = t.look;
      if (look != null) _scene.setLook(look);
    }, fireImmediately: true);
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid != null) {
      ref.listenManual(chatProfileProvider(uid), (_, next) {
        _scene.username = next.valueOrNull?.username;
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Scene dirender di kanvas seukuran layar HP lalu diperkecil,
    // jadi kelihatan seperti screenshot halaman Pohon.
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.15),
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: 360,
          height: 560,
          child: TreeScene(controller: _scene, onFruitTap: (_) {}),
        ),
      ),
    );
  }
}

// ============================================================ border avatar

class FramePreview extends ConsumerWidget {
  const FramePreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid;
    final profile = uid == null ? null : ref.watch(chatProfileProvider(uid)).valueOrNull;
    var frames = ref.watch(_framePreviewProvider).valueOrNull ?? const <_FrameRef>[];
    if (frames.isEmpty) {
      // Fallback: border bawaan app (tidak perlu jaringan).
      frames = [
        for (final id in kAvatarFrameAssets.keys) _FrameRef(id, id[0].toUpperCase() + id.substring(1)),
      ];
    }
    final name = profile?.username ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [Color(0x557C3AED), Color(0x00000000)],
              radius: 0.75,
            ),
          ),
        ),
        _Cycler(
          count: frames.length,
          interval: const Duration(milliseconds: 2600),
          builder: (_, i) {
            final f = frames[i];
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: FramedAvatar.preview(
                    frameId: f.id,
                    size: 62,
                    child: UserAvatar(username: name, url: profile?.avatarUrl, size: 62),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Center(child: _Pill(f.name)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ============================================================ efek profil

class EffectPreview extends ConsumerWidget {
  const EffectPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid;
    final profile = uid == null ? null : ref.watch(chatProfileProvider(uid)).valueOrNull;
    final effect = ref.watch(effectPreviewProvider).valueOrNull;
    final banner = profile?.bannerUrl;
    final name = profile?.username ?? 'Kamu';

    // Mini kartu profil (banner + avatar + nama) dengan efek di atasnya,
    // dirender di kanvas tetap lalu diskalakan supaya proporsinya konsisten.
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: 200,
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.surfaceDark),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 82,
                child: banner != null && banner.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: banner,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const _BannerFallback(),
                      )
                    : const _BannerFallback(),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 52,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppColors.surfaceDark, shape: BoxShape.circle),
                      child: UserAvatar(username: name, url: profile?.avatarUrl, size: 56),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    // Garis "konten" profil.
                    for (final w in const [120.0, 84.0])
                      Container(
                        width: w,
                        height: 6,
                        margin: const EdgeInsets.only(bottom: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
              if (effect != null) ProfileEffectView(effect: effect.effect),
              if (effect != null)
                Positioned(left: 8, right: 8, bottom: 8, child: Center(child: _Pill(effect.name))),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFDB2777)]),
        ),
      );
}
