import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/pip_controller.dart';
import '../../../core/premium_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/watch_xp_gate.dart';
import '../../../data/models/comment_models.dart';
import '../../../data/models/episode_item.dart';
import '../../../data/models/stream_data.dart';
import '../../../providers.dart';
import '../../components/cards.dart';
import '../../components/common_components.dart';
import '../../components/mini_player.dart';
import '../../components/net_image.dart';
import '../comments/comments_section.dart';
import 'player_controller.dart';
import 'player_gestures.dart';
import 'player_settings_sheet.dart';
import 'quality_sheet.dart';

/// Link donasi Trakteer (sama dengan Zenime).
const String kTrakteerUrl = 'https://trakteer.id/Dayynimee';

/// Perkiraan intro/outro (API tidak punya timestamp asli), sama dengan Zenime.
const int _kIntroSkipMs = 90000;
const int _kOutroWindowMs = 85000;
// Episode pendek (OVA/klip) tidak di-skip otomatis.
const int _kMinDurationForSkipMs = _kIntroSkipMs * 3;

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
class PlayerPlayback {
  const PlayerPlayback({
    this.isPlaying = false,
    this.isBuffering = true,
    this.positionMs = 0,
    this.durationMs = 0,
  });

  final bool isPlaying;
  final bool isBuffering;
  final int positionMs;
  final int durationMs;

  PlayerPlayback copyWith({int? positionMs}) => PlayerPlayback(
        isPlaying: isPlaying,
        isBuffering: isBuffering,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs,
      );

  @override
  bool operator ==(Object other) =>
      other is PlayerPlayback &&
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
  final ValueNotifier<PlayerPlayback> _pb = ValueNotifier<PlayerPlayback>(const PlayerPlayback());

  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _tick;
  int _tickCount = 0;
  bool _endedHandled = false;
  bool _playerError = false;
  bool _wasPlaying = false;
  String? _gestureText;

  // Fitur pemutar ala Zenime: kecepatan, gesture kecerahan/volume, skip
  // intro/outro, flash seek, daftar episode di fullscreen.
  final PlayerLevels _levels = PlayerLevels();
  double _speed = 1.0;
  bool _outroSkipped = false;
  bool _showEpisodeList = false;
  bool _flashVisible = false;
  bool _flashForward = true;
  Timer? _flashTimer;

  /// Link dari mini player yang diambil alih (supaya tidak reload / ganti kualitas).
  String? _adoptedLink;
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
    _levels.init();
    PipController.isInPip.addListener(_onPip);

    // Dibuka dari mini player untuk episode yang sama: ambil alih controller
    // yang sedang jalan (tanpa reload). Episode lain: mini player ditutup.
    final mini = MiniPlayerManager.instance.consumeForExpand(widget.movieId, widget.episodeId);
    if (mini != null) {
      final vc = mini.controller;
      _vc = vc;
      _loadedLink = mini.info.link;
      _adoptedLink = mini.info.link;
      _speed = mini.info.speed;
      vc.addListener(_onVideo);
      _onVideo();
      final sz = vc.value.size;
      if (sz.width > 0 && sz.height > 0) {
        PipController.setAspectRatio(sz.width.round(), sz.height.round());
      }
    }
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
    _flashTimer?.cancel();
    _levels.dispose();
    PipController.isInPip.removeListener(_onPip);
    PipController.setCanEnter(false);
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
    // File hasil download diputar tanpa cek Premium/kunci episode (dan tanpa
    // menunggu status Premium, yang tidak bisa dicek saat offline).
    if (ui.selectedServer?.link?.startsWith('file://') == true) {
      return (ready: true, locked: false);
    }
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
    _pb.value = const PlayerPlayback(isBuffering: false);
    _wasPlaying = false;
    _playerError = false;
    WakelockPlus.disable();
    if (mounted) setState(() {});
  }

  Future<void> _loadLink(String? link) async {
    if (link == null || link.trim().isEmpty) return;
    final adopted = _adoptedLink;
    if (adopted != null) {
      _adoptedLink = null;
      if (link == adopted) return; // _loadedLink sudah sama
      // Server default beda dengan yang sedang diputar mini player: pilih server
      // yang cocok supaya video yang berjalan tidak diganti.
      final ui = ref.read(playerControllerProvider(_args));
      StreamServer? match;
      for (final sv in ui.streamData?.server ?? const <StreamServer>[]) {
        if (sv.link == adopted) {
          match = sv;
          break;
        }
      }
      if (match != null) {
        _notifier.selectServer(match);
        return;
      }
    }
    if (link == _loadedLink) return;
    _loadedLink = link;

    final old = _vc;
    old?.removeListener(_onVideo);
    final resumeMs = ref.read(playerControllerProvider(_args)).resumePositionMs;

    final VideoPlayerController vc;
    try {
      vc = link.startsWith('file://')
          ? VideoPlayerController.file(File.fromUri(Uri.parse(link)))
          : VideoPlayerController.networkUrl(Uri.parse(link));
    } catch (_) {
      if (mounted) setState(() => _playerError = true);
      return;
    }
    _vc = vc;
    _endedHandled = false;
    _outroSkipped = false;
    _wasPlaying = false;
    _playerError = false;
    _pb.value = const PlayerPlayback();
    if (mounted) setState(() {});
    await old?.dispose();

    try {
      await vc.initialize();
      if (!mounted || _vc != vc) return;
      if (resumeMs > 0) {
        await vc.seekTo(Duration(milliseconds: resumeMs));
      } else if (ref.read(localStoreProvider).autoSkipIntro &&
          vc.value.duration.inMilliseconds > _kMinDurationForSkipMs) {
        // Episode dibuka dari awal: lompati intro.
        await vc.seekTo(const Duration(milliseconds: _kIntroSkipMs));
      }
      if (!mounted || _vc != vc) return;
      final sz = vc.value.size;
      if (sz.width > 0 && sz.height > 0) {
        PipController.setAspectRatio(sz.width.round(), sz.height.round());
      }
      vc.addListener(_onVideo);
      await vc.play();
      if (!mounted || _vc != vc) return;
      if (_speed != 1.0) await vc.setPlaybackSpeed(_speed);
      if (!mounted || _vc != vc) return;
      _onVideo();
      setState(() {});
    } catch (_) {
      if (mounted && _vc == vc) {
        _pb.value = const PlayerPlayback(isBuffering: false);
        setState(() => _playerError = true);
      }
    }
  }

  void _onVideo() {
    final vc = _vc;
    if (vc == null || !mounted) return;
    final v = vc.value;
    if (v.hasError && !_playerError) setState(() => _playerError = true);

    final snap = PlayerPlayback(
      isPlaying: v.isPlaying,
      isBuffering: v.hasError ? false : (v.isBuffering || !v.isInitialized),
      positionMs: v.position.inMilliseconds,
      durationMs: v.duration.inMilliseconds < 0 ? 0 : v.duration.inMilliseconds,
    );
    _pb.value = snap;

    if (snap.isPlaying != _wasPlaying) {
      _wasPlaying = snap.isPlaying;
      WakelockPlus.toggle(enable: snap.isPlaying);
      // Auto-PiP saat pindah app hanya selama video memutar.
      PipController.setCanEnter(snap.isPlaying);
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

    // Auto-lanjut saat masuk zona outro (mepet habis), kalau ada episode
    // berikutnya dan episodenya cukup panjang.
    if (!_outroSkipped &&
        dur > _kMinDurationForSkipMs &&
        dur - vc.value.position.inMilliseconds <= _kOutroWindowMs &&
        ref.read(localStoreProvider).autoSkipOutro &&
        _notifier.nextEpisodeId != null) {
      _outroSkipped = true;
      _notifier.playNext();
      return;
    }

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

  // ------------------------------------------------- PiP & mini player

  bool get _inPip => PipController.isInPip.value;

  void _onPip() {
    if (!mounted) return;
    setState(() {});
    if (!_inPip) {
      // Jendela PiP ditutup (X): activity berhenti, jadi hentikan suaranya.
      // Kalau user justru membuka kembali (expand), app sudah di depan.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_inForeground) _vc?.pause();
      });
    }
  }

  Future<void> _enterPip() async {
    final ok = await PipController.enter();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Picture-in-Picture tidak tersedia di perangkat ini')),
        );
    }
  }

  /// Share sheet / browser memicu onUserLeaveHint; matikan auto-PiP sementara.
  Future<void> _withoutPip(Future<void> Function() action) async {
    await PipController.setCanEnter(false);
    try {
      await action();
    } finally {
      PipController.setCanEnter(_pb.value.isPlaying);
    }
  }

  /// Back dari layar player: video dititipkan ke mini player (tetap jalan) alih-alih
  /// dihentikan. Kalau belum siap / error / terkunci / sudah selesai, pop biasa.
  void _minimizeAndPop(PlayerUiState ui) {
    final vc = _vc;
    final link = _loadedLink;
    final gate = _gate(ui, ref.read(myPremiumProvider));
    if (vc != null &&
        link != null &&
        vc.value.isInitialized &&
        !_playerError &&
        !gate.locked &&
        !_endedHandled) {
      final dur = vc.value.duration.inMilliseconds;
      if (dur > 0) _notifier.saveProgress(vc.value.position.inMilliseconds, dur);
      vc.removeListener(_onVideo);
      _vc = null; // kepemilikan pindah ke mini player, jangan di-dispose di sini
      _loadedLink = null;
      final anime = ui.anime;
      final ep = ui.streamData?.episode ?? _findEpisode(ui);
      final poster = anime == null
          ? ''
          : (anime.posterUrl.isNotEmpty ? anime.posterUrl : anime.coverUrl);
      MiniPlayerManager.instance.activate(
        vc,
        MiniPlayerInfo(
          movieId: ui.movieId,
          episodeId: ui.currentEpisodeId,
          title: anime?.title ?? 'Anime',
          episodeLabel: 'Ep ${ep?.index ?? ''}',
          posterUrl: poster,
          link: link,
          speed: _speed,
        ),
      );
      WakelockPlus.disable();
    }
    Navigator.of(context).pop();
  }

  void _seekBy(int deltaMs) {
    _seekMs(_pb.value.positionMs + deltaMs);
    _scheduleHide();
  }

  void _doubleTapSeek({required bool forward}) {
    _seekMs(_pb.value.positionMs + (forward ? 10000 : -10000));
    _flashTimer?.cancel();
    setState(() {
      _flashForward = forward;
      _flashVisible = true;
    });
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashVisible = false);
    });
  }

  void _setSpeed(double v) {
    _speed = v;
    _vc?.setPlaybackSpeed(v);
    if (mounted) setState(() {});
  }

  void _openSettingsSheet() {
    final store = ref.read(localStoreProvider);
    showPlayerSettingsSheet(
      context,
      speed: _speed,
      autoSkipIntro: store.autoSkipIntro,
      autoSkipOutro: store.autoSkipOutro,
      onSpeed: _setSpeed,
      onAutoSkipIntro: store.setAutoSkipIntro,
      onAutoSkipOutro: store.setAutoSkipOutro,
    );
  }

  /// Flash "10 detik" di sisi layar yang di-double-tap.
  Widget _seekFlash() {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _flashVisible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Align(
          alignment: _flashForward ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x990B0E14),
                borderRadius: AppShapes.pill,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _flashForward ? Icons.forward_10 : Icons.replay_10,
                    color: AppColors.textWhite,
                    size: 24,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _flashForward ? '+10 dtk' : '-10 dtk',
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Panel daftar episode di fullscreen (port EpisodeListSidebar Zenime).
  Widget _episodeSidebar(PlayerUiState ui) {
    final isPremium = ref.watch(myPremiumProvider).valueOrNull ?? true;
    final total = latestEpisodeIndex(ui.episodes.map((e) => e.index));
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 280,
        color: const Color(0xF20B0E14),
        child: SafeArea(
          left: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Daftar Episode',
                        style: TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _showEpisodeList = false),
                      icon: const Icon(Icons.close, color: AppColors.textWhite, size: 20),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: ui.episodes.length,
                  itemBuilder: (context, i) {
                    final ep = ui.episodes[i];
                    final isCurrent = ep.id == ui.currentEpisodeId;
                    final locked = isEpisodeLocked(ep.index, total, isPremium);
                    return InkWell(
                      onTap: () {
                        final id = ep.id;
                        setState(() => _showEpisodeList = false);
                        if (id != null && !isCurrent) _notifier.loadEpisodeStream(id);
                      },
                      child: Container(
                        color: isCurrent
                            ? AppColors.accentViolet.withValues(alpha: 0.18)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            if (locked) ...[
                              const Icon(Icons.lock, size: 14, color: AppColors.accentViolet),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              'Ep ${ep.index ?? ''}',
                              style: TextStyle(
                                color: isCurrent
                                    ? AppColors.accentVioletLight
                                    : AppColors.textWhite,
                                fontSize: 13,
                                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            if (!_blank(ep.title)) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  ep.title!,
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
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
    _showEpisodeList = false;
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
    var ok = false;
    await _withoutPip(() async {
      ok = await launchUrl(
        Uri.parse(kTrakteerUrl),
        mode: LaunchMode.externalApplication,
      );
    });
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
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (ui.isFullscreen) {
          if (_showEpisodeList) {
            setState(() => _showEpisodeList = false);
          } else {
            _notifier.setFullscreen(false);
          }
          return;
        }
        _minimizeAndPop(ui);
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: _inPip
            ? SizedBox.expand(child: _videoSurface())
            : (ui.isFullscreen
                ? _fullscreenLayout(ui, gate)
                : _portraitLayout(ui, isFavorite, gate)),
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
    final prevId = _notifier.previousEpisodeId;
    final nextId = _notifier.nextEpisodeId;
    return ValueListenableBuilder<PlayerPlayback>(
      valueListenable: _pb,
      builder: (context, pb, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            PlayerControlsOverlay(
              pb: pb,
              showControls: _showControls,
              isFullscreen: fullscreen,
              title: _overlayTitle(ui),
              selectedServer: ui.selectedServer,
              speed: _speed,
              showSkipIntro:
                  pb.positionMs < _kIntroSkipMs && pb.durationMs > _kMinDurationForSkipMs,
              onTogglePlay: _togglePlay,
              onSeek: (ms) {
                _seekMs(ms);
                _scheduleHide();
              },
              onToggleFullscreen: () => _notifier.setFullscreen(!fullscreen),
              onOpenServers: _openServerSheet,
              onOpenSettings: _openSettingsSheet,
              onEnterPip: _enterPip,
              onOpenEpisodes: fullscreen
                  ? () => setState(() {
                        _showEpisodeList = true;
                        _showControls = false;
                      })
                  : null,
              onRewind: () => _seekBy(-10000),
              onForward: () => _seekBy(10000),
              onPrev: prevId == null ? null : _notifier.playPrevious,
              onNext: nextId == null ? null : _notifier.playNext,
              onSkipIntro: () {
                _seekMs(_kIntroSkipMs);
                _scheduleHide();
              },
              onDoubleTapLeft: () => _doubleTapSeek(forward: false),
              onDoubleTapRight: () => _doubleTapSeek(forward: true),
              onToggleOverlay: _toggleOverlay,
              onBack: fullscreen ? () => _notifier.setFullscreen(false) : widget.onBackClick,
            ),
            // Spinner buffering tetap tampil walau kontrol disembunyikan.
            if (pb.isBuffering && !_showControls)
              const IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: AppColors.accentViolet,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
          ],
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
        child: PlayerGestureLayer(
          levels: _levels,
          child: Stack(
          fit: StackFit.expand,
          children: [
            _videoSurface(),
            if (_gestureText != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x990B0E14),
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
            _seekFlash(),
            if (_showEpisodeList)
              GestureDetector(
                // Serap swipe horizontal supaya tidak ikut menggeser video.
                onHorizontalDragUpdate: (_) {},
                child: _episodeSidebar(ui),
              ),
            if (gate.locked) _lockedOverlay(fullscreen: true),
          ],
        ),
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
              child: PlayerGestureLayer(
                levels: _levels,
                child: Stack(
                fit: StackFit.expand,
                children: [
                  _videoSurface(),
                  _controls(ui, fullscreen: false),
                  _seekFlash(),
                  if (!gate.locked && (ui.streamError != null || _playerError)) _errorOverlay(),
                  if (!gate.locked && ui.autoNextCountdown != null)
                    _countdownOverlay(ui.autoNextCountdown!),
                  if (gate.locked) _lockedOverlay(fullscreen: false),
                ],
              ),
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
                    child: PlayerTrakteerButton(onTap: _openTrakteer),
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
                              _withoutPip(() => Share.share(text, subject: title));
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
      color: const Color(0xDD0B0E14),
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
      color: const Color(0xBB0B0E14),
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
class PlayerControlsOverlay extends StatefulWidget {
  const PlayerControlsOverlay({
    required this.pb,
    required this.showControls,
    required this.isFullscreen,
    required this.title,
    required this.selectedServer,
    required this.speed,
    required this.showSkipIntro,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onToggleFullscreen,
    required this.onOpenServers,
    required this.onOpenSettings,
    required this.onEnterPip,
    required this.onOpenEpisodes,
    required this.onRewind,
    required this.onForward,
    required this.onPrev,
    required this.onNext,
    required this.onSkipIntro,
    required this.onDoubleTapLeft,
    required this.onDoubleTapRight,
    required this.onToggleOverlay,
    required this.onBack,
  });

  final PlayerPlayback pb;
  final bool showControls;
  final bool isFullscreen;
  final String title;
  final StreamServer? selectedServer;
  final double speed;
  final bool showSkipIntro;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSeek;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenSettings;
  final VoidCallback onEnterPip;

  /// Hanya diisi di fullscreen (panel daftar episode).
  final VoidCallback? onOpenEpisodes;
  final VoidCallback onRewind;
  final VoidCallback onForward;

  /// null = tidak ada episode sebelumnya/berikutnya.
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onSkipIntro;
  final VoidCallback onDoubleTapLeft;
  final VoidCallback onDoubleTapRight;
  final VoidCallback onToggleOverlay;
  final VoidCallback onBack;

  @override
  State<PlayerControlsOverlay> createState() => PlayerControlsOverlayState();
}

class PlayerControlsOverlayState extends State<PlayerControlsOverlay> {
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.onOpenEpisodes != null) ...[
                                GestureDetector(
                                  onTap: widget.onOpenEpisodes,
                                  child: const Icon(
                                    Icons.playlist_play,
                                    color: AppColors.textWhite,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              GestureDetector(
                                onTap: widget.onEnterPip,
                                child: const Icon(
                                  Icons.picture_in_picture_alt,
                                  color: AppColors.textWhite,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: widget.onOpenSettings,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x66FFFFFF),
                                    borderRadius: AppShapes.pill,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.speed,
                                        size: 13,
                                        color: AppColors.textWhite,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        speedLabel(widget.speed),
                                        style: const TextStyle(
                                          color: AppColors.textWhite,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
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
                        ],
                      ),
                    ),
                  ),
                  // Tengah: prev / -10 / play-pause / +10 / next
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onPrev != null) ...[
                          _RoundControl(icon: Icons.skip_previous, onTap: widget.onPrev!),
                          const SizedBox(width: 14),
                        ],
                        _RoundControl(icon: Icons.replay_10, onTap: widget.onRewind),
                        const SizedBox(width: 14),
                        GestureDetector(
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
                        const SizedBox(width: 14),
                        _RoundControl(icon: Icons.forward_10, onTap: widget.onForward),
                        if (widget.onNext != null) ...[
                          const SizedBox(width: 14),
                          _RoundControl(icon: Icons.skip_next, onTap: widget.onNext!),
                        ],
                      ],
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
                            children: [
                              Text(
                                '${formatTime(pb.positionMs)} / ${formatTime(pb.durationMs)}',
                                style: const TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              if (widget.showSkipIntro) ...[
                                _SkipIntroPill(onTap: widget.onSkipIntro),
                                const SizedBox(width: 8),
                              ],
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

/// Tombol bulat transparan kecil di tengah pemutar (prev / -10 / +10 / next),
/// dengan gaya yang sama seperti lingkaran play Wibuplay.
class _RoundControl extends StatelessWidget {
  const _RoundControl({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0x66000000),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.textWhite, size: 24),
      ),
    );
  }
}

/// Pill "Lewati Intro" (muncul 90 detik pertama).
class _SkipIntroPill extends StatelessWidget {
  const _SkipIntroPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppShapes.pill,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fast_forward, size: 14, color: AppColors.accentViolet),
            SizedBox(width: 4),
            Text(
              'Lewati Intro',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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
class PlayerTrakteerButton extends StatelessWidget {
  const PlayerTrakteerButton({required this.onTap});

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
