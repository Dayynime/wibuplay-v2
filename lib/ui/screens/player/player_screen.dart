import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/watch_xp_gate.dart';
import '../../../data/models/episode_item.dart';
import '../../../data/models/stream_data.dart';
import '../../../providers.dart';
import '../../components/cards.dart';
import '../../components/common_components.dart';
import 'player_controller.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Format waktu mm:ss atau h:mm:ss (port formatTime).
String formatTime(int millis) {
  final totalSeconds = millis < 0 ? 0 : millis ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final hours = minutes ~/ 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${two(minutes % 60)}:${two(seconds)}';
  return '${two(minutes)}:${two(seconds)}';
}

/// Snapshot status pemutar (pengganti state `isPlaying/currentPosition/...`).
class _Playback {
  const _Playback({
    this.isPlaying = false,
    this.isBuffering = true,
    this.positionMs = 0,
    this.durationMs = 0,
  });

  final bool isPlaying;
  final bool isBuffering;
  final int positionMs;
  final int durationMs;

  _Playback copyWith({int? positionMs}) => _Playback(
        isPlaying: isPlaying,
        isBuffering: isBuffering,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs,
      );

  @override
  bool operator ==(Object other) =>
      other is _Playback &&
      other.isPlaying == isPlaying &&
      other.isBuffering == isBuffering &&
      other.positionMs == positionMs &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(isPlaying, isBuffering, positionMs, durationMs);
}

/// Port PlayerScreen.kt. ExoPlayer diganti video_player (ExoPlayer di Android).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.movieId,
    required this.episodeId,
    required this.onBackClick,
    required this.onAnimeClick,
  });

  final String movieId;
  final String episodeId;
  final VoidCallback onBackClick;
  final ValueChanged<String> onAnimeClick;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  /// false saat app di background: detik itu tidak dihitung untuk XP.
  bool _inForeground = true;

  VideoPlayerController? _vc;
  String? _loadedLink;
  final ValueNotifier<_Playback> _pb = ValueNotifier<_Playback>(const _Playback());

  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _tick;
  int _tickCount = 0;
  bool _endedHandled = false;
  bool _playerError = false;
  bool _wasPlaying = false;
  String? _gestureText;
  bool _synopsisExpanded = false;

  final ScrollController _epScroll = ScrollController();
  final GlobalKey _epRowKey = GlobalKey();
  final Map<String, GlobalKey> _epKeys = {};

  (String, String) get _args => (widget.movieId, widget.episodeId);
  PlayerController get _notifier => ref.read(playerControllerProvider(_args).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _tick = Timer.periodic(const Duration(seconds: 1), _onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadLink(ref.read(playerControllerProvider(_args)).selectedServer?.link);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WatchXpGate.release(this);
    _hideTimer?.cancel();
    _tick?.cancel();
    final vc = _vc;
    _vc = null;
    vc?.removeListener(_onVideo);
    vc?.dispose();
    _pb.dispose();
    _epScroll.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // ---------------------------------------------------------------- pemutar

  Future<void> _loadLink(String? link) async {
    if (link == null || link.trim().isEmpty) return;
    if (link == _loadedLink) return;
    _loadedLink = link;

    final old = _vc;
    old?.removeListener(_onVideo);
    final resumeMs = ref.read(playerControllerProvider(_args)).resumePositionMs;

    final VideoPlayerController vc;
    try {
      vc = VideoPlayerController.networkUrl(Uri.parse(link));
    } catch (_) {
      if (mounted) setState(() => _playerError = true);
      return;
    }
    _vc = vc;
    _endedHandled = false;
    _wasPlaying = false;
    _playerError = false;
    _pb.value = const _Playback();
    if (mounted) setState(() {});
    await old?.dispose();

    try {
      await vc.initialize();
      if (!mounted || _vc != vc) return;
      if (resumeMs > 0) await vc.seekTo(Duration(milliseconds: resumeMs));
      if (!mounted || _vc != vc) return;
      vc.addListener(_onVideo);
      await vc.play();
      if (!mounted || _vc != vc) return;
      _onVideo();
      setState(() {});
    } catch (_) {
      if (mounted && _vc == vc) {
        _pb.value = const _Playback(isBuffering: false);
        setState(() => _playerError = true);
      }
    }
  }

  void _onVideo() {
    final vc = _vc;
    if (vc == null || !mounted) return;
    final v = vc.value;
    if (v.hasError && !_playerError) setState(() => _playerError = true);

    final snap = _Playback(
      isPlaying: v.isPlaying,
      isBuffering: v.hasError ? false : (v.isBuffering || !v.isInitialized),
      positionMs: v.position.inMilliseconds,
      durationMs: v.duration.inMilliseconds < 0 ? 0 : v.duration.inMilliseconds,
    );
    _pb.value = snap;

    if (snap.isPlaying != _wasPlaying) {
      _wasPlaying = snap.isPlaying;
      WakelockPlus.toggle(enable: snap.isPlaying);
      _scheduleHide();
    }

    if (!_endedHandled &&
        v.isInitialized &&
        v.duration > Duration.zero &&
        (v.isCompleted || v.position >= v.duration)) {
      _endedHandled = true;
      _notifier.startAutoNextCountdown();
    }
  }

  void _onTick(Timer t) {
    if (!mounted) return;
    final vc = _vc;
    if (vc == null || !vc.value.isPlaying) return;
    _tickCount++;
    final dur = vc.value.duration.inMilliseconds;
    if (_tickCount % 5 == 0 && dur > 0) {
      _notifier.saveProgress(vc.value.position.inMilliseconds, dur);
    }

    // XP nonton: hanya detik aktif (playing, tidak buffering, app di depan).
    if (_inForeground && !vc.value.isBuffering && WatchXpGate.onActiveSecond(this)) {
      unawaited(
        ref.read(xpRepositoryProvider).sendHeartbeat(minutes: 1).then((ok) {
          // Segarkan kartu XP di Profil begitu server menerima heartbeat.
          if (ok && mounted) ref.invalidate(myXpProvider);
        }),
      );
    }
  }

  void _seekMs(int ms) {
    final vc = _vc;
    if (vc == null) return;
    final dur = _pb.value.durationMs;
    final target = ms.clamp(0, dur < 0 ? 0 : dur).toInt();
    vc.seekTo(Duration(milliseconds: target));
    _pb.value = _pb.value.copyWith(positionMs: target);
  }

  void _togglePlay() {
    final vc = _vc;
    if (vc == null) return;
    if (vc.value.isPlaying) {
      vc.pause();
    } else {
      vc.play();
    }
    _scheduleHide();
  }

  // ---------------------------------------------------------------- kontrol

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_showControls && _pb.value.isPlaying) {
      _hideTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  void _toggleOverlay() {
    setState(() => _showControls = !_showControls);
    _scheduleHide();
  }

  void _applyFullscreen(bool fullscreen) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  void _scrollToCurrentEpisode() {
    final id = ref.read(playerControllerProvider(_args)).currentEpisodeId;
    final chipCtx = _epKeys[id]?.currentContext;
    final rowCtx = _epRowKey.currentContext;
    if (chipCtx == null || rowCtx == null || !_epScroll.hasClients) return;
    final chipBox = chipCtx.findRenderObject();
    final rowBox = rowCtx.findRenderObject();
    if (chipBox is! RenderBox || rowBox is! RenderBox) return;
    final dx = chipBox.localToGlobal(Offset.zero, ancestor: rowBox).dx;
    final target = dx.clamp(0.0, _epScroll.position.maxScrollExtent).toDouble();
    _epScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _openServerSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final ui = ref.watch(playerControllerProvider(_args));
            final servers = ui.streamData?.server ?? const <StreamServer>[];
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih Server & Kualitas Video',
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (servers.isEmpty)
                    const Text(
                      'Tidak ada server video alternatif.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    )
                  else
                    for (final server in servers)
                      _ServerTile(
                        server: server,
                        isSelected: identical(server, ui.selectedServer),
                        onTap: () {
                          _notifier.selectServer(server);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(playerControllerProvider(_args));
    final isFavorite = ref.watch(localStoreProvider.select((s) => s.isFavorite(ui.movieId)));

    ref.listen<String?>(
      playerControllerProvider(_args).select((s) => s.selectedServer?.link),
      (prev, next) => _loadLink(next),
    );
    ref.listen<bool>(
      playerControllerProvider(_args).select((s) => s.isFullscreen),
      (prev, next) => _applyFullscreen(next),
    );
    ref.listen<(String, int)>(
      playerControllerProvider(_args).select((s) => (s.currentEpisodeId, s.episodes.length)),
      (prev, next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToCurrentEpisode();
        });
      },
    );

    return PopScope(
      canPop: !ui.isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && ui.isFullscreen) _notifier.setFullscreen(false);
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: ui.isFullscreen ? _fullscreenLayout(ui) : _portraitLayout(ui, isFavorite),
      ),
    );
  }

  Widget _videoSurface() {
    final vc = _vc;
    if (vc == null || !vc.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final ratio = vc.value.aspectRatio;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: ratio > 0 ? ratio : 16 / 9,
          child: VideoPlayer(vc),
        ),
      ),
    );
  }

  String _overlayTitle(PlayerUiState ui) {
    return '${ui.anime?.title ?? 'Anime'} - Ep ${ui.streamData?.episode?.index ?? ''}';
  }

  Widget _controls(PlayerUiState ui, {required bool fullscreen}) {
    return ValueListenableBuilder<_Playback>(
      valueListenable: _pb,
      builder: (context, pb, _) {
        return _ControlsOverlay(
          pb: pb,
          showControls: _showControls,
          isFullscreen: fullscreen,
          title: _overlayTitle(ui),
          selectedServer: ui.selectedServer,
          onTogglePlay: _togglePlay,
          onSeek: (ms) {
            _seekMs(ms);
            _scheduleHide();
          },
          onToggleFullscreen: () => _notifier.setFullscreen(!fullscreen),
          onOpenServers: _openServerSheet,
          onDoubleTapLeft: () => _seekMs(_pb.value.positionMs - 10000),
          onDoubleTapRight: () => _seekMs(_pb.value.positionMs + 10000),
          onToggleOverlay: _toggleOverlay,
          onBack: fullscreen ? () => _notifier.setFullscreen(false) : widget.onBackClick,
        );
      },
    );
  }

  // ------------------------------------------------------------- fullscreen

  Widget _fullscreenLayout(PlayerUiState ui) {
    return ColoredBox(
      color: Colors.black,
      child: GestureDetector(
        onHorizontalDragUpdate: (d) {
          if (_vc == null) return;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final deltaMs = (d.delta.dx * dpr * 250).round();
          final dur = _pb.value.durationMs;
          final target = (_pb.value.positionMs + deltaMs).clamp(0, dur < 0 ? 0 : dur).toInt();
          _seekMs(target);
          setState(() => _gestureText = '${formatTime(target)} / ${formatTime(dur)}');
        },
        onHorizontalDragEnd: (_) => setState(() => _gestureText = null),
        onHorizontalDragCancel: () => setState(() => _gestureText = null),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _videoSurface(),
            if (_gestureText != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x991E1B2E),
                    borderRadius: AppShapes.pill,
                  ),
                  child: Text(
                    _gestureText!,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            _controls(ui, fullscreen: true),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- portrait

  Widget _portraitLayout(PlayerUiState ui, bool isFavorite) {
    final currentEp = ui.streamData?.episode ?? _findEpisode(ui);
    final anime = ui.anime;
    final nextEp = ui.streamData?.episodeNext;
    final hasNext = nextEp != null || ui.streamData?.hasNextEpisode == true;
    final syn = anime?.synopsis;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _videoSurface(),
                  _controls(ui, fullscreen: false),
                  if (ui.streamError != null || _playerError) _errorOverlay(),
                  if (ui.autoNextCountdown != null) _countdownOverlay(ui.autoNextCountdown!),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // Judul & badge
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anime?.title ?? 'Anime',
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Episode ${currentEp?.index ?? ''} • ${currentEp?.title ?? ''}',
                        style: const TextStyle(
                          color: AppColors.accentViolet,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (!_blank(anime?.status))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceDark,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                anime!.status!,
                                style: const TextStyle(
                                  color: AppColors.accentViolet,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (!_blank(anime?.year))
                            Text(
                              anime!.year!,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          if (!_blank(anime?.views))
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.visibility_outlined,
                                  size: 12,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  anime!.views!,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Aksi: favorit, bagikan, server, next
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _ActionIconButton(
                              icon: isFavorite ? Icons.bookmark : Icons.bookmark_border,
                              label: 'Favorit',
                              tint: isFavorite ? AppColors.accentViolet : AppColors.textWhite,
                              onTap: () => _notifier.toggleFavorite(),
                            ),
                            _ActionIconButton(
                              icon: Icons.share_outlined,
                              label: 'Bagikan',
                              tint: AppColors.textWhite,
                              onTap: () {
                                final title = anime?.title ?? 'Wibuplay';
                                Share.share(
                                  'Nonton ${anime?.title ?? 'Anime'} di Wibuplay!',
                                  subject: title,
                                );
                              },
                            ),
                            _ActionIconButton(
                              icon: Icons.tune,
                              label: ui.selectedServer?.quality ?? 'Server',
                              tint: AppColors.textWhite,
                              onTap: _openServerSheet,
                            ),
                          ],
                        ),
                      ),
                      if (hasNext)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: FilledButton.icon(
                            onPressed: () {
                              final id = nextEp?.id;
                              if (id != null) _notifier.loadEpisodeStream(id);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accentViolet,
                              foregroundColor: AppColors.textWhite,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            icon: const Icon(Icons.skip_next, size: 18),
                            label: const Text(
                              'Next',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Sinopsis
                if (!_blank(syn))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: AppShapes.card,
                      ),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              syn!,
                              maxLines: _synopsisExpanded ? null : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 18 / 12,
                              ),
                            ),
                            if (syn!.length > 100)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    setState(() => _synopsisExpanded = !_synopsisExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _synopsisExpanded ? 'Tutup' : 'Baca selengkapnya',
                                    style: const TextStyle(
                                      color: AppColors.accentViolet,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Daftar episode
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Daftar Episode (${ui.episodes.length})',
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  controller: _epScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    key: _epRowKey,
                    children: [
                      for (var i = 0; i < ui.episodes.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        _episodeChip(ui, ui.episodes[i]),
                      ],
                    ],
                  ),
                ),

                // Rekomendasi
                if (ui.recommended.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const SectionHeader(title: 'Mungkin Kamu Suka'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 290,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: ui.recommended.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final rec = ui.recommended[i];
                        return Align(
                          alignment: Alignment.topCenter,
                          child: AnimePosterCard(
                            anime: rec,
                            onTap: () {
                              final id = rec.id;
                              if (id != null) widget.onAnimeClick(id);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  EpisodeItem? _findEpisode(PlayerUiState ui) {
    for (final e in ui.episodes) {
      if (e.id == ui.currentEpisodeId) return e;
    }
    return null;
  }

  Widget _episodeChip(PlayerUiState ui, EpisodeItem ep) {
    final isCurrent = ep.id == ui.currentEpisodeId;
    final key = ep.id == null ? null : _epKeys.putIfAbsent(ep.id!, () => GlobalKey());
    return GestureDetector(
      key: key,
      onTap: () {
        final id = ep.id;
        if (id != null) _notifier.loadEpisodeStream(id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent ? AppColors.accentViolet : AppColors.surfaceCard,
          borderRadius: AppShapes.card,
        ),
        child: Text(
          'Ep ${ep.index ?? ''}',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 13,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _errorOverlay() {
    return ColoredBox(
      color: const Color(0xDD1E1B2E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gagal memutar video di server ini',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _openServerSheet,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentViolet,
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Coba Server Lain',
                  style: TextStyle(color: AppColors.textWhite, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countdownOverlay(int countdown) {
    return ColoredBox(
      color: const Color(0xBB1E1B2E),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: AppShapes.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Episode berikutnya dalam ${countdown}d...',
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _notifier.cancelAutoNext(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'Batal',
                    style: TextStyle(
                      color: AppColors.accentViolet,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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

// ---------------------------------------------------------------- komponen

/// Port PlayerControlsOverlay.
class _ControlsOverlay extends StatefulWidget {
  const _ControlsOverlay({
    required this.pb,
    required this.showControls,
    required this.isFullscreen,
    required this.title,
    required this.selectedServer,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onToggleFullscreen,
    required this.onOpenServers,
    required this.onDoubleTapLeft,
    required this.onDoubleTapRight,
    required this.onToggleOverlay,
    required this.onBack,
  });

  final _Playback pb;
  final bool showControls;
  final bool isFullscreen;
  final String title;
  final StreamServer? selectedServer;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSeek;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenServers;
  final VoidCallback onDoubleTapLeft;
  final VoidCallback onDoubleTapRight;
  final VoidCallback onToggleOverlay;
  final VoidCallback onBack;

  @override
  State<_ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  double _downX = 0;

  @override
  Widget build(BuildContext context) {
    final pb = widget.pb;
    final dur = pb.durationMs;
    final sliderMax = (dur < 1 ? 1 : dur).toDouble();
    final sliderValue = dur > 0 ? pb.positionMs.clamp(0, dur).toDouble() : 0.0;

    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggleOverlay,
          onDoubleTapDown: (d) => _downX = d.localPosition.dx,
          onDoubleTap: () {
            if (_downX < c.maxWidth / 2) {
              widget.onDoubleTapLeft();
            } else {
              widget.onDoubleTapRight();
            }
          },
          child: AnimatedOpacity(
            opacity: widget.showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !widget.showControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0x88000000)),
                  // Bar atas: back, judul, chip kualitas
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: widget.onBack,
                                  icon: const Icon(Icons.arrow_back, color: AppColors.textWhite),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textWhite,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: widget.onOpenServers,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0x66FFFFFF),
                                borderRadius: AppShapes.pill,
                              ),
                              child: Text(
                                widget.selectedServer?.quality ?? 'Kualitas',
                                style: const TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Tengah: play / pause / buffering
                  Center(
                    child: GestureDetector(
                      onTap: widget.onTogglePlay,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: Color(0x66000000),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: pb.isBuffering
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    color: AppColors.accentViolet,
                                    strokeWidth: 3,
                                  ),
                                )
                              : Icon(
                                  pb.isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: AppColors.textWhite,
                                  size: 36,
                                ),
                        ),
                      ),
                    ),
                  ),
                  // Bawah: waktu, fullscreen, seek bar
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${formatTime(pb.positionMs)} / ${formatTime(pb.durationMs)}',
                                style: const TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: widget.onToggleFullscreen,
                                  icon: Icon(
                                    widget.isFullscreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    color: AppColors.textWhite,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 20,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbColor: AppColors.accentViolet,
                                activeTrackColor: AppColors.accentViolet,
                                inactiveTrackColor: const Color(0x66FFFFFF),
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                value: sliderValue,
                                min: 0,
                                max: sliderMax,
                                onChanged: (v) => widget.onSeek(v.toInt()),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Port ActionIconButton.
class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppShapes.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: tint),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: tint, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.isSelected, required this.onTap});

  final StreamServer server;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isSelected
            ? AppColors.accentViolet.withValues(alpha: 0.2)
            : AppColors.surfaceElevated,
        borderRadius: AppShapes.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name ?? 'Server Utama',
                        style: TextStyle(
                          color: isSelected ? AppColors.accentViolet : AppColors.textWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Tipe: ${server.type ?? 'direct'}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accentViolet : AppColors.surfaceDark,
                    borderRadius: AppShapes.pill,
                  ),
                  child: Text(
                    server.quality ?? 'Auto',
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
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
