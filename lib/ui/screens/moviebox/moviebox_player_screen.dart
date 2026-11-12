import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wibuplay/core/review_prompter.dart';
import 'package:wibuplay/core/wp_video.dart';

import '../../../core/error_message.dart';
import '../../../core/pip_controller.dart';
import '../../../core/premium_access.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/watch_xp_gate.dart';
import '../../../data/local/entities.dart' show DownloadedEpisodeEntity;
import '../../../data/models/comment_models.dart';
import '../../../data/models/moviebox_models.dart';
import '../../../data/models/stream_data.dart';
import '../../../data/repository/anime_repository.dart';
import '../../../data/repository/moviebox_repository.dart';
import '../../../providers.dart';
import '../../components/common_components.dart';
import '../../glass/glass.dart';
import '../comments/comments_section.dart';
import '../download/download_actions.dart'
    show confirmDeleteDownload, downloadStateHighlight, downloadStateIcon, downloadStateLabel;
import '../player/danmaku.dart';
import '../player/player_gestures.dart';
import '../player/player_screen.dart';
import '../player/quality_sheet.dart';
import 'moviebox_subtitle.dart';
import 'moviebox_widgets.dart';

/// Detail film (judul, sinopsis, dub). Cache 10 menit lewat keepAlive.
final mbDetailProvider = FutureProvider.autoDispose.family<MbDetail, String>(
  (ref, id) => ref.watch(movieBoxRepositoryProvider).getDetail(id),
);

/// Link video. Diambil FRESH tiap layar dibuka (link CDN ada masa berlakunya).
/// Jalan PARALEL dengan detail; server mencari detail_path sendiri.
final mbStreamsProvider = FutureProvider.autoDispose.family<List<MbStream>, String>(
  (ref, id) => ref.watch(movieBoxRepositoryProvider).getStreams(id),
);

final mbCaptionsProvider = FutureProvider.autoDispose.family<List<MbCaption>, String>(
  (ref, id) => ref.watch(movieBoxRepositoryProvider).getCaptions(id),
);

/// Prefix id riwayat & download film (`moviebox:<id>`) supaya tidak bentrok
/// dengan episode anime / donghua.
const String kMovieBoxPrefix = 'moviebox:';

/// Player film MovieBox. Tampilan & fitur disamakan dengan player anime /
/// donghua: kontrol custom, gestur kecerahan/volume, double-tap +-10 detik,
/// kunci layar, PiP, danmaku, kecepatan, kualitas (kunci > 480p non-premium),
/// download (Premium), riwayat tontonan, XP nonton, komentar. Tambahan:
/// subtitle (SRT dari MovieBox) yang digambar sendiri di atas video.
class MovieBoxPlayerScreen extends ConsumerStatefulWidget {
  const MovieBoxPlayerScreen({
    super.key,
    required this.movieId,
    required this.onBackClick,
    required this.onMovieChange,
    required this.onUpgradeClick,
  });

  final String movieId;
  final VoidCallback onBackClick;

  /// Ganti ke film lain (mis. versi dub). Mengganti layar, tidak menumpuk.
  final ValueChanged<String> onMovieChange;
  final VoidCallback onUpgradeClick;

  @override
  ConsumerState<MovieBoxPlayerScreen> createState() => _MovieBoxPlayerScreenState();
}

class _MovieBoxPlayerScreenState extends ConsumerState<MovieBoxPlayerScreen> with WidgetsBindingObserver {
  /// false saat app di background: detik itu tidak dihitung untuk XP.
  bool _inForeground = true;

  /// Danmaku. Kunci memakai prefix donghua `d:` + `mb-<id>` karena server
  /// danmaku hanya menerima kunci `a:` / `d:`.
  late final DanmakuController _dm = DanmakuController(ref.read(supabaseDioProvider));

  WpVideoController? _vc;
  String? _loadedUrl;
  bool _finishCounted = false;

  /// Mode pemutar (lihat WpDecoder): naik otomatis kalau ExoPlayer gagal
  /// (mis. HP tanpa decoder HEVC).
  int _decoderLevel = WpDecoder.savedLevel;
  int _decoderRetries = 0;
  String? _pendingUrl;
  final ValueNotifier<PlayerPlayback> _pb = ValueNotifier<PlayerPlayback>(const PlayerPlayback());

  bool _showControls = true;
  bool _fullscreen = false;
  bool _screenLocked = false;
  bool _lockButtonVisible = false;
  Timer? _lockHideTimer;
  bool _playerError = false;
  bool _wasPlaying = false;
  Timer? _hideTimer;
  Timer? _tick;
  Timer? _flashTimer;

  final PlayerLevels _levels = PlayerLevels();
  double _speed = 1.0;
  bool _flashVisible = false;
  bool _flashForward = true;

  /// URL kualitas pilihan user. null = otomatis.
  String? _selectedUrl;

  /// true = putar file hasil download kalau ada.
  bool _preferOffline = true;
  bool _synopsisExpanded = false;

  // ---- Subtitle ----
  /// URL subtitle yang dipilih user. null = otomatis (Indonesia kalau ada).
  String? _captionUrl;
  bool _subtitleOff = false;
  String? _cuesUrl;
  List<SubtitleCue> _cues = const [];
  bool _cuesLoading = false;

  /// Subtitle yang gagal dimuat: tidak dicoba ulang otomatis (hindari loop).
  final Set<String> _cuesFailed = {};

  String get _dlKey => '$kMovieBoxPrefix${widget.movieId}';

  // ---- Riwayat tontonan ----
  late final AnimeRepository _repo;
  int _tickCount = 0;
  String _histTitle = 'Film';
  String _histPoster = '';
  bool _histReady = false;
  final GlobalKey _commentsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _repo = ref.read(repositoryProvider);
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
    ReviewPrompter.onPlayerClosed();
    _dm.dispose();
    _saveHistory();
    WidgetsBinding.instance.removeObserver(this);
    WatchXpGate.release(this);
    _hideTimer?.cancel();
    _lockHideTimer?.cancel();
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

  /// Putar [url]. Posisi terakhir dipertahankan kalau cuma ganti kualitas.
  Future<void> _loadUrl(String url, Map<String, String> headers) async {
    if (!mounted || url == _loadedUrl) return;
    _loadedUrl = url;
    _finishCounted = false;
    _pendingUrl = null;

    final old = _vc;
    // Ganti kualitas: lanjut dari posisi sekarang. Pertama kali dibuka:
    // lanjut dari riwayat tontonan film ini.
    final resumeMs =
        old?.value.position.inMilliseconds ?? (_repo.historyForEpisode(_dlKey)?.playbackPositionMs ?? 0);
    old?.removeListener(_onVideo);

    final WpVideoController vc;
    try {
      vc = url.startsWith('file://')
          ? WpVideoController.file(File.fromUri(Uri.parse(url)), decoderLevel: _decoderLevel)
          : WpVideoController.networkUrl(Uri.parse(url), httpHeaders: headers, decoderLevel: _decoderLevel);
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
      final total = vc.value.duration.inMilliseconds;
      // Hampir selesai (sisa < 60 dtk, bagian kredit) -> mulai dari awal lagi.
      if (resumeMs > 0 && (total <= 0 || resumeMs < total - 60000)) {
        await vc.seekTo(Duration(milliseconds: resumeMs));
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
    } catch (e) {
      if (mounted && _vc == vc) {
        // Format/decoder tidak didukung mode ini (HEVC di HP tertentu): coba
        // mode berikutnya, akhirnya media_kit software.
        final desc = vc.value.errorDescription ?? '$e';
        if (desc.toLowerCase().contains('decoder') &&
            _decoderRetries < WpDecoder.maxLevel &&
            _decoderLevel < WpDecoder.maxLevel) {
          _decoderRetries++;
          _decoderLevel++;
          _vc = null;
          _loadedUrl = null;
          vc.removeListener(_onVideo);
          try {
            await vc.dispose();
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (mounted) await _loadUrl(url, headers);
          return;
        }
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

    if (!_finishCounted && snap.durationMs > 60000 && snap.positionMs >= snap.durationMs * 0.9) {
      _finishCounted = true;
      unawaited(ReviewPrompter.onEpisodeFinished());
    }

    if (snap.isPlaying != _wasPlaying) {
      _wasPlaying = snap.isPlaying;
      WakelockPlus.toggle(enable: snap.isPlaying);
      PipController.setCanEnter(snap.isPlaying);
      _scheduleHide();
    }
  }

  void _onTick(Timer t) {
    if (!mounted) return;
    final vc = _vc;
    if (vc == null || !vc.value.isPlaying) return;
    _tickCount++;
    if (_tickCount % 5 == 0) _saveHistory();
    // XP nonton: hanya detik aktif (playing, tidak buffering, app di depan / PiP).
    if ((_inForeground || _inPip) && !vc.value.isBuffering && WatchXpGate.onActiveSecond(this)) {
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

  // ---------------------------------------------------------------- subtitle

  /// Subtitle aktif: pilihan user, kalau belum memilih -> Indonesia, kalau
  /// tidak ada -> yang pertama.
  MbCaption? _activeCaption(List<MbCaption> caps) {
    if (_subtitleOff || caps.isEmpty) return null;
    final picked = caps.where((c) => c.url == _captionUrl).firstOrNull;
    return picked ?? caps.where((c) => c.isIndonesian).firstOrNull ?? caps.first;
  }

  Future<void> _loadCues(String url) async {
    if (_cuesUrl == url) return;
    _cuesUrl = url;
    setState(() {
      _cuesLoading = true;
      _cues = const [];
    });
    try {
      final raw = await ref.read(movieBoxRepositoryProvider).fetchSubtitle(url);
      final cues = parseSubtitles(raw);
      if (!mounted || _cuesUrl != url) return;
      setState(() {
        _cues = cues;
        _cuesLoading = false;
      });
      if (cues.isEmpty) _toast('Subtitle ini kosong / formatnya tidak dikenal');
    } catch (_) {
      if (!mounted || _cuesUrl != url) return;
      _cuesFailed.add(url);
      setState(() => _cuesLoading = false);
      _toast('Gagal memuat subtitle. Coba pilih bahasa lain.');
    }
  }

  // ---------------------------------------------------------------- kontrol

  bool get _inPip => PipController.isInPip.value;

  void _onPip() {
    if (!mounted) return;
    setState(() {
      if (_inPip) _showControls = false;
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
    if (!ok && mounted) _toast('Picture-in-Picture tidak tersedia di perangkat ini');
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

  void _lockScreen() {
    _hideTimer?.cancel();
    setState(() {
      _screenLocked = true;
      _showControls = false;
      _lockButtonVisible = true;
    });
    _scheduleHideLockButton();
  }

  void _unlockScreen() {
    _lockHideTimer?.cancel();
    setState(() {
      _screenLocked = false;
      _lockButtonVisible = false;
      _showControls = true;
    });
    _scheduleHide();
  }

  void _scheduleHideLockButton() {
    _lockHideTimer?.cancel();
    _lockHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _lockButtonVisible = false);
    });
  }

  void _onLockedTap() {
    setState(() => _lockButtonVisible = true);
    _scheduleHideLockButton();
  }

  void _showLockedHint() {
    _onLockedTap();
    _toast('Layar terkunci. Ketuk ikon gembok untuk membuka.');
  }

  Widget _lockedPlayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _videoSurface(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onLockedTap,
          onHorizontalDragStart: (_) {},
          onVerticalDragStart: (_) {},
          onDoubleTap: () {},
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 24),
            child: AnimatedOpacity(
              opacity: _lockButtonVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_lockButtonVisible,
                child: GestureDetector(
                  onTap: _unlockScreen,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                    child: const Icon(Icons.lock, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _setFullscreen(bool fullscreen) {
    if (!fullscreen) {
      _screenLocked = false;
      _lockButtonVisible = false;
      _lockHideTimer?.cancel();
    }
    setState(() => _fullscreen = fullscreen);
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
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

  void _openDanmaku() {
    showDanmakuSheet(context, controller: _dm, positionMs: _vc?.value.position.inMilliseconds ?? 0);
  }

  /// Sheet pengaturan: kecepatan putar + subtitle.
  void _openSettingsSheet(List<MbCaption> caps) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final active = _activeCaption(caps);
    Widget pill(String text, bool selected, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.accentViolet.withValues(alpha: 0.2) : AppColors.surfaceVariantDark,
              borderRadius: BorderRadius.circular(100),
              border: selected ? Border.all(color: AppColors.accentViolet) : null,
            ),
            child: Text(
              text,
              style: TextStyle(
                color: selected ? AppColors.accentViolet : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
    const titleStyle = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700);

    showGlassSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kecepatan Putar', style: titleStyle),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in speeds)
                    pill(s == 1.0 ? 'Normal' : '${s}x', s == _speed, () {
                      _setSpeed(s);
                      Navigator.of(sheetContext).pop();
                    }),
                ],
              ),
              const SizedBox(height: 22),
              const Text('Subtitle', style: titleStyle),
              const SizedBox(height: 14),
              if (caps.isEmpty)
                const Text(
                  'Film ini tidak punya subtitle terpisah.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    pill('Mati', _subtitleOff, () {
                      setState(() => _subtitleOff = true);
                      Navigator.of(sheetContext).pop();
                    }),
                    for (final c in caps)
                      pill(c.language, !_subtitleOff && identical(c, active), () {
                        setState(() {
                          _subtitleOff = false;
                          _captionUrl = c.url;
                        });
                        Navigator.of(sheetContext).pop();
                      }),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Daftar kualitas untuk sheet. [name] = keterangan codec & ukuran.
  List<StreamServer> _servers(List<MbStream> streams) => [
        for (final s in streams)
          StreamServer(
            link: s.url,
            quality: s.quality,
            name: [
              s.isHevc ? 'HEVC' : 'H.264',
              if ((s.sizeMb ?? 0) > 0)
                s.sizeMb! >= 1024 ? '${(s.sizeMb! / 1024).toStringAsFixed(1)} GB' : '${s.sizeMb!.round()} MB',
            ].join(' • '),
          ),
      ];

  void _openQualitySheet(List<MbStream> streams, MbStream? selected, bool isPremium) {
    final servers = _servers(streams);
    StreamServer? current;
    for (final s in servers) {
      if (s.link == selected?.url) current = s;
    }
    showQualityPickerSheet(
      context,
      servers: servers,
      selected: current,
      isPremium: isPremium,
      onSelect: (s) => setState(() {
        _selectedUrl = s.link;
        _preferOffline = false;
      }),
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
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  Future<void> _share(String? title) async {
    await PipController.setCanEnter(false);
    try {
      await Share.share('Nonton film "${title ?? 'ini'}" di Zenime!');
    } finally {
      PipController.setCanEnter(_pb.value.isPlaying);
    }
  }

  /// Simpan posisi tonton ke riwayat. movieId `moviebox_<id>`, episodeId
  /// `moviebox:<id>` (dibuka lagi lewat openPlayer di app_routes).
  void _saveHistory() {
    final vc = _vc;
    if (vc == null || !_histReady || !vc.value.isInitialized || _playerError) return;
    if (vc.isSeekPending) return;
    final dur = vc.value.duration.inMilliseconds;
    if (dur <= 0) return;
    unawaited(_repo.saveWatchProgress(
      movieId: 'moviebox_${widget.movieId}',
      movieTitle: _histTitle,
      moviePoster: _histPoster,
      episodeId: _dlKey,
      episodeIndex: '1',
      episodeTitle: 'Film',
      playbackPositionMs: vc.value.position.inMilliseconds,
      durationMs: dur,
    ));
  }

  // --------------------------------------------------------------- download

  Future<void> _onDownloadTap({
    required List<MbStream> streams,
    required bool? premium,
    required String? title,
    required String? poster,
  }) async {
    final manager = ref.read(episodeDownloadManagerProvider);
    final entry = ref.read(localStoreProvider).downloadFor(_dlKey);

    if (entry != null && entry.isCompleted) {
      if (await confirmDeleteDownload(context, label: title) && mounted) {
        await manager.deleteDownload(_dlKey);
        if (mounted) setState(() => _preferOffline = false);
      }
      return;
    }
    if (entry != null && entry.isActive) {
      _toast('Film ini sedang didownload');
      return;
    }
    if (premium != true) {
      widget.onUpgradeClick();
      return;
    }
    if (streams.isEmpty) {
      _toast('Link video belum siap, coba lagi sebentar');
      return;
    }

    final picked = await _pickDownloadQuality(streams);
    if (picked == null || !mounted) return;

    final err = await manager.startDownload(
      episodeId: _dlKey,
      animeId: 'moviebox_${widget.movieId}',
      animeTitle: title ?? 'Film',
      posterUrl: poster,
      episodeTitle: 'Film',
      episodeIndex: '1',
      quality: picked.quality,
      videoUrl: picked.url,
      headers: picked.headers,
    );
    if (mounted) _toast(err ?? 'Download dimulai');
  }

  Future<MbStream?> _pickDownloadQuality(List<MbStream> streams) {
    final options = [...streams]..sort((a, b) => b.qualityValue.compareTo(a.qualityValue));
    return showGlassSheet<MbStream>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih Kualitas Download',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'File disimpan di perangkat dan bisa ditonton offline.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              for (final s in _servers(options))
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(sheetContext).pop(options.firstWhere((o) => o.url == s.link)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.download_for_offline, size: 20, color: AppColors.accentViolet),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s.quality ?? 'Auto',
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                        Text(s.name ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final id = widget.movieId;
    _dm.setKey('d:mb-$id');
    final detailAsync = ref.watch(mbDetailProvider(id));
    final streamsAsync = ref.watch(mbStreamsProvider(id));
    final caps = ref.watch(mbCaptionsProvider(id)).valueOrNull ?? const <MbCaption>[];
    final premiumAsync = ref.watch(myPremiumProvider);
    // Cek status gagal = dianggap non-premium (bukan loading selamanya).
    final bool? premium = premiumAsync.isLoading ? null : (premiumAsync.valueOrNull ?? false);

    final detail = detailAsync.valueOrNull;
    final streams = streamsAsync.valueOrNull ?? const <MbStream>[];

    // ---- Kualitas terpilih: pilihan user, kalau belum -> urutan server
    // (h264 dulu) yang tidak terkunci untuk user ini.
    MbStream? selected;
    if (premium != null && streams.isNotEmpty) {
      selected = streams.where((s) => s.url == _selectedUrl).firstOrNull ??
          streams.where((s) => !isQualityLocked(s.quality, premium)).firstOrNull ??
          streams.first;
    }

    // ---- File hasil download ----
    final dlEntry = ref.watch(localStoreProvider.select((s) => s.downloadFor(_dlKey)));
    final offlineFile =
        (dlEntry?.isCompleted ?? false) ? ref.read(episodeDownloadManagerProvider).localFileFor(_dlKey) : null;
    final playOffline = offlineFile != null && _preferOffline;

    final videoReady = playOffline || selected != null;
    final url = (offlineFile != null && _preferOffline) ? Uri.file(offlineFile.path).toString() : selected?.url;
    if (videoReady && url != null && url != _loadedUrl && url != _pendingUrl) {
      _pendingUrl = url;
      final headers = playOffline ? const <String, String>{} : selected!.headers;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUrl(url, headers));
    }

    // ---- Subtitle aktif ----
    final caption = _activeCaption(caps);
    if (caption != null && caption.url != _cuesUrl && !_cuesFailed.contains(caption.url)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCues(caption.url);
      });
    }

    final title = detail?.title ?? dlEntry?.animeTitle;
    _histTitle = title ?? 'Film';
    _histPoster = detail?.cover ?? dlEntry?.posterUrl ?? '';
    _histReady = detail != null || dlEntry != null;

    final videoArea = _videoArea(
      streamsAsync: streamsAsync,
      videoReady: videoReady,
      offline: playOffline,
      streams: streams,
      selected: playOffline ? null : selected,
      premium: premium ?? false,
      caps: caps,
      showSubtitle: caption != null,
      title: title ?? 'Film',
    );

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_screenLocked) {
          _showLockedHint();
          return;
        }
        if (_fullscreen) _setFullscreen(false);
      },
      child: GlassScaffold(
        backgroundColor: AppColors.backgroundDark,
        body: ValueListenableBuilder<bool>(
          valueListenable: PipController.isInPip,
          builder: (context, inPip, _) {
            if (_fullscreen || inPip) return ColoredBox(color: Colors.black, child: videoArea);
            return SafeArea(
              bottom: false,
              child: Column(
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: videoArea),
                  Expanded(
                    child: _details(
                      detail: detail,
                      detailAsync: detailAsync,
                      title: title,
                      streams: streams,
                      selected: selected,
                      premium: premium,
                      caps: caps,
                      caption: caption,
                      download: dlEntry,
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
    required AsyncValue<List<MbStream>> streamsAsync,
    required bool videoReady,
    required bool offline,
    required List<MbStream> streams,
    required MbStream? selected,
    required bool premium,
    required List<MbCaption> caps,
    required bool showSubtitle,
    required String title,
  }) {
    final err = streamsAsync.error;
    final is404 = err is DioException && err.response?.statusCode == 404;

    Widget body;
    if (offline) {
      body = _player(streams: streams, selected: null, premium: premium, caps: caps, showSubtitle: showSubtitle, title: title);
    } else if (streamsAsync.hasError && !streamsAsync.isLoading) {
      body = is404
          ? const MbCenterMessage('Video film ini belum tersedia di sumber.')
          : ErrorState(
              message: errorMessage(err!, 'Gagal mengambil link video.'),
              onRetry: () => ref.invalidate(mbStreamsProvider(widget.movieId)),
            );
    } else if (streamsAsync.hasValue && streams.isEmpty) {
      body = const MbCenterMessage('Video film ini belum tersedia. Coba lagi nanti atau pilih versi dub lain.');
    } else if (!videoReady) {
      body = const Center(child: CircularProgressIndicator(color: AppColors.accentViolet));
    } else {
      body = _player(streams: streams, selected: selected, premium: premium, caps: caps, showSubtitle: showSubtitle, title: title);
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (!videoReady)
            Positioned(
              top: 6,
              left: 6,
              child: IconButton(
                onPressed: _fullscreen ? () => _setFullscreen(false) : widget.onBackClick,
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.45)),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _videoSurface() {
    final vc = _vc;
    if (vc == null || !vc.value.isInitialized) return const ColoredBox(color: Colors.black);
    final ratio = vc.value.aspectRatio;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: ratio > 0 ? ratio : 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              WpVideoView(vc),
              if (!_inPip) DanmakuLayer(controller: _dm, video: vc, speed: _speed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _player({
    required List<MbStream> streams,
    required MbStream? selected,
    required bool premium,
    required List<MbCaption> caps,
    required bool showSubtitle,
    required String title,
  }) {
    final selectedServer = StreamServer(quality: selected?.quality, name: selected?.quality);
    final vc = _vc;

    if (_screenLocked && _fullscreen) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _lockedPlayer(),
          if (vc != null && showSubtitle) SubtitleLayer(video: vc, cues: _cues, large: true),
        ],
      );
    }

    return PlayerGestureLayer(
      levels: _levels,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _videoSurface(),
          // Subtitle di bawah kontrol supaya tombol tetap bisa diketuk.
          if (vc != null && showSubtitle)
            SubtitleLayer(video: vc, cues: _cues, large: _fullscreen || _inPip, raised: _showControls && !_inPip),
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
                      onOpenServers: () => _openQualitySheet(streams, selected, premium),
                      onOpenSettings: () => _openSettingsSheet(caps),
                      onEnterPip: _enterPip,
                      onDanmaku: _openDanmaku,
                      onLock: _fullscreen ? _lockScreen : null,
                      onOpenEpisodes: null,
                      onRewind: () => _seekBy(-10000),
                      onForward: () => _seekBy(10000),
                      onPrev: null,
                      onNext: null,
                      onSkipIntro: () {},
                      onDoubleTapLeft: () => _doubleTapSeek(forward: false),
                      onDoubleTapRight: () => _doubleTapSeek(forward: true),
                      onToggleOverlay: _toggleOverlay,
                      onBack: _fullscreen ? () => _setFullscreen(false) : widget.onBackClick,
                    ),
                  if (pb.isBuffering && !_showControls && !_inPip)
                    const IgnorePointer(
                      child: Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
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
        ],
      ),
    );
  }

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
              decoration: BoxDecoration(color: const Color(0x990B0E14), borderRadius: BorderRadius.circular(100)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_flashForward ? Icons.forward_10 : Icons.replay_10, color: Colors.white, size: 24),
                  const SizedBox(width: 6),
                  Text(
                    _flashForward ? '+10 dtk' : '-10 dtk',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------- bagian bawah (portrait)

  Widget _details({
    required MbDetail? detail,
    required AsyncValue<MbDetail> detailAsync,
    required String? title,
    required List<MbStream> streams,
    required MbStream? selected,
    required bool? premium,
    required List<MbCaption> caps,
    required MbCaption? caption,
    required DownloadedEpisodeEntity? download,
  }) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final synopsis = detail?.description ?? '';
    final poster = detail?.cover ?? download?.posterUrl;
    final dubs = detail?.dubs ?? const <MbDub>[];
    final meta = <String>[
      if (detail?.rating != null) '★ ${detail!.rating}',
      if (detail?.year != null) detail!.year!,
      if (detail?.duration != null) detail!.duration!,
      if (detail?.country != null) detail!.country!,
    ];

    return CustomScrollView(
      slivers: [
        // 1. Poster kecil + judul + info
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
                          if ((poster ?? '').isNotEmpty) MovieBoxImage(poster),
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
                        title ?? (detailAsync.hasError ? 'Film' : 'Memuat...'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          meta.join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                      if ((detail?.genre ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail!.genre!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.accentVioletLight, fontSize: 12),
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

        // 2. Sinopsis
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
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 20 / 14),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _synopsisExpanded ? 'Sembunyikan' : 'Selengkapnya',
                        style: const TextStyle(color: AppColors.accentViolet, fontSize: 12, fontWeight: FontWeight.w700),
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
                MbActionChip(
                  icon: Icons.high_quality,
                  label: selected?.quality ?? 'Kualitas',
                  onTap: streams.isEmpty ? () {} : () => _openQualitySheet(streams, selected, premium ?? false),
                ),
                const SizedBox(width: 10),
                MbActionChip(
                  icon: _subtitleOff || caps.isEmpty ? Icons.subtitles_off_outlined : Icons.subtitles_outlined,
                  label: caps.isEmpty
                      ? 'Tanpa Subtitle'
                      : (caption == null ? 'Subtitle: Mati' : (_cuesLoading ? 'Memuat...' : caption.language)),
                  highlight: caption != null,
                  onTap: () => _openSettingsSheet(caps),
                ),
                const SizedBox(width: 10),
                MbActionChip(
                  icon: downloadStateIcon(download),
                  label: downloadStateLabel(download),
                  highlight: downloadStateHighlight(download),
                  onTap: () => _onDownloadTap(streams: streams, premium: premium, title: title, poster: poster),
                ),
                const SizedBox(width: 10),
                MbActionChip(icon: Icons.chat_bubble_outline, label: 'Komentar', onTap: _scrollToComments),
                const SizedBox(width: 10),
                MbActionChip(icon: Icons.share_outlined, label: 'Bagikan', onTap: () => _share(title)),
              ],
            ),
          ),
        ),

        // 5. Pilihan audio / dub (mengganti layar ke film versi itu)
        if (dubs.length > 1)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    'Audio',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: dubs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final d = dubs[i];
                      final active = d.id == widget.movieId;
                      return MbActionChip(
                        icon: active ? Icons.check : Icons.translate,
                        label: d.name ?? 'Versi ${i + 1}',
                        highlight: active,
                        onTap: () {
                          if (!active) widget.onMovieChange(d.id);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

        // 6. Komentar. Id memakai prefix donghua `dh:` + `mb-<id>` (format
        // yang sudah diterima server komentar).
        if (detail != null)
          CommentsSliver(
            key: ValueKey('comments-mb-${widget.movieId}'),
            args: ('dh:mb-${widget.movieId}', 'dh:mb-${widget.movieId}'),
            meta: CommentMeta(animeTitle: title, animePosterUrl: detail.cover, episodeIndex: null),
            headerKey: _commentsKey,
            onUpgradeClick: widget.onUpgradeClick,
          ),

        SliverToBoxAdapter(child: SizedBox(height: 28 + bottomInset)),
      ],
    );
  }
}
