import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/avatar_frame_models.dart';
import '../../data/repository/avatar_frame_repository.dart';
import '../../providers.dart';

/// Cache border yang dipakai tiap uid. Permintaan dari banyak avatar
/// (chat, komentar) dikumpulkan lalu diambil sekali jalan per batch.
class AvatarFrameCache extends StateNotifier<Map<String, String>> {
  AvatarFrameCache(this._repo) : super(const {});

  final AvatarFrameRepository _repo;
  final Set<String> _seen = {};
  final Set<String> _pending = {};
  Timer? _timer;

  void request(String uid) {
    if (uid.isEmpty || _seen.contains(uid)) return;
    _seen.add(uid);
    _pending.add(uid);
    _timer ??= Timer(const Duration(milliseconds: 150), _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    final batch = _pending.toList();
    _pending.clear();
    if (batch.isEmpty) return;
    try {
      final found = await _repo.getEquippedForUids(batch);
      if (!mounted || found.isEmpty) return;
      state = {...state, ...found};
    } catch (_) {
      // Gagal = tampil tanpa border; tidak dicoba ulang di sesi ini.
    }
  }

  /// Update langsung setelah user sendiri pasang/lepas border.
  void setLocal(String uid, String? frameId) {
    _seen.add(uid);
    final next = {...state};
    if (frameId == null) {
      next.remove(uid);
    } else {
      next[uid] = frameId;
    }
    state = next;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final avatarFrameCacheProvider =
    StateNotifierProvider<AvatarFrameCache, Map<String, String>>(
  (ref) => AvatarFrameCache(ref.watch(avatarFrameRepositoryProvider)),
);

/// Bungkus avatar bulat berukuran [size] dengan border milik [uid].
/// Border digambar 1.25x lebih besar dan meluber keluar, jadi ukuran
/// layout avatar TIDAK berubah.
class FramedAvatar extends ConsumerWidget {
  const FramedAvatar({
    super.key,
    required this.uid,
    required this.size,
    required this.child,
  })  : previewFrameId = null,
        _preview = false;

  /// Pakai border tertentu (untuk pratinjau di toko), bukan milik uid.
  const FramedAvatar.preview({
    super.key,
    required String? frameId,
    required this.size,
    required this.child,
  })  : uid = '',
        previewFrameId = frameId,
        _preview = true;

  final String uid;
  final double size;
  final Widget child;
  final String? previewFrameId;
  final bool _preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? id;
    if (_preview) {
      id = previewFrameId;
    } else if (uid.isNotEmpty) {
      ref.read(avatarFrameCacheProvider.notifier).request(uid);
      id = ref.watch(avatarFrameCacheProvider.select((m) => m[uid]));
    }
    final asset = avatarFrameAsset(id);
    final scale = avatarFrameScale(id);
    final ext = size * (scale - 1) / 2;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: child),
          if (asset != null)
            Positioned(
              left: -ext,
              top: -ext,
              width: size * scale,
              height: size * scale,
              child: IgnorePointer(
                child: Image.asset(
                  asset,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
