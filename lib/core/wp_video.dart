import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pemutar video app. Mesin utama ExoPlayer (Media3, android_native/WpExo.kt);
/// media_kit (libmpv) hanya cadangan untuk HP yang tidak bisa memutar lewat
/// ExoPlayer (mis. layar hitam / decoder rusak di sebagian HP MediaTek).
/// API dibuat sama dengan video_player supaya layar player tidak perlu
/// ditulis ulang.
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

/// Mode pemutar, dari paling ringan ke paling aman:
/// 0 = ExoPlayer, decoder hardware (decoder lain otomatis dicoba kalau gagal)
/// 1 = ExoPlayer, decoder software didahulukan
/// 2 = media_kit bawaan (hardware, auto-safe)
/// 3 = media_kit, frame disalin dulu (mediacodec-copy), obat layar hitam
/// 4 = media_kit software penuh (paling aman, paling berat)
/// Level yang terbukti berhasil disimpan per HP, jadi HP yang pernah layar
/// hitam / error langsung pakai mode aman di pemutaran berikutnya.
class WpDecoder {
  WpDecoder._();

  static const _prefKey = 'wp_decoder_level_v2';

  /// Kunci lama (0..2 = mode media_kit) dari versi sebelum ada ExoPlayer.
  static const _oldPrefKey = 'wp_decoder_level';
  static const int maxLevel = 4;

  /// Level pertama yang memakai media_kit.
  static const int firstMpvLevel = 2;
  static int _saved = 0;

  static int get savedLevel => _saved;

  static bool usesExo(int level) => level < firstMpvLevel;

  /// Panggil sekali di main() setelah MediaKit.ensureInitialized().
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v2 = p.getInt(_prefKey);
      if (v2 != null) {
        _saved = v2.clamp(0, maxLevel);
        return;
      }
      // HP yang dulu butuh mode aman media_kit (copy / software) langsung
      // ke mode yang sama, tidak dicoba ExoPlayer lagi.
      final old = p.getInt(_oldPrefKey) ?? 0;
      _saved = old > 0 ? (old + firstMpvLevel).clamp(0, maxLevel) : 0;
      await p.setInt(_prefKey, _saved);
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

  /// Konfigurasi media_kit untuk level 2..4.
  static VideoControllerConfiguration configFor(int level) {
    switch (level) {
      case 3:
        return const VideoControllerConfiguration(hwdec: 'mediacodec-copy');
      case 4:
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
  })  : _url = uri.toString(),
        _filePath = null,
        _headers = httpHeaders ?? const {},
        _startAt = startAt,
        decoderLevel = (decoderLevel ?? WpDecoder.savedLevel).clamp(0, WpDecoder.maxLevel) {
    _setup();
  }

  WpVideoController.file(File file, {Duration? startAt, int? decoderLevel})
      : _url = Uri.file(file.path).toString(),
        _filePath = file.path,
        _headers = const {},
        _startAt = startAt,
        decoderLevel = (decoderLevel ?? WpDecoder.savedLevel).clamp(0, WpDecoder.maxLevel) {
    _setup();
  }

  final String _url;
  final String? _filePath;
  final Map<String, String> _headers;
  final Duration? _startAt;
  final int decoderLevel;

  /// true = diputar lewat ExoPlayer, false = media_kit.
  bool get usesExo => WpDecoder.usesExo(decoderLevel);

  // media_kit (hanya terisi kalau !usesExo)
  Player? _player;
  VideoController? _mpvVideo;

  // ExoPlayer (hanya terisi kalau usesExo)
  static const MethodChannel _exo = MethodChannel('wibuplay/exo');
  int? _exoId;
  int? _textureId;
  Duration _exoPos = Duration.zero;

  /// Texture Flutter untuk ExoPlayer (null sebelum siap / kalau media_kit).
  int? get textureId => _textureId;

  /// Controller media_kit untuk widget Video (null kalau pakai ExoPlayer).
  VideoController? get video => _mpvVideo;

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
    return _rawPosition < t - _seekTolerance;
  }

  Duration get _rawPosition => usesExo ? _exoPos : (_player?.state.position ?? Duration.zero);

  WpVideoValue get value => _value;

  void _onFirstFrame() {
    if (_disposed || _firstFrame) return;
    _firstFrame = true;
    // Mode aman ini terbukti jalan di HP ini: pakai terus ke depannya.
    if (decoderLevel > 0) unawaited(WpDecoder.remember(decoderLevel));
    notifyListeners();
  }

  void _setup() {
    if (usesExo) return; // ExoPlayer dibuat di initialize() (async).
    final player = Player();
    _player = player;
    final video = VideoController(player, configuration: WpDecoder.configFor(decoderLevel));
    _mpvVideo = video;
    unawaited(video.waitUntilFirstFrameRendered.then((_) => _onFirstFrame()).catchError((_) {}));
    final s = player.stream;
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
      unawaited(_engineSeek(t));
    }
  }

  void _set(WpVideoValue v) {
    if (_disposed) return;
    _value = v;
    notifyListeners();
  }

  void _onSize() {
    final p = _player;
    if (p == null) return;
    final w = p.state.width ?? 0;
    final h = p.state.height ?? 0;
    _set(_value.copyWith(size: Size(w.toDouble(), h.toDouble())));
    _checkReady();
  }

  void _checkReady() {
    final p = _player;
    if (_disposed || _value.isInitialized || p == null) return;
    final hasSize = (p.state.width ?? 0) > 0;
    final hasDuration = p.state.duration > Duration.zero;
    if (!hasSize && !hasDuration) return;
    _markReady();
  }

  void _markReady() {
    if (_disposed || _value.isInitialized) return;
    _set(_value.copyWith(isInitialized: true));
    final r = _ready;
    if (r != null && !r.isCompleted) r.complete();
  }

  // ------------------------------------------------------------ ExoPlayer

  Future<void> _openExo(Duration? start) async {
    final res = await _exo.invokeMapMethod<String, dynamic>('create', {
      'url': _url,
      'headers': _headers,
      'startMs': start?.inMilliseconds ?? 0,
      'software': decoderLevel == 1,
    });
    final id = (res?['id'] as num?)?.toInt();
    final tex = (res?['textureId'] as num?)?.toInt();
    if (id == null || tex == null) throw Exception('ExoPlayer gagal dibuat');
    if (_disposed) {
      unawaited(_exo.invokeMethod<void>('dispose', {'id': id}).catchError((Object _) {}));
      return;
    }
    _exoId = id;
    _textureId = tex;
    _subs.add(
      EventChannel('wibuplay/exo/events/$id').receiveBroadcastStream().listen(
            _onExoEvent,
            onError: (Object e) => _onExoError(e is PlatformException ? (e.message ?? e.code) : '$e'),
          ),
    );
    notifyListeners();
  }

  void _onExoEvent(dynamic raw) {
    if (_disposed || raw is! Map) return;
    int i(String k) => (raw[k] as num?)?.toInt() ?? 0;
    switch (raw['e']) {
      case 'pos':
        _exoPos = Duration(milliseconds: i('p'));
        _guardSeek(_exoPos);
        final d = i('d');
        _set(_value.copyWith(
          position: _exoPos,
          duration: d > 0 ? Duration(milliseconds: d) : null,
        ));
      case 'ready':
        final w = i('w');
        final h = i('h');
        final d = i('d');
        _set(_value.copyWith(
          size: w > 0 && h > 0 ? Size(w.toDouble(), h.toDouble()) : null,
          duration: d > 0 ? Duration(milliseconds: d) : null,
          isBuffering: false,
        ));
        _markReady();
      case 'size':
        final w = i('w');
        final h = i('h');
        if (w > 0 && h > 0) _set(_value.copyWith(size: Size(w.toDouble(), h.toDouble())));
      case 'buffering':
        _set(_value.copyWith(isBuffering: raw['v'] == true));
      case 'playing':
        final v = raw['v'] == true;
        _set(_value.copyWith(isPlaying: v, isCompleted: v ? false : null));
      case 'ended':
        _set(_value.copyWith(isCompleted: true, isPlaying: false));
      case 'frame':
        _onFirstFrame();
      case 'error':
        final code = i('code');
        final msg = (raw['msg'] as String?) ?? 'ExoPlayer error';
        // 3xxx = format/kontainer, 4xxx = decoder: tandai "Decoder" supaya
        // layar player otomatis pindah ke mode berikutnya (akhirnya media_kit).
        final isDecoder = code >= 3000 && code < 5000;
        _onExoError(isDecoder ? 'ExoPlayer Decoder $msg' : 'ExoPlayer $msg');
    }
  }

  /// Error ExoPlayer selalu fatal (pemutaran berhenti), jadi diteruskan juga
  /// setelah video mulai main supaya layar bisa coba ulang / pindah mode.
  void _onExoError(String msg) {
    if (_disposed || msg.isEmpty) return;
    _set(_value.copyWith(errorDescription: msg, isBuffering: false, isPlaying: false));
    final r = _ready;
    if (r != null && !r.isCompleted) r.completeError(Exception(msg));
  }

  Future<void> _exoCall(String method, [Map<String, Object?> args = const {}]) async {
    final id = _exoId;
    if (id == null || _disposed) return;
    try {
      await _exo.invokeMethod<void>(method, {'id': id, ...args});
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  Future<void> _engineSeek(Duration t) {
    if (usesExo) {
      _exoPos = t;
      return _exoCall('seek', {'ms': t.inMilliseconds});
    }
    return _player?.seek(t) ?? Future<void>.value();
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
    if (usesExo) {
      // ExoPlayer langsung dibuka di posisi start, tidak perlu seek dijaga.
      if (start != null && start > Duration.zero) {
        _exoPos = start;
        _value = _value.copyWith(position: start);
      }
      try {
        await _openExo(start != null && start > Duration.zero ? start : null);
      } on MissingPluginException {
        throw Exception('ExoPlayer Decoder tidak tersedia di build ini');
      } on PlatformException catch (e) {
        throw Exception('ExoPlayer Decoder ${e.message ?? e.code}');
      }
      await ready.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Video tidak merespons (timeout 30 dtk)');
        },
      );
      return;
    }
    final player = _player!;
    if (start != null && start > Duration.zero) {
      final platform = player.platform;
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
    await player.open(Media(_filePath ?? _url, httpHeaders: _headers.isEmpty ? null : _headers), play: false);
    await ready.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Video tidak merespons (timeout 30 dtk)');
      },
    );
    // Cadangan kalau opsi start diabaikan / ketimpa: seek + jaga posisinya.
    if (start != null && start > Duration.zero && !_disposed) {
      if (player.state.position < start - _seekTolerance) {
        await seekTo(start);
      } else {
        _seekTarget = start;
        _seekUntil = DateTime.now().add(const Duration(seconds: 6));
      }
    }
  }

  Future<void> play() {
    if (usesExo) {
      // Diputar ulang setelah selesai: mulai lagi dari awal seperti mpv.
      if (_value.isCompleted && _value.duration > Duration.zero && _exoPos >= _value.duration - const Duration(milliseconds: 500)) {
        unawaited(_engineSeek(Duration.zero));
      }
      return _exoCall('play');
    }
    return _player?.play() ?? Future<void>.value();
  }

  Future<void> pause() => usesExo ? _exoCall('pause') : (_player?.pause() ?? Future<void>.value());

  Future<void> seekTo(Duration position) {
    _seekTarget = position;
    _seekUntil = DateTime.now().add(const Duration(seconds: 6));
    _lastReseek = DateTime.now();
    if (usesExo) {
      _set(_value.copyWith(position: position, isCompleted: false));
    }
    return _engineSeek(position);
  }

  Future<void> setPlaybackSpeed(double speed) =>
      usesExo ? _exoCall('speed', {'v': speed}) : (_player?.setRate(speed) ?? Future<void>.value());

  /// Volume video 0..100 (dipakai Nobar supaya suara teman tetap terdengar).
  Future<void> setVolume(double volume) {
    final v = volume.clamp(0, 100).toDouble();
    return usesExo ? _exoCall('volume', {'v': v / 100}) : (_player?.setVolume(v) ?? Future<void>.value());
  }

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
    final id = _exoId;
    _exoId = null;
    _textureId = null;
    if (id != null) {
      try {
        await _exo.invokeMethod<void>('dispose', {'id': id});
      } catch (_) {}
    }
    try {
      await _player?.dispose();
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
    if (controller.usesExo) return _ExoView(controller);
    final video = controller.video;
    if (video == null) return const ColoredBox(color: Colors.black);
    return Video(
      controller: video,
      controls: NoVideoControls,
      fit: BoxFit.contain,
      fill: Colors.black,
      wakelock: false, // wakelock sudah diatur WakelockPlus di layar player
      pauseUponEnteringBackgroundMode: false, // PiP & mini player
    );
  }
}

/// Tampilan ExoPlayer: texture di tengah dengan rasio video (BoxFit.contain).
class _ExoView extends StatelessWidget {
  const _ExoView(this.controller);

  final WpVideoController controller;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final id = controller.textureId;
          final size = controller.value.size;
          if (id == null || size.width <= 0 || size.height <= 0) {
            return const SizedBox.expand();
          }
          return SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Texture(textureId: id),
              ),
            ),
          );
        },
      ),
    );
  }
}
