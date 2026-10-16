import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Pengganti VideoPlayerController berbasis media_kit (libmpv).
/// API dibuat sama dengan video_player supaya layar player tidak perlu
/// ditulis ulang. Keunggulan: kalau decoder hardware gagal (mis. Redmi 9C /
/// MediaTek), mpv otomatis jatuh ke software decode.
@immutable
class WpVideoValue {
  const WpVideoValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.size = Size.zero,
    this.errorDescription,
  });

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final Duration position;
  final Duration duration;
  final Size size;
  final String? errorDescription;

  bool get hasError => errorDescription != null;

  double get aspectRatio {
    if (size.width <= 0 || size.height <= 0) return 1.0;
    return size.width / size.height;
  }

  WpVideoValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    Duration? position,
    Duration? duration,
    Size? size,
    String? errorDescription,
  }) {
    return WpVideoValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      errorDescription: errorDescription ?? this.errorDescription,
    );
  }
}

class WpVideoController extends ChangeNotifier {
  WpVideoController.networkUrl(
    Uri uri, {
    Map<String, String>? httpHeaders,
  }) : _media = Media(uri.toString(), httpHeaders: httpHeaders) {
    _setup();
  }

  WpVideoController.file(File file) : _media = Media(file.path) {
    _setup();
  }

  final Media _media;
  late final Player _player;
  late final VideoController video;
  final List<StreamSubscription<dynamic>> _subs = [];
  WpVideoValue _value = const WpVideoValue();
  bool _disposed = false;
  Completer<void>? _ready;

  WpVideoValue get value => _value;

  void _setup() {
    _player = Player();
    video = VideoController(_player);
    final s = _player.stream;
    _subs.addAll([
      s.playing.listen((v) => _set(_value.copyWith(isPlaying: v))),
      s.buffering.listen((v) => _set(_value.copyWith(isBuffering: v))),
      s.completed.listen((v) => _set(_value.copyWith(isCompleted: v))),
      s.position.listen((v) => _set(_value.copyWith(position: v))),
      s.duration.listen((v) {
        _set(_value.copyWith(duration: v));
        _checkReady();
      }),
      s.width.listen((_) => _onSize()),
      s.height.listen((_) => _onSize()),
      s.error.listen(_onError),
    ]);
  }

  void _set(WpVideoValue v) {
    if (_disposed) return;
    _value = v;
    notifyListeners();
  }

  void _onSize() {
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    _set(_value.copyWith(size: Size(w.toDouble(), h.toDouble())));
    _checkReady();
  }

  void _checkReady() {
    if (_disposed || _value.isInitialized) return;
    final hasSize = (_player.state.width ?? 0) > 0;
    final hasDuration = _player.state.duration > Duration.zero;
    if (!hasSize && !hasDuration) return;
    _set(_value.copyWith(isInitialized: true));
    final r = _ready;
    if (r != null && !r.isCompleted) r.complete();
  }

  void _onError(String msg) {
    if (_disposed || msg.isEmpty) return;
    // Error sebelum siap = fatal. Setelah mulai main, error non-fatal mpv
    // (subtitle, log ffmpeg) diabaikan supaya tidak memunculkan overlay.
    if (_value.isInitialized) return;
    _set(_value.copyWith(errorDescription: msg));
    final r = _ready;
    if (r != null && !r.isCompleted) r.completeError(Exception(msg));
  }

  Future<void> initialize() async {
    final ready = Completer<void>();
    _ready = ready;
    await _player.open(_media, play: false);
    await ready.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Video tidak merespons (timeout 30 dtk)');
      },
    );
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> seekTo(Duration position) => _player.seek(position);

  Future<void> setPlaybackSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final r = _ready;
    if (r != null && !r.isCompleted) {
      r.completeError(Exception('disposed'));
    }
    try {
      await _player.dispose();
    } catch (_) {}
    super.dispose();
  }
}

/// Pengganti widget VideoPlayer(controller).
class WpVideoView extends StatelessWidget {
  const WpVideoView(this.controller, {super.key});

  final WpVideoController controller;

  @override
  Widget build(BuildContext context) {
    return Video(
      controller: controller.video,
      controls: NoVideoControls,
      fit: BoxFit.contain,
      fill: Colors.black,
      wakelock: false, // wakelock sudah diatur WakelockPlus di layar player
      pauseUponEnteringBackgroundMode: false, // PiP & mini player
    );
  }
}
