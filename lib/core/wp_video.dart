import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Mode decoder, dari paling ringan ke paling aman:
/// 0 = bawaan media_kit (hardware, auto-safe)
/// 1 = hardware tapi frame disalin dulu (mediacodec-copy), obat layar hitam
/// 2 = software penuh (paling aman, paling berat)
/// Level yang terbukti berhasil disimpan per HP, jadi HP yang pernah layar
/// hitam langsung pakai mode aman di pemutaran berikutnya.
class WpDecoder {
  WpDecoder._();

  static const _prefKey = 'wp_decoder_level';
  static const int maxLevel = 2;
  static int _saved = 0;

  static int get savedLevel => _saved;

  /// Panggil sekali di main() setelah MediaKit.ensureInitialized().
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _saved = (p.getInt(_prefKey) ?? 0).clamp(0, maxLevel);
    } catch (_) {}
  }

  static Future<void> remember(int level) async {
    if (level <= _saved) return;
    _saved = level.clamp(0, maxLevel);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_prefKey, _saved);
    } catch (_) {}
  }

  /// Untuk tombol "reset pemutar" di pengaturan (opsional).
  static Future<void> reset() async {
    _saved = 0;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefKey);
    } catch (_) {}
  }

  static VideoControllerConfiguration configFor(int level) {
    switch (level) {
      case 1:
        return const VideoControllerConfiguration(hwdec: 'mediacodec-copy');
      case 2:
        return const VideoControllerConfiguration(enableHardwareAcceleration: false);
      default:
        return const VideoControllerConfiguration();
    }
  }
}

class WpVideoController extends ChangeNotifier {
  /// [startAt] = mulai langsung dari posisi ini (lanjut tontonan). Dipasang
  /// sebagai opsi `start` mpv sebelum file dibuka, jadi tidak bisa
  /// "ditimpa balik" ke 00:00 saat surface video baru terpasang.
  /// [decoderLevel] null = pakai level tersimpan ([WpDecoder.savedLevel]).
  WpVideoController.networkUrl(
    Uri uri, {
    Map<String, String>? httpHeaders,
    Duration? startAt,
    int? decoderLevel,
  })  : _media = Media(uri.toString(), httpHeaders: httpHeaders),
        _startAt = startAt,
        decoderLevel = decoderLevel ?? WpDecoder.savedLevel {
    _setup();
  }

  WpVideoController.file(File file, {Duration? startAt, int? decoderLevel})
      : _media = Media(file.path),
        _startAt = startAt,
        decoderLevel = decoderLevel ?? WpDecoder.savedLevel {
    _setup();
  }

  final Media _media;
  final Duration? _startAt;
  final int decoderLevel;
  late final Player _player;
  late final VideoController video;
  final List<StreamSubscription<dynamic>> _subs = [];
  WpVideoValue _value = const WpVideoValue();
  bool _disposed = false;
  Completer<void>? _ready;

  bool _firstFrame = false;

  /// true begitu frame pertama benar-benar tergambar di layar.
  /// Posisi jalan tapi ini masih false = gejala layar hitam.
  bool get firstFrameRendered => _firstFrame;

  // Seek "dijaga": media_kit di Android memanggil seek(posisi lama) sendiri
  // saat surface video dipasang, sehingga seek kita (lanjut tontonan / skip
  // intro) bisa ketimpa balik. Selama beberapa detik setelah seek, kalau
  // posisi mundur jauh dari target, seek diulang.
  Duration? _seekTarget;
  DateTime _seekUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastReseek = DateTime.fromMillisecondsSinceEpoch(0);
  static const _seekTolerance = Duration(seconds: 3);

  /// true selama posisi belum sampai ke target seek terakhir. Dipakai supaya
  /// riwayat tontonan tidak tersimpan dengan posisi yang salah (00:0x).
  bool get isSeekPending {
    final t = _seekTarget;
    if (t == null) return false;
    if (DateTime.now().isAfter(_seekUntil)) return false;
    return _player.state.position < t - _seekTolerance;
  }

  WpVideoValue get value => _value;

  void _setup() {
    _player = Player();
    video = VideoController(_player, configuration: WpDecoder.configFor(decoderLevel));
    unawaited(video.waitUntilFirstFrameRendered.then((_) {
      if (_disposed) return;
      _firstFrame = true;
      // Mode aman ini terbukti jalan di HP ini: pakai terus ke depannya.
      if (decoderLevel > 0) unawaited(WpDecoder.remember(decoderLevel));
      notifyListeners();
    }).catchError((_) {}));
    final s = _player.stream;
    _subs.addAll([
      s.playing.listen((v) => _set(_value.copyWith(isPlaying: v))),
      s.buffering.listen((v) => _set(_value.copyWith(isBuffering: v))),
      s.completed.listen((v) => _set(_value.copyWith(isCompleted: v))),
      s.position.listen((v) {
        _guardSeek(v);
        _set(_value.copyWith(position: v));
      }),
      s.duration.listen((v) {
        _set(_value.copyWith(duration: v));
        _checkReady();
      }),
      s.width.listen((_) => _onSize()),
      s.height.listen((_) => _onSize()),
      s.error.listen(_onError),
    ]);
  }

  void _guardSeek(Duration pos) {
    final t = _seekTarget;
    if (t == null) return;
    final now = DateTime.now();
    if (now.isAfter(_seekUntil)) {
      _seekTarget = null;
      return;
    }
    if (pos < t - _seekTolerance &&
        now.difference(_lastReseek) > const Duration(milliseconds: 800)) {
      _lastReseek = now;
      unawaited(_player.seek(t));
    }
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
    final start = _startAt;
    if (start != null && start > Duration.zero) {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        try {
          await platform.setProperty(
            'start',
            (start.inMilliseconds / 1000).toStringAsFixed(3),
          );
        } catch (_) {}
      }
      _value = _value.copyWith(position: start);
    }
    await _player.open(_media, play: false);
    await ready.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Video tidak merespons (timeout 30 dtk)');
      },
    );
    // Cadangan kalau opsi start diabaikan / ketimpa: seek + jaga posisinya.
    if (start != null && start > Duration.zero && !_disposed) {
      if (_player.state.position < start - _seekTolerance) {
        await seekTo(start);
      } else {
        _seekTarget = start;
        _seekUntil = DateTime.now().add(const Duration(seconds: 6));
      }
    }
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> seekTo(Duration position) {
    _seekTarget = position;
    _seekUntil = DateTime.now().add(const Duration(seconds: 6));
    _lastReseek = DateTime.now();
    return _player.seek(position);
  }

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
