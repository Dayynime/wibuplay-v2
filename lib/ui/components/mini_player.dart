import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wibuplay/core/wp_video.dart';

import '../../core/theme/app_colors.dart';
import '../../core/watch_xp_gate.dart';
import '../../providers.dart';
import '../app_routes.dart';
import 'net_image.dart';

/// Info episode yang sedang "diminimize" ke mini player.
class MiniPlayerInfo {
  const MiniPlayerInfo({
    required this.movieId,
    required this.episodeId,
    required this.title,
    required this.episodeLabel,
    required this.posterUrl,
    required this.link,
    required this.speed,
  });

  final String movieId;
  final String episodeId;
  final String title;
  final String episodeLabel;
  final String posterUrl;

  /// Link stream yang sedang diputar (supaya kualitas tetap sama saat expand).
  final String link;
  final double speed;
}

/// Menyimpan SATU WpVideoController yang dititipkan dari PlayerScreen saat
/// user menekan back sambil masih menonton (port MiniPlayerManager.kt).
/// Berbeda dari PiP sistem: ini murni di dalam app.
class MiniPlayerManager extends ChangeNotifier {
  MiniPlayerManager._();

  static final MiniPlayerManager instance = MiniPlayerManager._();

  WpVideoController? _controller;
  MiniPlayerInfo? _info;
  bool _disposed = false;

  WpVideoController? get controller => _controller;
  MiniPlayerInfo? get info => _info;
  bool get active => _controller != null && _info != null;

  /// notifyListeners ditunda ke microtask: consumeForExpand dipanggil dari
  /// initState PlayerScreen (fase build), jadi notify langsung bikin error
  /// "setState during build" di overlay.
  void _notifySafe() {
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  void _onVideo() => notifyListeners();

  /// Kepemilikan controller pindah ke sini (TIDAK di-dispose).
  void activate(WpVideoController controller, MiniPlayerInfo info) {
    final old = _controller;
    if (old != null && !identical(old, controller)) {
      old.removeListener(_onVideo);
      old.dispose();
    }
    _controller = controller;
    _info = info;
    controller.addListener(_onVideo);
    _notifySafe();
  }

  /// Dipanggil PlayerScreen saat dibuka. Kalau episodenya sama persis, controller
  /// diserahkan balik (posisi & buffer terpakai, tanpa reload). Kalau beda,
  /// mini player lama ditutup supaya tidak ada dua video bersuara bersamaan.
  ({WpVideoController controller, MiniPlayerInfo info})? consumeForExpand(
    String movieId,
    String episodeId,
  ) {
    final c = _controller;
    final i = _info;
    if (c == null || i == null) return null;
    if (i.movieId == movieId && i.episodeId == episodeId) {
      c.removeListener(_onVideo);
      _controller = null;
      _info = null;
      _notifySafe();
      return (controller: c, info: i);
    }
    close();
    return null;
  }

  /// Tombol X: berhenti dan lepas resource.
  void close() {
    final c = _controller;
    if (c == null && _info == null) return;
    c?.removeListener(_onVideo);
    c?.pause();
    c?.dispose();
    _controller = null;
    _info = null;
    _notifySafe();
  }

  void togglePlayPause() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Kartu video mengambang di atas semua layar. Geser badan kartu = pindah,
/// tap = buka kembali player penuh, tombol play/pause dan X di kartu.
/// Dipasang di MaterialApp.builder (lihat main.dart).
class MiniPlayerOverlay extends ConsumerStatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  ConsumerState<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends ConsumerState<MiniPlayerOverlay>
    with WidgetsBindingObserver {
  static const double _cardW = 200;
  static const double _cardH = _cardW * 9 / 16;

  Offset? _pos;
  String? _forEpisode;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _xpTick;
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _xpTick = Timer.periodic(const Duration(seconds: 1), _onXpTick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
  }

  /// XP nonton tetap dihitung saat video jalan di mini player. Layar player
  /// penuh sudah dibuang saat di-minimize (timer XP-nya ikut berhenti), jadi
  /// penghitungan dilanjutkan di sini. Pakai WatchXpGate yang sama supaya tidak
  /// dobel dengan layar player: detik hanya dihitung kalau video playing,
  /// tidak buffering, dan app di depan.
  void _onXpTick(Timer _) {
    if (!mounted || !_inForeground) return;
    final vc = MiniPlayerManager.instance.controller;
    if (vc == null || !vc.value.isPlaying || vc.value.isBuffering) return;
    if (!WatchXpGate.onActiveSecond(this)) return;
    unawaited(
      ref.read(xpRepositoryProvider).sendHeartbeat(minutes: 1).then((ok) {
        // Segarkan kartu XP di Profil begitu server menerima heartbeat.
        if (ok && mounted) ref.invalidate(myXpProvider);
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _xpTick?.cancel();
    WatchXpGate.release(this);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showControlsBriefly() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
    _hideTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MiniPlayerManager.instance,
      builder: (context, _) {
        final m = MiniPlayerManager.instance;
        final info = m.info;
        final vc = m.controller;
        if (info == null || vc == null) return const SizedBox.shrink();

        final size = MediaQuery.sizeOf(context);
        final pad = MediaQuery.paddingOf(context);

        // Posisi awal (kanan atas) tiap ada sesi mini player baru.
        if (_forEpisode != info.episodeId || _pos == null) {
          _forEpisode = info.episodeId;
          _pos = Offset(size.width - _cardW - 12, pad.top + 72);
          _controlsVisible = true;
          _hideTimer?.cancel();
          _hideTimer = Timer(const Duration(milliseconds: 1800), () {
            if (mounted) setState(() => _controlsVisible = false);
          });
        }
        final pos = _pos!;
        final isPlaying = vc.value.isPlaying;
        final dur = vc.value.duration.inMilliseconds;
        final progress =
            dur > 0 ? (vc.value.position.inMilliseconds / dur).clamp(0.0, 1.0) : 0.0;
        final ratio = vc.value.isInitialized && vc.value.aspectRatio > 0
            ? vc.value.aspectRatio
            : 16 / 9;

        return Positioned(
          left: pos.dx,
          top: pos.dy,
          width: _cardW,
          height: _cardH,
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              onPanUpdate: (d) {
                setState(() {
                  final next = pos + d.delta;
                  _pos = Offset(
                    next.dx.clamp(0.0, size.width - _cardW).toDouble(),
                    next.dy
                        .clamp(pad.top, size.height - _cardH - pad.bottom)
                        .toDouble(),
                  );
                });
              },
              onTap: () {
                if (_controlsVisible) {
                  openPlayerFromMini(info.movieId, info.episodeId);
                } else {
                  _showControlsBriefly();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.accentViolet, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x88000000), blurRadius: 14, offset: Offset(0, 4)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (vc.value.isInitialized)
                      Center(
                        child: AspectRatio(aspectRatio: ratio, child: WpVideoView(vc)),
                      )
                    else if (info.posterUrl.isNotEmpty)
                      NetImage(info.posterUrl),
                    AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Color(0x88000000)),
                            Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 6, 34, 0),
                                child: Text(
                                  '${info.title} \u2022 ${info.episodeLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textWhite,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.topRight,
                              child: GestureDetector(
                                onTap: MiniPlayerManager.instance.close,
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.close, size: 18, color: AppColors.textWhite),
                                ),
                              ),
                            ),
                            Center(
                              child: GestureDetector(
                                onTap: () {
                                  MiniPlayerManager.instance.togglePlayPause();
                                  _showControlsBriefly();
                                },
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Color(0x66000000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: AppColors.textWhite,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        value: progress.toDouble(),
                        minHeight: 3,
                        color: AppColors.accentViolet,
                        backgroundColor: const Color(0x40FFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
