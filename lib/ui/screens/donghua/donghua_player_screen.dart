import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/error_message.dart';
import '../../../core/pip_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/watch_xp_gate.dart';
import '../../../data/api/anichin_network.dart';
import '../../../data/models/anichin_models.dart';
import '../../../data/models/comment_models.dart';
import '../../../data/models/stream_data.dart';
import '../../../data/repository/anichin_repository.dart';
import '../../../providers.dart';
import '../../components/common_components.dart';
import '../comments/comments_section.dart';
import '../player/player_gestures.dart';
import '../player/player_screen.dart';
import '../player/quality_sheet.dart';
import 'donghua_widgets.dart';

/// Link video langsung (GET /video-source/{slug}). Dijaga token premium di
/// server. Diambil FRESH tiap layar dibuka (link ada masa berlakunya).
final donghuaVideoProvider =
    FutureProvider.autoDispose.family<AnichinVideoSource, String>(
  (ref, slug) => ref.watch(anichinRepositoryProvider).getVideoSource(slug),
);

/// Info episode + daftar episode (GET /episode/{slug}). Jalan PARALEL dengan
/// [donghuaVideoProvider], jadi video tidak menunggu info episode.
final donghuaEpisodeProvider =
    FutureProvider.autoDispose.family<AnichinEpisodeDetail, String>(
  (ref, slug) => ref.watch(anichinRepositoryProvider).getEpisode(slug),
);

// Ambil "Episode 16" dari judul "Judul Anime Episode 16 Subtitle Indonesia".
final RegExp _epTitle = RegExp(r'\s*[-–]?\s*Episode\s*(\d+).*$', caseSensitive: false);

String? _animeTitleOf(String? episodeName) {
  final t = episodeName?.replaceAll(_epTitle, '').trim();
  return (t == null || t.isEmpty) ? null : t;
}

String? _episodeNumberOf(String? episodeName, AnichinEpisodeRef? ref) {
  final fromRef = ref?.episode?.trim();
  if (fromRef != null && fromRef.isNotEmpty) return fromRef;
  return _epTitle.firstMatch(episodeName ?? '')?.group(1);
}

/// Port DonghuaPlayerScreen.kt. Tampilan disamakan dengan player anime
/// (kontrol custom, gestur kecerahan/volume, double-tap +-10 detik), lalu di
/// bawah video ada poster + sinopsis, banner Trakteer, chip aksi, daftar
/// episode bergambar, dan komentar. Komponen UI dipakai ulang dari
/// player_screen.dart; datanya dari API Anichin.
class DonghuaPlayerScreen extends ConsumerStatefulWidget {
  const DonghuaPlayerScreen({
    super.key,
    required this.slug,
    required this.onBackClick,
    required this.onEpisodeChange,
    required this.onUpgradeClick,
  });

  final String slug;
  final VoidCallback onBackClick;
  final ValueChanged<String> onEpisodeChange;
  final VoidCallback onUpgradeClick;

  @override
  ConsumerState<DonghuaPlayerScreen> createState() => _DonghuaPlayerScreenState();
}

class _DonghuaPlayerScreenState extends ConsumerState<DonghuaPlayerScreen>
    with WidgetsBindingObserver {
  /// false saat app di background: detik itu tidak dihitung untuk XP.
  bool _inForeground = true;

  VideoPlayerController? _vc;
  String? _loadedUrl;
  String? _pendingUrl;
  final ValueNotifier<PlayerPlayback> _pb =
      ValueNotifier<PlayerPlayback>(const PlayerPlayback());

  bool _showControls = true;
  bool _fullscreen = false;
  bool _playerError = false;
  bool _wasPlaying = false;
  bool _showEpisodeList = false;
  Timer? _hideTimer;
  Timer? _tick;
  Timer? _flashTimer;

  final PlayerLevels _levels = PlayerLevels();
  double _speed = 1.0;
  bool _flashVisible = false;
  bool _flashForward = true;

  /// Pilihan kualitas dari user (kode mentah: sd/hd/...). null = otomatis.
  String? _selectedQuality;
  bool _synopsisExpanded = false;
  final GlobalKey _commentsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _tick = Timer.periodic(const Duration(seconds: 1), _onTick);
    _levels.init();
    PipController.isInPip.addListener(_onPip);
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
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // ---------------------------------------------------------------- pemutar

  /// Putar [url] (mp4 OK.ru). Posisi terakhir dipertahankan kalau cuma ganti
  /// kualitas. Header User-Agent + Referer wajib, kalau tidak server menolak.
  Future<void> _loadUrl(String url) async {
    if (!mounted || url == _loadedUrl) return;
    _loadedUrl = url;
    _pendingUrl = null;

    final old = _vc;
    final resumeMs = old?.value.position.inMilliseconds ?? 0;
    old?.removeListener(_onVideo);

    final VideoPlayerController vc;
    try {
      vc = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: AnichinNetwork.videoHeaders,
      );
    } catch (_) {
      if (mounted) setState(() => _playerError = true);
      return;
    }
    _vc = vc;
    _wasPlaying = false;
    _playerError = false;
    _pb.value = const PlayerPlayback();
    if (mounted) setState(() {});
    await old?.dispose();

    try {
      await vc.initialize();
      if (!mounted || _vc != vc) return;
      if (resumeMs > 0) await vc.seekTo(Duration(milliseconds: resumeMs));
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
  }

  void _onTick(Timer t) {
    if (!mounted) return;
    final vc = _vc;
    if (vc == null || !vc.value.isPlaying) return;
    // XP nonton: hanya detik aktif (playing, tidak buffering, app di depan).
    // Hitungan XP global lewat WatchXpGate (bukan per player).
    if (_inForeground && !vc.value.isBuffering && WatchXpGate.onActiveSecond(this)) {
      unawaited(
        ref.read(xpRepositoryProvider).sendHeartbeat(minutes: 1).then((ok) {
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

  void _seekBy(int deltaMs) {
    _seekMs(_pb.value.positionMs + deltaMs);
    _scheduleHide();
  }

  void _togglePlay() {
    final vc = _vc;
    if (vc == null) return;
    vc.value.isPlaying ? vc.pause() : vc.play();
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

  // ---------------------------------------------------------------- kontrol

  bool get _inPip => PipController.isInPip.value;

  void _onPip() {
    if (!mounted) return;
    setState(() {
      if (_inPip) {
        _showControls = false;
        _showEpisodeList = false;
      }
    });
    if (!_inPip) {
      // Jendela PiP ditutup (X): activity berhenti, hentikan suaranya.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_inForeground) _vc?.pause();
      });
    }
  }

  Future<void> _enterPip() async {
    final ok = await PipController.enter();
    if (!ok && mounted) {
      _toast('Picture-in-Picture tidak tersedia di perangkat ini');
    }
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

  void _setFullscreen(bool fullscreen) {
    setState(() {
      _fullscreen = fullscreen;
      _showEpisodeList = false;
    });
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

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _openSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kecepatan Putar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in speeds)
                    GestureDetector(
                      onTap: () {
                        _setSpeed(s);
                        Navigator.of(sheetContext).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: s == _speed
                              ? AppColors.accentViolet.withValues(alpha: 0.2)
                              : AppColors.surfaceVariantDark,
                          borderRadius: BorderRadius.circular(100),
                          border: s == _speed
                              ? Border.all(color: AppColors.accentViolet)
                              : null,
                        ),
                        child: Text(
                          s == 1.0 ? 'Normal' : '${s}x',
                          style: TextStyle(
                            color: s == _speed ? AppColors.accentViolet : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
    );
  }

  void _openQualitySheet(List<AnichinMedia> medias, String? selected, bool isPremium) {
    final servers = [
      for (final m in medias)
        StreamServer(
          link: m.url,
          quality: AnichinRepository.qualityLabel(m.quality),
          name: m.quality,
        ),
    ];
    StreamServer? current;
    for (final s in servers) {
      if (s.name == selected) current = s;
    }
    showQualityPickerSheet(
      context,
      servers: servers,
      selected: current,
      isPremium: isPremium,
      onSelect: (s) => setState(() => _selectedQuality = s.name),
      onLocked: widget.onUpgradeClick,
    );
  }

  Future<void> _openTrakteer() async {
    var ok = false;
    await PipController.setCanEnter(false);
    try {
      ok = await launchUrl(Uri.parse(kTrakteerUrl), mode: LaunchMode.externalApplication);
    } finally {
      PipController.setCanEnter(_pb.value.isPlaying);
    }
    if (!ok && mounted) _toast('Tidak ada browser untuk membuka Trakteer');
  }

  void _scrollToComments() {
    final ctx = _commentsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _share(String? title, String? epNumber) async {
    final t = title ?? 'donghua ini';
    final text = (epNumber != null && epNumber.isNotEmpty)
        ? 'Nonton "$t" Episode $epNumber di Wibuplay!'
        : 'Nonton "$t" di Wibuplay!';
    await PipController.setCanEnter(false);
    try {
      await Share.share(text);
    } finally {
      PipController.setCanEnter(_pb.value.isPlaying);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final slug = widget.slug;
    final videoAsync = ref.watch(donghuaVideoProvider(slug));
    final episodeAsync = ref.watch(donghuaEpisodeProvider(slug));
    final premium = ref.watch(myPremiumProvider).valueOrNull;

    final episodeDetail = episodeAsync.valueOrNull;
    final video = videoAsync.valueOrNull;

    // ---- Daftar kualitas (terendah -> tertinggi) ----
    final medias = (video?.medias ?? const <AnichinMedia>[])
        .where((m) => (m.url ?? '').trim().isNotEmpty && AnichinRepository.qualityRank(m.quality) >= 0)
        .toList()
      ..sort((a, b) => AnichinRepository.qualityRank(a.quality)
          .compareTo(AnichinRepository.qualityRank(b.quality)));

    // Kualitas terpilih: default = tertinggi yang boleh (non-premium max 480p).
    String? selectedQuality;
    if (premium != null && medias.isNotEmpty) {
      final chosen = medias.where((m) => m.quality == _selectedQuality).firstOrNull;
      selectedQuality = chosen?.quality ??
          AnichinRepository.pickMedia(
            medias,
            maxQuality: premium ? 'ultra' : AnichinRepository.nonPremiumMaxQuality,
          )?.quality;
    }
    final selectedMedia = medias.where((m) => m.quality == selectedQuality).firstOrNull;

    final videoReady = video != null && medias.isNotEmpty && premium != null;
    final url = selectedMedia?.url;
    if (videoReady && url != null && url != _loadedUrl && url != _pendingUrl) {
      _pendingUrl = url;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUrl(url));
    }

    // ---- Info episode ----
    // Daftar di situs sumber urut terbaru -> terlama, jadi BERIKUTNYA =
    // index - 1, SEBELUMNYA = index + 1.
    final episodes = episodeDetail?.episodes ?? const <AnichinEpisodeRef>[];
    final currentIdx = episodes.indexWhere((e) => e.slug == slug);
    final currentRef = currentIdx >= 0 ? episodes[currentIdx] : null;
    final prevSlug = currentIdx >= 0 && currentIdx + 1 < episodes.length
        ? episodes[currentIdx + 1].slug
        : null;
    final nextSlug = currentIdx > 0 ? episodes[currentIdx - 1].slug : null;

    final fullName = episodeDetail?.name ?? video?.title;
    final animeTitle = _animeTitleOf(fullName) ?? fullName;
    final epNumber = _episodeNumberOf(fullName, currentRef);

    final videoArea = _videoArea(
      videoAsync: videoAsync,
      videoReady: videoReady,
      medias: medias,
      selectedQuality: selectedQuality,
      premium: premium ?? false,
      title: '${animeTitle ?? 'Donghua'}${epNumber != null ? ' - Ep $epNumber' : ''}',
      prevSlug: prevSlug,
      nextSlug: nextSlug,
      episodes: episodes,
    );

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _setFullscreen(false);
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: ValueListenableBuilder<bool>(
          valueListenable: PipController.isInPip,
          builder: (context, inPip, _) {
            if (_fullscreen || inPip) {
              return ColoredBox(color: Colors.black, child: videoArea);
            }
            return SafeArea(
              bottom: false,
              child: Column(
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: videoArea),
                  Expanded(
                    child: _details(
                      animeTitle: animeTitle,
                      epNumber: epNumber,
                      currentRef: currentRef,
                      episodeDetail: episodeDetail,
                      episodes: episodes,
                      episodesLoading: episodeAsync.isLoading,
                      medias: medias,
                      selectedQuality: selectedQuality,
                      premium: premium,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------ area video

  Widget _videoArea({
    required AsyncValue<AnichinVideoSource> videoAsync,
    required bool videoReady,
    required List<AnichinMedia> medias,
    required String? selectedQuality,
    required bool premium,
    required String title,
    required String? prevSlug,
    required String? nextSlug,
    required List<AnichinEpisodeRef> episodes,
  }) {
    final err = videoAsync.error;
    final is404 = err is DioException && err.response?.statusCode == 404;

    Widget body;
    if (videoAsync.hasError && !videoAsync.isLoading) {
      body = is404
          // 404 dari API = episode ini tidak punya mirror OK.ru (bukan masalah koneksi)
          ? const _CenterMessage('Video episode ini belum tersedia di sumber. Coba episode lain.')
          : ErrorState(
              message: errorMessage(err!, 'Gagal mengambil link video.'),
              onRetry: () => ref.invalidate(donghuaVideoProvider(widget.slug)),
            );
    } else if (videoAsync.hasValue && medias.isEmpty) {
      body = const _CenterMessage('Video tidak tersedia untuk episode ini.');
    } else if (!videoReady) {
      body = const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet),
      );
    } else {
      body = _player(
        medias: medias,
        selectedQuality: selectedQuality,
        premium: premium,
        title: title,
        prevSlug: prevSlug,
        nextSlug: nextSlug,
        episodes: episodes,
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          // Tombol back kalau kontrol belum tampil (error / loading).
          if (!videoReady)
            Positioned(
              top: 6,
              left: 6,
              child: IconButton(
                onPressed: _fullscreen ? () => _setFullscreen(false) : widget.onBackClick,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.45),
                ),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
        ],
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

  Widget _player({
    required List<AnichinMedia> medias,
    required String? selectedQuality,
    required bool premium,
    required String title,
    required String? prevSlug,
    required String? nextSlug,
    required List<AnichinEpisodeRef> episodes,
  }) {
    final selectedServer = StreamServer(
      quality: selectedQuality == null ? null : AnichinRepository.qualityLabel(selectedQuality),
      name: selectedQuality,
    );

    return PlayerGestureLayer(
      levels: _levels,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _videoSurface(),
          ValueListenableBuilder<PlayerPlayback>(
            valueListenable: _pb,
            builder: (context, pb, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (!_inPip)
                    PlayerControlsOverlay(
                      pb: pb,
                      showControls: _showControls,
                      isFullscreen: _fullscreen,
                      title: title,
                      selectedServer: selectedServer,
                      speed: _speed,
                      showSkipIntro: false,
                      onTogglePlay: _togglePlay,
                      onSeek: (ms) {
                        _seekMs(ms);
                        _scheduleHide();
                      },
                      onToggleFullscreen: () => _setFullscreen(!_fullscreen),
                      onOpenServers: () => _openQualitySheet(medias, selectedQuality, premium),
                      onOpenSettings: _openSpeedSheet,
                      onEnterPip: _enterPip,
                      onOpenEpisodes: _fullscreen
                          ? () => setState(() {
                                _showEpisodeList = true;
                                _showControls = false;
                              })
                          : null,
                      onRewind: () => _seekBy(-10000),
                      onForward: () => _seekBy(10000),
                      onPrev: prevSlug == null ? null : () => widget.onEpisodeChange(prevSlug),
                      onNext: nextSlug == null ? null : () => widget.onEpisodeChange(nextSlug),
                      onSkipIntro: () {},
                      onDoubleTapLeft: () => _doubleTapSeek(forward: false),
                      onDoubleTapRight: () => _doubleTapSeek(forward: true),
                      onToggleOverlay: _toggleOverlay,
                      onBack: _fullscreen ? () => _setFullscreen(false) : widget.onBackClick,
                    ),
                  // Spinner buffering tetap tampil walau kontrol disembunyikan.
                  if (pb.isBuffering && !_showControls && !_inPip)
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
          ),
          if (!_inPip) _seekFlash(),
          if (_playerError)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: const Text(
                'Video gagal diputar. Coba kualitas lain.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          if (_showEpisodeList)
            GestureDetector(
              // Serap swipe horizontal supaya tidak ikut menggeser video.
              onHorizontalDragUpdate: (_) {},
              child: _episodeSidebar(episodes),
            ),
        ],
      ),
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
                color: const Color(0x991E1B2E),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _flashForward ? Icons.forward_10 : Icons.replay_10,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _flashForward ? '+10 dtk' : '-10 dtk',
                    style: const TextStyle(
                      color: Colors.white,
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

  /// Panel daftar episode di fullscreen (kanan).
  Widget _episodeSidebar(List<AnichinEpisodeRef> episodes) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showEpisodeList = false),
          child: const ColoredBox(color: Color(0x66000000)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 300,
            color: AppColors.backgroundDarkSecondary.withValues(alpha: 0.96),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Daftar Episode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _showEpisodeList = false),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: episodes.length,
                      itemBuilder: (_, i) {
                        final ep = episodes[i];
                        final active = ep.slug == widget.slug;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (!active) widget.onEpisodeChange(ep.slug);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.accentViolet.withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 88,
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          const ColoredBox(color: AppColors.surfaceVariantDark),
                                          DonghuaImage(ep.thumbnail),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Episode ${_episodeNumberOf(ep.name, ep) ?? '-'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: active ? AppColors.accentViolet : Colors.white,
                                      fontSize: 13,
                                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
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
        ),
      ],
    );
  }

  // ------------------------------------------------- bagian bawah (portrait)

  Widget _details({
    required String? animeTitle,
    required String? epNumber,
    required AnichinEpisodeRef? currentRef,
    required AnichinEpisodeDetail? episodeDetail,
    required List<AnichinEpisodeRef> episodes,
    required bool episodesLoading,
    required List<AnichinMedia> medias,
    required String? selectedQuality,
    required bool? premium,
  }) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final synopsis = episodeDetail?.sinopsis ?? '';
    final posterPath = episodeDetail?.thumbnail;
    final epSubtitle = currentRef?.subtitle;
    final epDate = currentRef?.date;

    return CustomScrollView(
      slivers: [
        // 1. Poster kecil + judul + info episode
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: AppColors.surfaceVariantDark),
                          if ((posterPath ?? '').isNotEmpty) DonghuaImage(posterPath),
                        ],
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
                        animeTitle ?? 'Memuat...',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Episode ${epNumber ?? '-'}'
                        '${(epSubtitle ?? '').isNotEmpty ? ' • $epSubtitle' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                      if ((epDate ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          epDate!,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                      if (_playerError) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Video gagal diputar. Coba kualitas lain.',
                          style: TextStyle(color: AppColors.accentViolet, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Sinopsis (expandable)
        if (synopsis.trim().isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    synopsis,
                    maxLines: _synopsisExpanded ? null : 2,
                    overflow: _synopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 20 / 14,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
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

        // 3. Banner Trakteer
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: PlayerTrakteerButton(onTap: _openTrakteer),
          ),
        ),

        // 4. Tombol aksi
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Row(
              children: [
                _ActionChip(
                  icon: Icons.high_quality,
                  label: 'Kualitas',
                  onTap: medias.isEmpty
                      ? () {}
                      : () => _openQualitySheet(medias, selectedQuality, premium ?? false),
                ),
                const SizedBox(width: 10),
                _ActionChip(
                  icon: Icons.download_for_offline,
                  label: 'Download',
                  onTap: () => premium == false
                      ? widget.onUpgradeClick()
                      : _toast('Download donghua segera hadir'),
                ),
                const SizedBox(width: 10),
                _ActionChip(
                  icon: Icons.chat_bubble_outline,
                  label: 'Komentar',
                  onTap: _scrollToComments,
                ),
                const SizedBox(width: 10),
                _ActionChip(
                  icon: Icons.flag_outlined,
                  label: 'Laporkan',
                  onTap: () => _toast('Fitur laporkan segera hadir'),
                ),
                const SizedBox(width: 10),
                _ActionChip(
                  icon: Icons.share_outlined,
                  label: 'Bagikan',
                  onTap: () => _share(animeTitle, epNumber),
                ),
              ],
            ),
          ),
        ),

        // 5. Header "Episode List"
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Episode List',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        // 6. Daftar episode horizontal bergambar
        SliverToBoxAdapter(
          child: episodes.isNotEmpty
              ? SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: episodes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final ep = episodes[i];
                      return _EpisodeThumbCard(
                        episode: ep,
                        isActive: ep.slug == widget.slug,
                        onTap: () {
                          if (ep.slug != widget.slug) widget.onEpisodeChange(ep.slug);
                        },
                      );
                    },
                  ),
                )
              : episodesLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: AppColors.accentViolet,
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Daftar episode belum tersedia',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ),
        ),

        // 7. Komentar episode (inline, di bawah Episode List). Id diberi
        // prefix "dh:" supaya tidak bentrok dengan id episode anime. Dibuat
        // setelah detail episode terbaca, supaya judul/poster yang ditempel
        // ke komentar sudah terisi.
        if (episodeDetail != null)
          CommentsSliver(
            key: ValueKey('comments-dh-${widget.slug}'),
            args: ('dh:${widget.slug}', 'dh:${episodeDetail.root ?? widget.slug}'),
            meta: CommentMeta(
              animeTitle: animeTitle,
              animePosterUrl: AnichinNetwork.imageUrl(episodeDetail.thumbnail),
              episodeIndex: epNumber,
            ),
            headerKey: _commentsKey,
            onUpgradeClick: widget.onUpgradeClick,
          ),

        SliverToBoxAdapter(child: SizedBox(height: 28 + bottomInset)),
      ],
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.surfaceElevated),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeThumbCard extends StatelessWidget {
  const _EpisodeThumbCard({
    required this.episode,
    required this.isActive,
    required this.onTap,
  });

  final AnichinEpisodeRef episode;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = _episodeNumberOf(episode.name, episode) ?? '-';
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariantDark,
                  borderRadius: BorderRadius.circular(10),
                  border: isActive
                      ? Border.all(color: AppColors.accentViolet, width: 2)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isActive ? 8 : 10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if ((episode.thumbnail ?? '').isNotEmpty) DonghuaImage(episode.thumbnail),
                      if (isActive)
                        Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.play_circle_filled,
                            size: 24,
                            color: AppColors.accentViolet,
                          ),
                        ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                          ),
                          child: Text(
                            'EP $n',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
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
            const SizedBox(height: 4),
            Text(
              'Episode $n',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? AppColors.accentViolet : AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
