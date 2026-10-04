import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/cuplix_item.dart';
import '../../components/common_components.dart';
import '../../components/net_image.dart';
import '../../route_observer.dart';
import 'cuplix_controller.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Port CuplixScreen.kt: feed klip pendek vertikal (VerticalPager).
///
/// Di Kotlin composable ini dibuang saat tab lain dibuka atau layar Detail/Player
/// dipush, sehingga ExoPlayer ikut dilepas. Di Flutter tab tetap hidup
/// (IndexedStack), jadi pemutaran dihentikan lewat tiga sinyal: [isTabActive],
/// route lain menutupi layar ini (RouteAware), dan aplikasi masuk background.
class CuplixScreen extends ConsumerStatefulWidget {
  const CuplixScreen({
    super.key,
    required this.isTabActive,
    required this.onWatchAnime,
  });

  /// true kalau tab Cuplix sedang tampil di AppShell.
  final bool isTabActive;
  final void Function(String movieId, String episodeId) onWatchAnime;

  @override
  ConsumerState<CuplixScreen> createState() => _CuplixScreenState();
}

class _CuplixScreenState extends ConsumerState<CuplixScreen>
    with WidgetsBindingObserver, RouteAware {
  late final PageController _pageController;
  ModalRoute<Object?>? _route;
  bool _routeVisible = true;
  bool _appForeground = true;

  /// Setara LaunchedEffect(currentPage) yang jalan sekali saat pager pertama tampil.
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController =
        PageController(initialPage: ref.read(cuplixControllerProvider).currentIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) routeObserver.unsubscribe(this);
      _route = route;
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _pageController.dispose();
    super.dispose();
  }

  // Route lain (Detail/Player) di atas layar ini.
  @override
  void didPushNext() {
    if (mounted) setState(() => _routeVisible = false);
  }

  @override
  void didPopNext() {
    if (mounted) setState(() => _routeVisible = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = !(state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached);
    if (foreground != _appForeground && mounted) {
      setState(() => _appForeground = foreground);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(cuplixControllerProvider);
    final notifier = ref.read(cuplixControllerProvider.notifier);
    final screenActive = widget.isTabActive && _routeVisible && _appForeground;

    final Widget content;
    if (ui.isLoading) {
      _announced = false;
      content = const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet),
      );
    } else if (ui.error != null) {
      _announced = false;
      content = Center(
        child: ErrorState(
          message: ui.error!,
          onRetry: () => notifier.loadFeed(isInitial: true),
        ),
      );
    } else if (ui.items.isEmpty) {
      _announced = false;
      content = const Center(
        child: EmptyState(
          title: 'Cuplix Belum Tersedia',
          subtitle: 'Tarik ke bawah atau coba kembali beberapa saat lagi',
          icon: Icons.video_library_outlined,
        ),
      );
    } else {
      if (!_announced) {
        _announced = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          notifier.onPageChanged(ref.read(cuplixControllerProvider).currentIndex);
        });
      }
      content = PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: ui.items.length,
        onPageChanged: notifier.onPageChanged,
        itemBuilder: (context, index) {
          final item = ui.items[index];
          return CuplixVideoItem(
            key: ValueKey(item.id),
            item: item,
            isActive: screenActive && ui.currentIndex == index,
            isLiked: ui.likedIds.contains(item.id),
            onToggleLike: () => notifier.toggleLike(item.id),
            onWatchFull: () {
              final movieId = item.idMovie ?? '';
              final episodeId = item.idEpisode ?? '';
              if (movieId.isNotEmpty && episodeId.isNotEmpty) {
                widget.onWatchAnime(movieId, episodeId);
              }
            },
            resolveStreamUrl: notifier.resolveStreamUrl,
            onStreamFailed: notifier.invalidateStreamCache,
          );
        },
      );
    }

    return ColoredBox(
      color: AppColors.backgroundDark,
      child: SizedBox.expand(child: content),
    );
  }
}

/// Port CuplixVideoPlayerItem. Pemutar hanya hidup selama [isActive] true
/// (DisposableEffect(isActive, item.id) di Kotlin).
class CuplixVideoItem extends StatefulWidget {
  const CuplixVideoItem({
    super.key,
    required this.item,
    required this.isActive,
    required this.isLiked,
    required this.onToggleLike,
    required this.onWatchFull,
    required this.resolveStreamUrl,
    required this.onStreamFailed,
  });

  final CuplixItem item;
  final bool isActive;
  final bool isLiked;
  final VoidCallback onToggleLike;
  final VoidCallback onWatchFull;
  final Future<String?> Function(String episodeId) resolveStreamUrl;
  final ValueChanged<String> onStreamFailed;

  @override
  State<CuplixVideoItem> createState() => _CuplixVideoItemState();
}

class _CuplixVideoItemState extends State<CuplixVideoItem> {
  VideoPlayerController? _vc;

  /// Naik setiap start/stop; pekerjaan async dari sesi lama dibuang.
  int _session = 0;
  Timer? _boundaryTimer;
  bool _polling = false;
  bool _restarting = false;
  bool _failed = false;

  bool _isPlaying = false;
  bool _isBuffering = true;
  bool _showPauseIcon = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) unawaited(_start());
  }

  @override
  void didUpdateWidget(CuplixVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive || oldWidget.item.id != widget.item.id) {
      _stop();
      if (widget.isActive) unawaited(_start());
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- pemutar

  Future<void> _start() async {
    final session = ++_session;
    _isBuffering = true;
    _showPauseIcon = false;
    _failed = false;

    final item = widget.item;
    final epId = item.idEpisode;
    if (epId == null || epId.trim().isEmpty) {
      _isBuffering = false;
      return;
    }

    final url = await widget.resolveStreamUrl(epId);
    if (!mounted || session != _session) return;
    if (url == null) {
      // Tidak ada link: tetap tampil thumbnail (sama seperti Kotlin).
      setState(() => _isBuffering = false);
      return;
    }

    final VideoPlayerController vc;
    try {
      vc = VideoPlayerController.networkUrl(Uri.parse(url));
    } catch (_) {
      setState(() => _isBuffering = false);
      return;
    }
    _vc = vc;

    try {
      await vc.initialize();
      if (!mounted || session != _session) return;
      final startMs = item.timeStartMs;
      if (startMs > 0) await vc.seekTo(Duration(milliseconds: startMs));
      if (!mounted || session != _session) return;
      vc.addListener(_onVideo);
      await vc.play();
      if (!mounted || session != _session) return;
      _startBoundaryWatch(vc, item);
      _onVideo();
      setState(() {});
    } catch (_) {
      if (mounted && session == _session) {
        // Sama seperti onPlayerError di Kotlin: buang cache URL, tanpa retry otomatis.
        widget.onStreamFailed(epId);
        if (_vc == vc) {
          _vc = null;
          vc.removeListener(_onVideo);
          unawaited(vc.dispose());
        }
        setState(() => _isBuffering = false);
      }
    }
  }

  /// Hentikan dan lepas pemutar. Tidak memanggil setState (aman dipakai di
  /// didUpdateWidget/dispose); build berikutnya membaca nilai terbaru.
  void _stop() {
    _session++;
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    final vc = _vc;
    _vc = null;
    if (vc != null) {
      vc.removeListener(_onVideo);
      unawaited(vc.dispose());
    }
    _isPlaying = false;
    _showPauseIcon = false;
    _restarting = false;
    _polling = false;
  }

  /// Port coroutine pemantau time_end: tiap 150 ms, kalau posisi >= time_end
  /// lompat ke time_start dan putar lagi. Posisi dibaca langsung dari platform
  /// karena value.position di video_player hanya diperbarui tiap ~500 ms.
  void _startBoundaryWatch(VideoPlayerController vc, CuplixItem item) {
    final startMs = item.timeStartMs;
    final endMs = item.timeEndMs;
    if (endMs <= startMs) return;
    _boundaryTimer?.cancel();
    _boundaryTimer = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      if (_vc != vc || _restarting || _polling) return;
      _polling = true;
      try {
        final pos = await vc.position;
        if (_vc != vc || _restarting || pos == null) return;
        if (pos.inMilliseconds >= endMs) {
          await _loopToStart(vc, startMs);
        }
      } catch (_) {
        // pemutar sudah dilepas
      } finally {
        _polling = false;
      }
    });
  }

  Future<void> _loopToStart(VideoPlayerController vc, int startMs) async {
    if (_restarting) return;
    _restarting = true;
    try {
      await vc.seekTo(Duration(milliseconds: startMs));
      if (_vc == vc) await vc.play();
    } catch (_) {
      // pemutar sudah dilepas
    } finally {
      if (_vc == vc) _restarting = false;
    }
  }

  void _onVideo() {
    final vc = _vc;
    if (vc == null || !mounted) return;
    final v = vc.value;
    final buffering = v.hasError ? false : v.isBuffering;

    if (v.hasError && !_failed) {
      _failed = true;
      final epId = widget.item.idEpisode;
      if (epId != null) widget.onStreamFailed(epId);
    }

    // Klip selesai (STATE_ENDED di Kotlin): ulang dari time_start.
    if (v.isInitialized && v.isCompleted && !_restarting) {
      unawaited(_loopToStart(vc, widget.item.timeStartMs));
    }

    if (v.isPlaying != _isPlaying || buffering != _isBuffering) {
      setState(() {
        _isPlaying = v.isPlaying;
        _isBuffering = buffering;
      });
    }
  }

  void _onTapScreen() {
    final vc = _vc;
    if (vc == null || !vc.value.isInitialized) return;
    if (vc.value.isPlaying) {
      unawaited(vc.pause());
      setState(() => _showPauseIcon = true);
    } else {
      unawaited(vc.play());
      setState(() => _showPauseIcon = false);
    }
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final vc = _vc;
    final showVideo = widget.isActive && vc != null && vc.value.isInitialized;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTapScreen,
      child: ColoredBox(
        color: AppColors.backgroundDark,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail sebagai placeholder
            Positioned.fill(child: NetImage(item.thumbnailUrl)),

            // Video (fit, seperti PlayerView RESIZE_MODE_FIT)
            if (showVideo)
              Positioned.fill(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: vc.value.aspectRatio,
                    child: VideoPlayer(vc),
                  ),
                ),
              ),

            // Gradien atas dan bawah supaya teks terbaca
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x991E1B2E), Colors.transparent],
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 300,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xDD1E1B2E), Color(0xFF1E1B2E)],
                  ),
                ),
              ),
            ),

            // Indikator buffering
            if (_isBuffering && widget.isActive)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        color: AppColors.accentViolet,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              ),

            // Ikon play saat dijeda
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: (_showPauseIcon && !_isPlaying) ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0x66000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: AppColors.textWhite,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Info kiri bawah: username, judul anime, episode, caption
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.78,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 95),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_blank(item.username)) ...[
                          Text(
                            '@${item.username}',
                            style: const TextStyle(
                              color: AppColors.accentViolet,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          item.anime ?? 'Anime',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!_blank(item.episode))
                          Text(
                            'Episode ${item.episode}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (!_blank(item.caption)) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.caption!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textWhite.withValues(alpha: 0.9),
                              fontSize: 12,
                              height: 16 / 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bar aksi kanan: suka, komentar, bagikan, tonton penuh
            Positioned(
              right: 16,
              bottom: bottomInset + 95,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionButton(
                    onTap: widget.onToggleLike,
                    label: item.countLikes ?? '0',
                    child: Icon(
                      widget.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: widget.isLiked ? AppColors.errorRed : AppColors.textWhite,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Komentar: di Kotlin hanya tampilan jumlah, belum ada aksi.
                  _ActionButton(
                    label: item.countComments ?? '0',
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.textWhite,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ActionButton(
                    onTap: () {
                      Share.share(
                        'Tonton klip anime ${item.anime ?? ''} di Wibuplay!',
                        subject: item.anime ?? 'Wibuplay',
                      );
                    },
                    label: 'Bagi',
                    child: const Icon(
                      Icons.share_outlined,
                      color: AppColors.textWhite,
                      size: 22,
                    ),
                  ),
                  if (!_blank(item.idMovie)) ...[
                    const SizedBox(height: 16),
                    _ActionButton(
                      onTap: widget.onWatchFull,
                      background: AppColors.accentViolet,
                      child: const Icon(
                        Icons.movie_outlined,
                        color: AppColors.textWhite,
                        size: 24,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tombol bulat 46dp dengan label kecil opsional di bawahnya.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.child,
    this.onTap,
    this.label,
    this.background,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background ?? AppColors.surfaceDark.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
            child: child,
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label!,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
