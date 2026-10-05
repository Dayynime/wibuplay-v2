import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/premium_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/watch_xp_gate.dart';
import '../../../data/models/comment_models.dart';
import '../../../data/models/episode_item.dart';
import '../../../data/models/stream_data.dart';
import '../../../providers.dart';
import '../../components/cards.dart';
import '../../components/common_components.dart';
import '../../components/net_image.dart';
import '../comments/comments_section.dart';
import 'player_controller.dart';
import 'quality_sheet.dart';

/// Link donasi Trakteer (sama dengan Zenime).
const String _kTrakteerUrl = 'https://trakteer.id/Dayynimee';

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
  final GlobalKey _commentsKey = GlobalKey();

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
      _applyPlayback();
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

  /// Index episode yang sedang dibuka. Diambil dari daftar episode (cocok id),
  /// fallback ke data stream cuma kalau id-nya sama. Null = belum diketahui.
  String? _currentIndex(PlayerUiState ui) {
    for (final e in ui.episodes) {
      if (e.id == ui.currentEpisodeId) return e.index;
    }
    final se = ui.streamData?.episode;
    if (se != null && se.id == ui.currentEpisodeId) return se.index;
    return null;
  }

  /// ready = sudah cukup data buat memutuskan (status premium + daftar episode).
  /// Sebelum itu video tidak diputar, supaya suara episode terkunci tidak bocor.
  ({bool ready, bool locked}) _gate(PlayerUiState ui, AsyncValue<bool> premium) {
    final isPremium = premium.valueOrNull ?? false;
    final decided = premium.hasValue || premium.hasError;
    if (isPremium) return (ready: true, locked: false);
    if (!decided || !ui.episodesLoaded) return (ready: false, locked: false);
    final total = latestEpisodeIndex(ui.episodes.map((e) => e.index));
    return (ready: true, locked: isEpisodeLocked(_currentIndex(ui), total, false));
  }

  /// Satu pintu buat nyalain/matiin pemutar sesuai status kunci.
  void _applyPlayback() {
    if (!mounted) return;
    final ui = ref.read(playerControllerProvider(_args));
    final gate = _gate(ui, ref.read(myPremiumProvider));
    if (gate.locked) {
      _stopPlayer();
      return;
    }
    if (!gate.ready) return;

    // Non-premium dibatasi kualitas maksimal (sama seperti Zenime). Kalau
    // server default ternyata di atas batas, turunkan ke yang tertinggi
    // yang masih boleh; selectServer memicu _applyPlayback lagi.
    final isPremium = ref.read(myPremiumProvider).valueOrNull ?? false;
    final sel = ui.selectedServer;
    if (!isPremium && sel != null && isQualityLocked(sel.quality, false)) {
      final fallback = _bestUnlockedServer(ui.streamData?.server ?? const []);
      if (fallback != null) {
        _notifier.selectServer(fallback);
        return;
      }
    }
    _loadLink(sel?.link);
  }

  StreamServer? _bestUnlockedServer(List<StreamServer> servers) {
    StreamServer? best;
    var bestValue = -1;
    for (final s in servers) {
      final link = s.link;
      if (link == null || link.trim().isEmpty) continue;
      if (isQualityLocked(s.quality, false)) continue;
      final v = qualityValueP(s.quality) ?? 0;
      if (v > bestValue) {
        best = s;
        bestValue = v;
      }
    }
    return best;
  }

  void _stopPlayer() {
    final vc = _vc;
    _loadedLink = null;
    if (vc == null) return;
    _vc = null;
    vc.removeListener(_onVideo);
    vc.pause();
    vc.dispose();
    _pb.value = const _Playback(isBuffering: false);
    _wasPlaying = false;
    _playerError = false;
    WakelockPlus.disable();
    if (mounted) setState(() {});
  }

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

  void _showPremiumHint() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Kualitas di atas 480p khusus Premium. Aktifkan Premium lewat menu Profil.',
          ),
        ),
      );
  }

  void _openServerSheet() {
    final ui = ref.read(playerControllerProvider(_args));
    showQualityPickerSheet(
      context,
      servers: ui.streamData?.server ?? const <StreamServer>[],
      selected: ui.selectedServer,
      isPremium: ref.read(myPremiumProvider).valueOrNull ?? false,
      onSelect: _notifier.selectServer,
      onLocked: _showPremiumHint,
    );
  }

  Future<void> _openTrakteer() async {
    final ok = await launchUrl(
      Uri.parse(_kTrakteerUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada browser untuk membuka Trakteer')),
      );
    }
  }

  void _scrollToComments() {
    final ctx = _commentsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.0,
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(playerControllerProvider(_args));
    final isFavorite = ref.watch(localStoreProvider.select((s) => s.isFavorite(ui.movieId)));

    final premium = ref.watch(myPremiumProvider);
    final gate = _gate(ui, premium);
    ref.listen<(String?, String, bool, int)>(
      playerControllerProvider(_args).select(
        (s) => (s.selectedServer?.link, s.currentEpisodeId, s.episodesLoaded, s.episodes.length),
      ),
      (prev, next) => _applyPlayback(),
    );
    ref.listen<AsyncValue<bool>>(myPremiumProvider, (prev, next) => _applyPlayback());
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
        body: ui.isFullscreen
            ? _fullscreenLayout(ui, gate)
            : _portraitLayout(ui, isFavorite, gate),
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

  Widget _fullscreenLayout(PlayerUiState ui, ({bool ready, bool locked}) gate) {
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
            if (gate.locked) _lockedOverlay(fullscreen: true),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- portrait

  Widget _portraitLayout(PlayerUiState ui, bool isFavorite, ({bool ready, bool locked}) gate) {
    final currentEp = ui.streamData?.episode ?? _findEpisode(ui);
    final anime = ui.anime;
    final nextEp = ui.streamData?.episodeNext;
    final hasNext = nextEp != null || ui.streamData?.hasNextEpisode == true;
    final syn = anime?.synopsis;
    // Loading dianggap premium biar ikon gembok tidak berkedip.
    final chipPremium = ref.watch(myPremiumProvider).valueOrNull ?? true;
    final totalEps = latestEpisodeIndex(ui.episodes.map((e) => e.index));
    // Layar edge-to-edge: tanpa ini konten paling bawah tertutup tombol
    // navigasi HP.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    final posterUrl = anime == null
        ? ''
        : (anime.posterUrl.isNotEmpty ? anime.posterUrl : anime.coverUrl);
    final epTitle = currentEp?.title;
    final viewsLabel = formatViewCount(anime?.views);
    final aired = !_blank(anime?.airedStart) ? anime!.airedStart! : anime?.year;
    final showComments = ui.currentEpisodeId.trim().isNotEmpty;

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
                  if (!gate.locked && (ui.streamError != null || _playerError)) _errorOverlay(),
                  if (!gate.locked && ui.autoNextCountdown != null)
                    _countdownOverlay(ui.autoNextCountdown!),
                  if (gate.locked) _lockedOverlay(fullscreen: false),
                ],
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                // 1. Poster kecil + judul + info episode (gaya Zenime)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 80,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ColoredBox(
                                color: AppColors.surfaceVariantDark,
                                child: NetImage(posterUrl),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                anime?.title ?? 'Memuat...',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Episode ${currentEp?.index ?? '-'}'
                                '${_blank(epTitle) ? '' : ' \u2022 $epTitle'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (viewsLabel != null) ...[
                                    const Icon(
                                      Icons.visibility_outlined,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      viewsLabel,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  if (!_blank(aired)) ...[
                                    if (viewsLabel != null)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Text(
                                          '\u2022',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    Flexible(
                                      child: Text(
                                        aired!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Sinopsis (expandable)
                if (!_blank(syn))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                                fontSize: 13,
                                height: 20 / 13,
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setState(() => _synopsisExpanded = !_synopsisExpanded),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _synopsisExpanded ? 'Sembunyikan' : 'Selengkapnya',
                                  style: const TextStyle(
                                    color: AppColors.accentViolet,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 3. Tombol donasi Trakteer
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _TrakteerButton(onTap: _openTrakteer),
                  ),
                ),

                // 4. Baris tombol aksi
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _ActionIconButton(
                            icon: Icons.high_quality,
                            label: 'Kualitas',
                            tint: AppColors.textSecondary,
                            onTap: _openServerSheet,
                          ),
                          const SizedBox(width: 10),
                          _ActionIconButton(
                            icon: isFavorite ? Icons.bookmark : Icons.bookmark_border,
                            label: 'Favorit',
                            tint: isFavorite ? AppColors.accentViolet : AppColors.textSecondary,
                            onTap: () => _notifier.toggleFavorite(),
                          ),
                          const SizedBox(width: 10),
                          _ActionIconButton(
                            icon: Icons.chat,
                            label: 'Komentar',
                            tint: AppColors.textSecondary,
                            onTap: _scrollToComments,
                          ),
                          const SizedBox(width: 10),
                          _ActionIconButton(
                            icon: Icons.flag,
                            label: 'Laporkan',
                            tint: AppColors.textSecondary,
                            onTap: () {
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text('Fitur laporkan segera hadir'),
                                  ),
                                );
                            },
                          ),
                          const SizedBox(width: 10),
                          _ActionIconButton(
                            icon: Icons.share,
                            label: 'Bagikan',
                            tint: AppColors.textSecondary,
                            onTap: () {
                              final title = anime?.title ?? 'anime ini';
                              final idx = currentEp?.index;
                              final text = _blank(idx)
                                  ? 'Nonton "$title" di Zenime!'
                                  : 'Nonton "$title" Episode $idx di Zenime!';
                              Share.share(text, subject: title);
                            },
                          ),
                          if (hasNext) ...[
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: () {
                                final id = nextEp?.id;
                                if (id != null) _notifier.loadEpisodeStream(id);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accentViolet,
                                foregroundColor: AppColors.textWhite,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                              icon: const Icon(Icons.skip_next, size: 18),
                              label: const Text(
                                'Next',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // 5. Daftar episode (tetap seperti sebelumnya)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              _episodeChip(
                                ui,
                                ui.episodes[i],
                                isEpisodeLocked(ui.episodes[i].index, totalEps, chipPremium),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 5b. Mungkin Kamu Suka (dipertahankan dari versi sebelumnya)
                if (ui.recommended.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                    ),
                  ),

                // 6. Komentar episode (inline, di bawah Daftar Episode)
                if (showComments)
                  CommentsSliver(
                    key: ValueKey('comments-${ui.currentEpisodeId}'),
                    args: (ui.currentEpisodeId, ui.movieId),
                    meta: CommentMeta(
                      animeTitle: anime?.title,
                      animePosterUrl: posterUrl.isEmpty ? null : posterUrl,
                      episodeIndex: currentEp?.index,
                    ),
                    headerKey: _commentsKey,
                    onUpgradeClick: () => ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Sorotan komentar khusus Premium. Aktifkan Premium lewat menu Profil.',
                          ),
                        ),
                      ),
                  ),

                SliverToBoxAdapter(child: SizedBox(height: bottomInset + 28)),
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

  Widget _episodeChip(PlayerUiState ui, EpisodeItem ep, bool locked) {
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked) ...[
              const Icon(Icons.lock, size: 12, color: AppColors.textWhite),
              const SizedBox(width: 4),
            ],
            Text(
              'Ep ${ep.index ?? ''}',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Menutup area video (termasuk kontrol) kalau episode ini khusus Premium.
  Widget _lockedOverlay({required bool fullscreen}) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.backgroundDark,
        child: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: fullscreen
                      ? () => _notifier.setFullscreen(false)
                      : widget.onBackClick,
                  icon: const Icon(Icons.arrow_back, color: AppColors.textWhite),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock, size: 30, color: AppColors.accentViolet),
                      const SizedBox(height: 8),
                      const Text(
                        'Episode terbaru khusus Premium',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$kLockedLatestEpisodesCount episode terbaru bisa ditonton dengan Premium. '
                        'Episode sebelumnya tetap gratis.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
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

/// Chip aksi di bawah video (gaya PlayerActionChip Zenime).
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariantDark,
          borderRadius: AppShapes.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: tint),
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

/// Tombol "Bantu Admin Seikhlasnya" (Trakteer), sama dengan Zenime.
class _TrakteerButton extends StatelessWidget {
  const _TrakteerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF29ABE2);
    return Material(
      color: blue.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: blue, shape: BoxShape.circle),
                child: const Icon(Icons.favorite, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bantu Admin Seikhlasnya',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Traktir admin lewat Trakteer, ya!',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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

/// Angka mentah jadi label ringkas "24.5K"; null kalau kosong/tidak valid.
String? formatViewCount(String? raw) {
  final v = int.tryParse((raw ?? '').trim());
  if (v == null) return null;
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toString();
}
