import 'dart:async';
import 'dart:math' as math;

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

  /// Kepemilikan controller pindah ke sini (TIDAK di-dispose).
  void activate(WpVideoController controller, MiniPlayerInfo info) {
    final old = _controller;
    if (old != null && !identical(old, controller)) {
      old.dispose();
    }
    _controller = controller;
    _info = info;
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

/// Kartu video mengambang di atas semua layar. Geser badan kartu = pindah
/// (menempel ke tepi kiri/kanan saat dilepas), tap = buka kembali player
/// penuh, tombol play/pause dan X di kartu.
/// Dipasang di MaterialApp.builder (lihat main.dart).
///
/// Performa: posisi disimpan di ValueNotifier sehingga saat digeser HANYA
/// posisi kartu yang diperbarui (video & kontrol tidak dibangun ulang), dan
/// tiap tick video cuma memperbarui bar progres / ikon play.
class MiniPlayerOverlay extends ConsumerStatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  ConsumerState<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends ConsumerState<MiniPlayerOverlay>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const double _cardW = 200;
  static const double _cardH = _cardW * 9 / 16;

  /// Jarak kartu ke tepi layar saat menempel.
  static const double _edge = 12;

  final ValueNotifier<Offset> _pos = ValueNotifier<Offset>(Offset.zero);
  final ValueNotifier<bool> _dragging = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);

  late final AnimationController _snapCtl;
  Animation<Offset>? _snapAnim;

  bool _posReady = false;
  String? _forEpisode;
  Timer? _hideTimer;
  Timer? _xpTick;
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _xpTick = Timer.periodic(const Duration(seconds: 1), _onXpTick);
    _snapCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        final a = _snapAnim;
        if (a != null) _pos.value = a.value;
      });
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
    _snapCtl.dispose();
    _pos.dispose();
    _dragging.dispose();
    _controlsVisible.dispose();
    super.dispose();
  }

  void _showControlsBriefly() {
    _hideTimer?.cancel();
    _controlsVisible.value = true;
    _hideTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) _controlsVisible.value = false;
    });
  }

  /// Batasi posisi kartu di dalam area aman layar.
  Offset _clamp(Offset o, Size size, EdgeInsets pad, {double margin = 0}) {
    final minX = margin;
    final maxX = math.max(minX, size.width - _cardW - margin);
    final minY = pad.top + margin;
    final maxY = math.max(minY, size.height - _cardH - pad.bottom - margin);
    return Offset(
      o.dx.clamp(minX, maxX).toDouble(),
      o.dy.clamp(minY, maxY).toDouble(),
    );
  }

  void _onPanStart() {
    _snapCtl.stop();
    _hideTimer?.cancel();
    _dragging.value = true;
  }

  void _onPanUpdate(DragUpdateDetails d, Size size, EdgeInsets pad) {
    _pos.value = _clamp(_pos.value + d.delta, size, pad);
  }

  /// Lepas jari: menempel ke tepi terdekat (memperhitungkan lemparan) dengan
  /// animasi halus, seperti mini player aplikasi nonton lain.
  void _onPanEnd(DragEndDetails d, Size size, EdgeInsets pad) {
    _dragging.value = false;
    final v = d.velocity.pixelsPerSecond;
    final cur = _pos.value;
    final projectedCx = cur.dx + _cardW / 2 + v.dx * 0.12;
    final toRight = projectedCx > size.width / 2;
    final targetX = toRight ? size.width - _cardW - _edge : _edge;
    final target = _clamp(
      Offset(targetX, cur.dy + v.dy * 0.08),
      size,
      pad,
      margin: _edge,
    );
    _snapAnim = Tween<Offset>(begin: cur, end: target).animate(
      CurvedAnimation(parent: _snapCtl, curve: Curves.easeOutCubic),
    );
    _snapCtl.forward(from: 0);
    _showControlsBriefly();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MiniPlayerManager.instance,
      builder: (context, _) {
        final m = MiniPlayerManager.instance;
        final info = m.info;
        final vc = m.controller;
        if (info == null || vc == null) {
          _posReady = false;
          _forEpisode = null;
          return const SizedBox.shrink();
        }

        final size = MediaQuery.sizeOf(context);
        final pad = MediaQuery.paddingOf(context);

        // Posisi awal (kanan atas) tiap mini player baru muncul. Kalau cuma
        // ganti episode saat kartu sudah tampil, posisinya dibiarkan.
        if (!_posReady) {
          _posReady = true;
          _pos.value = Offset(size.width - _cardW - _edge, pad.top + 72);
        }
        if (_forEpisode != info.episodeId) {
          _forEpisode = info.episodeId;
          // Ditunda: jangan ubah notifier saat fase build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showControlsBriefly();
          });
        }

        final card = RepaintBoundary(
          child: ValueListenableBuilder<bool>(
            valueListenable: _dragging,
            builder: (context, dragging, child) => AnimatedScale(
              scale: dragging ? 1.04 : 1,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: child,
            ),
            child: _card(info, vc),
          ),
        );

        // Positioned.fill + Stack: area kosong tidak menyerap sentuhan, dan
        // posisi kartu diperbarui lewat ValueListenableBuilder saja.
        return Positioned.fill(
          child: Stack(
            children: [
              ValueListenableBuilder<Offset>(
                valueListenable: _pos,
                child: card,
                builder: (context, pos, child) {
                  // Dijepit tiap frame supaya tetap di layar saat rotasi /
                  // ukuran layar berubah.
                  final p = _clamp(pos, size, pad);
                  return Positioned(
                    left: p.dx,
                    top: p.dy,
                    width: _cardW,
                    height: _cardH,
                    child: child!,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(MiniPlayerInfo info, WpVideoController vc) {
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, _) {
          final size = MediaQuery.sizeOf(context);
          final pad = MediaQuery.paddingOf(context);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (_) => _snapCtl.stop(),
            onPanStart: (_) => _onPanStart(),
            onPanUpdate: (d) => _onPanUpdate(d, size, pad),
            onPanEnd: (d) => _onPanEnd(d, size, pad),
            onPanCancel: () => _dragging.value = false,
            onTap: () {
              if (_controlsVisible.value) {
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
                  // Video: cuma dibangun ulang saat ukuran/inisialisasi berubah.
                  ListenableBuilder(
                    listenable: vc,
                    builder: (context, _) {
                      if (vc.value.isInitialized) {
                        final ratio = vc.value.aspectRatio > 0 ? vc.value.aspectRatio : 16 / 9;
                        return Center(
                          child: AspectRatio(aspectRatio: ratio, child: WpVideoView(vc)),
                        );
                      }
                      return info.posterUrl.isNotEmpty
                          ? NetImage(info.posterUrl)
                          : const SizedBox.shrink();
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _controlsVisible,
                    builder: (context, visible, child) => AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(ignoring: !visible, child: child),
                    ),
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
                              // Ikon play/pause mengikuti status video.
                              child: ListenableBuilder(
                                listenable: vc,
                                builder: (context, _) => Icon(
                                  vc.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: AppColors.textWhite,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ListenableBuilder(
                      listenable: vc,
                      builder: (context, _) {
                        final dur = vc.value.duration.inMilliseconds;
                        final progress = dur > 0
                            ? (vc.value.position.inMilliseconds / dur).clamp(0.0, 1.0)
                            : 0.0;
                        return LinearProgressIndicator(
                          value: progress.toDouble(),
                          minHeight: 3,
                          color: AppColors.accentViolet,
                          backgroundColor: const Color(0x40FFFFFF),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
