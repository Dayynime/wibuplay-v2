import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/profile_effect_models.dart';
import '../../data/repository/profile_effect_repository.dart';
import '../../providers.dart';

/// Cache efek yang dipakai tiap uid. Permintaan dari beberapa layar
/// dikumpulkan lalu diambil sekali jalan per batch.
class ProfileEffectCache extends StateNotifier<Map<String, ProfileEffect>> {
  ProfileEffectCache(this._repo) : super(const {});

  final ProfileEffectRepository _repo;
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
      // Gagal = profil tampil tanpa efek; tidak dicoba ulang di sesi ini.
    }
  }

  /// Update langsung setelah user sendiri pasang/lepas efek.
  void setLocal(String uid, ProfileEffect? effect) {
    _seen.add(uid);
    final next = {...state};
    if (effect == null) {
      next.remove(uid);
    } else {
      next[uid] = effect;
    }
    state = next;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final profileEffectCacheProvider =
    StateNotifierProvider<ProfileEffectCache, Map<String, ProfileEffect>>(
  (ref) => ProfileEffectCache(ref.watch(profileEffectRepositoryProvider)),
);

/// Isi file lapisan: disimpan di disk (sekali unduh per file) dan beberapa
/// yang terakhir dipakai disimpan di memori.
class _EffectBytes {
  static final LinkedHashMap<String, Future<Uint8List>> _mem = LinkedHashMap();

  static Future<Uint8List> get(String url) {
    final hit = _mem.remove(url);
    if (hit != null) {
      _mem[url] = hit;
      return hit;
    }
    final f = DefaultCacheManager().getSingleFile(url).then((file) => file.readAsBytes());
    _mem[url] = f;
    f.then((_) {}, onError: (Object _) {
      // Gagal: jangan disimpan, supaya dicoba lagi lain kali.
      if (identical(_mem[url], f)) _mem.remove(url);
    });
    while (_mem.length > 16) {
      _mem.remove(_mem.keys.first);
    }
    return f;
  }
}

/// Efek profil milik [uid], ditumpuk di atas kartu profil.
/// Taruh di dalam Stack sebagai Positioned.fill; tidak menangkap sentuhan.
class ProfileEffectOverlay extends ConsumerWidget {
  const ProfileEffectOverlay({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid.isEmpty) return const SizedBox.shrink();
    ref.read(profileEffectCacheProvider.notifier).request(uid);
    final effect = ref.watch(profileEffectCacheProvider.select((m) => m[uid]));
    return ProfileEffectView(effect: effect);
  }
}

/// Memutar semua lapisan [effect] memenuhi seluruh area (seperti BoxFit.cover):
/// efek diperbesar sampai menutup lebar DAN tinggi, kelebihannya dipotong.
class ProfileEffectView extends StatelessWidget {
  const ProfileEffectView({super.key, required this.effect});

  final ProfileEffect? effect;

  @override
  Widget build(BuildContext context) {
    final e = effect;
    if (e == null || e.layers.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < e.layers.length; i++)
              Positioned.fill(
                child: _EffectLayerPlayer(key: ValueKey('${e.id}#$i'), layer: e.layers[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _EffectLayerPlayer extends StatefulWidget {
  const _EffectLayerPlayer({super.key, required this.layer});

  final ProfileEffectLayer layer;

  @override
  State<_EffectLayerPlayer> createState() => _EffectLayerPlayerState();
}

/// Lapisan diputar dengan codec sendiri (bukan Image biasa) supaya tiap
/// putaran mulai dari frame pertama dan bisa disembunyikan saat jeda.
class _EffectLayerPlayerState extends State<_EffectLayerPlayer> {
  static final Random _rnd = Random();

  ui.Image? _image;
  Timer? _wait;
  int _gen = 0;
  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Berhenti saat layar tidak tampil (TickerMode mati) atau user mematikan
    // animasi di pengaturan aksesibilitas.
    final shouldRun = TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context);
    if (shouldRun != _active) {
      _active = shouldRun;
      shouldRun ? _restart() : _stop(rebuild: false);
    }
  }

  @override
  void didUpdateWidget(covariant _EffectLayerPlayer old) {
    super.didUpdateWidget(old);
    if (old.layer != widget.layer && _active) _restart();
  }

  @override
  void dispose() {
    _gen++;
    _wait?.cancel();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  void _stop({bool rebuild = true}) {
    _gen++;
    _wait?.cancel();
    _wait = null;
    _setImage(null, rebuild: rebuild);
  }

  void _restart() {
    _stop(rebuild: false);
    _schedule(_gen, widget.layer.startMs);
  }

  void _schedule(int gen, int ms) {
    _wait?.cancel();
    _wait = Timer(Duration(milliseconds: ms), () => _play(gen));
  }

  void _setImage(ui.Image? img, {bool rebuild = true}) {
    final old = _image;
    if (identical(old, img)) return;
    if (rebuild && mounted) {
      setState(() => _image = img);
    } else {
      _image = img;
    }
    old?.dispose();
  }

  /// Buka codec untuk satu putaran. Varian dipilih acak (kalau ada).
  Future<ui.Codec> _openCodec(ProfileEffectLayer layer) async {
    final files = layer.files;
    final file = files.length == 1 ? files.first : files[_rnd.nextInt(files.length)];
    final bytes = await _EffectBytes.get(layer.url(file));
    return ui.instantiateImageCodec(bytes);
  }

  Future<void> _play(int gen) async {
    final layer = widget.layer;
    ui.Codec? codec;
    Future<ui.Codec>? nextCodec;
    Future<ui.FrameInfo>? pending;
    bool alive() => gen == _gen && mounted;
    try {
      codec = await _openCodec(layer);
      while (true) {
        if (!alive()) return;
        // Putaran berikutnya disiapkan dari sekarang, supaya pas putaran ini
        // selesai frame pertamanya udah siap -> nggak ada frame kosong.
        if (layer.loop) nextCodec = _openCodec(layer);

        final frames = codec!.frameCount;
        final clock = Stopwatch()..start();
        var due = 0;
        pending = codec.getNextFrame();
        for (var i = 0; i < frames; i++) {
          final frame = await pending!;
          pending = null;
          if (!alive()) {
            frame.image.dispose();
            return;
          }
          _setImage(frame.image);
          // Decode frame berikutnya SAMBIL frame ini tampil.
          if (i + 1 < frames) pending = codec.getNextFrame();
          final ms = frame.duration.inMilliseconds;
          due += ms <= 0 ? 40 : ms;
          // Tunggu berdasarkan jam, bukan per frame, biar waktu decode gak
          // bikin animasi makin lama makin telat.
          final wait = due - clock.elapsedMilliseconds;
          if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
          if (!alive()) return;
        }
        codec.dispose();
        codec = null;

        if (!layer.loop) {
          _setImage(null);
          return;
        }
        // Sembunyikan cuma kalau memang ada jeda. Jeda 0 = frame terakhir
        // tetap tampil sampai frame pertama putaran baru menggantikannya.
        if (layer.delayMs > 0) {
          _setImage(null);
          await Future<void>.delayed(Duration(milliseconds: layer.delayMs));
          if (!alive()) return;
        }
        final next = nextCodec!;
        nextCodec = null;
        codec = await next;
      }
    } catch (_) {
      // Gagal unduh / decode = lapisan ini tidak tampil.
      if (alive()) _setImage(null);
    } finally {
      codec?.dispose();
      pending?.then((f) => f.image.dispose(), onError: (Object _) {});
      nextCodec?.then((c) => c.dispose(), onError: (Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null || img.width == 0) return const SizedBox.shrink();
    return RawImage(
      image: img,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.medium,
    );
  }
}
