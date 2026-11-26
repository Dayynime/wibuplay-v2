import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers.dart';

/// Suasana maskot.
enum MascotMood { idle, sleep, wave, shock }

/// Maskot Zenime (cowok anime: rambut jabrik bergaris merah, headphone Z,
/// plester di pipi) yang mengintip dari atas navbar.
///
/// - Malam (22.00–05.00): tidur, "z" melayang.
/// - Kembali ke app / pertama muncul / diketuk: hormat dua jari.
/// - Jumlah notifikasi belum dibaca bertambah (mis. episode baru): kaget "!".
/// - Selain itu diam dengan kedipan mata sesekali.
/// Tekan lama = sembunyi sampai app dibuka lagi.
/// Digambar langsung (CustomPainter), jadi tidak butuh file gambar/Lottie.
class ZenimeMascot extends ConsumerStatefulWidget {
  const ZenimeMascot({super.key});

  @override
  ConsumerState<ZenimeMascot> createState() => _ZenimeMascotState();
}

class _ZenimeMascotState extends ConsumerState<ZenimeMascot>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Jam animasi terus-menerus (napas, lambaian, z, kedip).
  /// Cuma berjalan saat tidur/melambai; saat diam berhenti total (hemat
  /// baterai), kedipan pakai timer.
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  Timer? _blinkTimer;
  bool _blink = false;

  /// Lompatan saat kaget / diketuk.
  late final AnimationController _jump =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450), value: 1);

  MascotMood? _event; // suasana sementara (wave/shock)
  Timer? _eventTimer;
  Timer? _clock;
  bool _hidden = false;
  bool _night = false;

  static bool _hiddenForSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hidden = _hiddenForSession;
    _night = _isNight();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      final n = _isNight();
      if (n != _night && mounted) setState(() => _night = n);
    });
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (!mounted || _event != null || _night) return;
      setState(() => _blink = true);
      Timer(const Duration(milliseconds: 140), () {
        if (mounted) setState(() => _blink = false);
      });
    });
    // Sapaan pertama.
    WidgetsBinding.instance.addPostFrameCallback((_) => _play(MascotMood.wave, const Duration(seconds: 3)));
  }

  static bool _isNight() {
    final h = DateTime.now().hour;
    return h >= 22 || h < 5;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _night = _isNight();
      _play(MascotMood.wave, const Duration(seconds: 3));
    }
  }

  void _play(MascotMood mood, Duration d) {
    if (!mounted) return;
    _eventTimer?.cancel();
    setState(() => _event = mood);
    if (mood == MascotMood.shock && !MediaQuery.disableAnimationsOf(context)) _jump.forward(from: 0);
    _eventTimer = Timer(d, () {
      if (mounted) setState(() => _event = null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventTimer?.cancel();
    _clock?.cancel();
    _blinkTimer?.cancel();
    _loop.dispose();
    _jump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Notifikasi belum dibaca bertambah = ada yang baru -> kaget.
    ref.listen<AsyncValue<int>>(unreadNotificationsProvider, (prev, next) {
      final a = prev?.valueOrNull, b = next.valueOrNull;
      if (a != null && b != null && b > a) _play(MascotMood.shock, const Duration(seconds: 3));
    });

    if (_hidden) return const SizedBox.shrink();
    final still = MediaQuery.disableAnimationsOf(context);
    final mood = _event ?? (_night ? MascotMood.sleep : MascotMood.idle);
    final needLoop = !still && (mood == MascotMood.sleep || mood == MascotMood.wave);
    if (needLoop != _loop.isAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (needLoop && !_loop.isAnimating) {
          _loop.repeat();
        } else if (!needLoop && _loop.isAnimating) {
          _loop.stop();
        }
      });
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (!still) _jump.forward(from: 0);
        _play(MascotMood.wave, const Duration(milliseconds: 2200));
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _hiddenForSession = true;
        setState(() => _hidden = true);
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _jump]),
        builder: (context, _) => RepaintBoundary(
          child: CustomPaint(
            size: const Size(72, 67.5),
            painter: _MascotPainter(
              mood: mood,
              t: still ? 0 : _loop.value,
              jump: still ? 1 : _jump.value,
              blink: _blink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Parser path SVG mini (M L H V Q C Z, huruf kecil = relatif) supaya
/// gambar maskot bisa ditulis sama persis dengan desain SVG-nya.
Path _svg(String d) {
  final path = Path();
  final tok = RegExp(r'[MLHVQCZmlhvqcz]|-?\d*\.?\d+').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0;
  double n() => double.parse(tok[i++]);
  while (i < tok.length) {
    if (RegExp(r'^[A-Za-z]$').hasMatch(tok[i])) cmd = tok[i++];
    switch (cmd) {
      case 'M':
        x = n();
        y = n();
        path.moveTo(x, y);
        cmd = 'L';
      case 'm':
        x += n();
        y += n();
        path.moveTo(x, y);
        cmd = 'l';
      case 'L':
        x = n();
        y = n();
        path.lineTo(x, y);
      case 'l':
        x += n();
        y += n();
        path.lineTo(x, y);
      case 'H':
        x = n();
        path.lineTo(x, y);
      case 'h':
        x += n();
        path.lineTo(x, y);
      case 'V':
        y = n();
        path.lineTo(x, y);
      case 'v':
        y += n();
        path.lineTo(x, y);
      case 'Q':
        final cx = n(), cy = n();
        x = n();
        y = n();
        path.quadraticBezierTo(cx, cy, x, y);
      case 'C':
        final c1x = n(), c1y = n(), c2x = n(), c2y = n();
        x = n();
        y = n();
        path.cubicTo(c1x, c1y, c2x, c2y, x, y);
      case 'Z':
      case 'z':
        path.close();
        // Angka nyasar setelah Z: lewati supaya tidak macet.
        if (i < tok.length && !RegExp(r'^[A-Za-z]$').hasMatch(tok[i])) i++;
      default:
        i++;
    }
  }
  return path;
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({required this.mood, required this.t, required this.jump, required this.blink});

  final MascotMood mood;
  final bool blink;
  final double t; // 0..1 dalam 6 detik
  final double jump; // 0..1

  // Warna.
  static const Color _skin = Color(0xFFF7D9C6);
  static const Color _skinEdge = Color(0xFFD9A98F);
  static const Color _ear = Color(0xFFEFC9B4);
  static const Color _neck = Color(0xFFE9C2AC);
  static const Color _hairBack = Color(0xFF141625);
  static const Color _hair = Color(0xFF1B1E30);
  static const Color _shine = Color(0xFF3B4166);
  static const Color _line = Color(0xFF141625);
  static const Color _iris = Color(0xFFC8243A);
  static const Color _irisLow = Color(0xFFFF6B7E);
  static const Color _pupil = Color(0xFF3A0A12);
  static const Color _gear = Color(0xFF2A2F3E);
  static const Color _shirt = Color(0xFF1B1F2C);
  static const Color _mouth = Color(0xFFA04050);

  // Bentuk (koordinat desain 128 x 120).
  static final Path _collar = _svg('M30 102 Q64 86 98 102 L104 120 L24 120 Z');
  static final Path _vNeck = _svg('M50 96 L64 108 L78 96');
  static final Path _neckP = _svg('M55 88 L73 88 L72 100 L56 100 Z');
  static final Path _back = _svg('M20 70 Q12 40 30 22 Q48 4 72 8 Q100 12 108 38 Q112 56 106 74 L96 84 L30 84 Z');
  static final Path _face = _svg('M33 52 Q33 84 64 92 Q95 84 95 52 Q95 36 64 34 Q33 36 33 52Z');
  static final Path _band = _svg('M24 62 Q22 22 64 20 Q106 22 104 62');
  static final Path _zMark = _svg('M101.5 61 h6 l-6 8 h6');
  static final Path _bangs = _svg(
      'M28 66 L26 44 Q30 22 54 16 Q80 12 96 28 Q104 38 102 58 L96 46 L94 60 L86 42 L80 56 L74 38 L66 58 L62 40 L54 56 L50 42 L42 60 L40 48 L33 70 Z');
  static final Path _lockL = _svg('M28 66 L20 82 L34 70 Z');
  static final Path _lockR = _svg('M100 60 L108 80 L96 68 Z');
  static final Path _streak = _svg('M66 18 Q74 26 80 56 L74 38 L70 44 Q70 30 66 18 Z');
  static final Path _spikes =
      _svg('M30 30 Q34 14 50 10 L46 2 Q62 4 70 10 L74 0 Q88 8 92 18 L106 14 Q104 26 100 32 L112 34 Q104 40 98 40 Z');
  static final Path _spikeSide = _svg('M16 46 Q18 30 28 24 L22 40 Z');
  static final Path _shine1 = _svg('M40 24 Q56 14 76 16');
  static final Path _shine2 = _svg('M84 20 Q92 24 96 30');
  static final Path _eyeWL = _svg('M38 60 Q46 54 55 58 L55 66 Q46 70 39 66 Z');
  static final Path _eyeWR = _svg('M73 58 Q82 54 90 60 L89 66 Q82 70 73 66 Z');
  static final Path _lashL = _svg('M36 59 Q46 51 57 56');
  static final Path _lashR = _svg('M71 56 Q82 51 92 59');
  static final Path _browL = _svg('M38 50 L54 52');
  static final Path _browR = _svg('M74 52 L90 49');
  static final Path _browShockL = _svg('M36 47 L54 50');
  static final Path _browShockR = _svg('M74 50 L92 47');
  static final Path _sleepL = _svg('M39 63 Q47 67 55 63');
  static final Path _sleepR = _svg('M73 63 Q81 67 89 63');
  static final Path _sleepBrowL = _svg('M39 53 L54 54');
  static final Path _sleepBrowR = _svg('M74 54 L89 53');
  static final Path _nose = _svg('M64 70 L62 74 L65 74');
  static final Path _smirk = _svg('M58 78 Q65 82 71 76');
  static final Path _calm = _svg('M60 79 Q64 81 68 79');
  static final Path _gasp = _svg('M59 79 Q64 74 69 79 Q64 83 59 79Z');
  static final Path _sweat = _svg('M100 38 Q104 46 100 50 Q96 46 100 38Z');
  static final Path _salute = _svg(
      'M96 76 Q94 64 98 60 L101 44 Q102 40 105 41 Q107 42 106 46 L104 58 L108 42 Q109 38 112 39 Q114 40 113 44 L109 62 Q112 70 106 80 Z');

  Paint _f(Color c) => Paint()..color = c;
  Paint _s(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c;

  void _text(Canvas c, String s, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 128, size.height / 120);

    // Kepala: napas pelan saat tidur, lompat saat kaget/diketuk.
    final breathe = mood == MascotMood.sleep ? math.sin(t * math.pi * 2 * 2.5) * 1.4 : 0.0;
    final hop = jump < 1 ? -18 * math.sin(jump * math.pi) : 0.0;

    c.save();
    c.translate(0, breathe + hop);

    c.drawPath(_collar, _f(_shirt));
    c.drawPath(_vNeck, _s(AppColors.accentViolet, 3));
    c.drawPath(_neckP, _f(_neck));
    c.drawPath(_back, _f(_hairBack));
    c.drawPath(_face, _f(_skin));
    c.drawOval(Rect.fromCenter(center: const Offset(32, 64), width: 10, height: 14), _f(_ear));
    c.drawOval(Rect.fromCenter(center: const Offset(96, 64), width: 10, height: 14), _f(_ear));

    // Headphone + logo Z.
    c.drawPath(_band, _s(_gear, 5));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(17, 54, 13, 22), const Radius.circular(6)), _f(_gear));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(98, 54, 13, 22), const Radius.circular(6)), _f(_gear));
    c.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(19.5, 58, 8, 14), const Radius.circular(4)), _f(AppColors.accentViolet));
    c.drawPath(_zMark, _s(AppColors.accentViolet, 1.8));

    // Rambut.
    c.drawPath(_bangs, _f(_hair));
    c.drawPath(_lockL, _f(_hair));
    c.drawPath(_lockR, _f(_hair));
    c.drawPath(_streak, _f(AppColors.accentViolet));
    c.drawPath(_spikes, _f(_hairBack));
    c.drawPath(_spikeSide, _f(_hairBack));
    c.drawPath(_shine1, _s(_shine, 2.4));
    c.drawPath(_shine2, _s(_shine, 2));

    // Mata.
    final closed = mood == MascotMood.sleep || (blink && mood == MascotMood.idle);
    if (closed) {
      final l = _s(_line, 2.6);
      for (final p in [_sleepL, _sleepR, _sleepBrowL, _sleepBrowR]) {
        c.drawPath(p, l);
      }
    } else if (mood == MascotMood.shock) {
      for (final x in const [47.0, 81.0]) {
        final r = Rect.fromCenter(center: Offset(x, 62), width: 16, height: 17);
        c.drawOval(r, _f(Colors.white));
        c.drawOval(r, _s(_line, 2));
        c.drawCircle(Offset(x, 62), 2.6, _f(_iris));
      }
      c.drawPath(_browShockL, _s(_line, 2.4));
      c.drawPath(_browShockR, _s(_line, 2.4));
    } else {
      c.drawPath(_eyeWL, _f(Colors.white));
      c.drawPath(_eyeWR, _f(Colors.white));
      for (final x in const [49.0, 79.0]) {
        c.drawOval(Rect.fromCenter(center: Offset(x, 62.5), width: 10, height: 12.4), _f(_iris));
        c.drawOval(Rect.fromCenter(center: Offset(x, 65.5), width: 7.2, height: 4.8), _f(_irisLow));
        c.drawOval(Rect.fromCenter(center: Offset(x, 63.5), width: 5.2, height: 7.2), _f(_pupil));
        c.drawCircle(Offset(x + 2, 60), 1.7, _f(Colors.white));
      }
      c.drawPath(_lashL, _s(_line, 2.6));
      c.drawPath(_lashR, _s(_line, 2.6));
      c.drawPath(_browL, _s(_line, 2.4));
      c.drawPath(_browR, _s(_line, 2.4));
    }

    c.drawPath(_nose, _s(const Color(0xFFD6A48D), 1.4));
    switch (mood) {
      case MascotMood.shock:
        c.drawPath(_gasp, _f(const Color(0xFF7A1F2E)));
      case MascotMood.sleep:
        c.drawPath(_calm, _s(_mouth, 2));
      default:
        c.drawPath(_smirk, _s(_mouth, 2.2));
    }

    // Plester di pipi.
    c.save();
    c.translate(84, 76);
    c.rotate(-20 * math.pi / 180);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-6, -3, 12, 5), const Radius.circular(2)),
        _f(const Color(0xE6FFFFFF)));
    c.drawLine(const Offset(-2, -3), const Offset(-2, 2), _s(const Color(0xFFDDDDDD), 0.8));
    c.drawLine(const Offset(2, -3), const Offset(2, 2), _s(const Color(0xFFDDDDDD), 0.8));
    c.restore();

    if (mood == MascotMood.shock) c.drawPath(_sweat, _f(const Color(0xFF7CC6FF)));
    c.restore();

    // Tangan di tepi navbar; tangan kanan hormat dua jari saat menyapa.
    final hand = Rect.fromCenter(center: const Offset(32, 113), width: 20, height: 14);
    c.drawOval(hand, _f(_skin));
    c.drawOval(hand, _s(_skinEdge, 1));
    if (mood == MascotMood.wave) {
      final a = math.sin(t * math.pi * 2 * 4) * 0.12; // ayunan kecil
      c.save();
      c.translate(14, 8);
      c.scale(0.85);
      c.translate(100, 70);
      c.rotate(-14 * math.pi / 180 + a);
      c.translate(-100, -70);
      c.drawPath(_salute, _f(_skin));
      c.drawPath(_salute, _s(_skinEdge, 1));
      c.restore();
    } else {
      final r = Rect.fromCenter(center: const Offset(96, 113), width: 20, height: 14);
      c.drawOval(r, _f(_skin));
      c.drawOval(r, _s(_skinEdge, 1));
    }

    if (mood == MascotMood.shock) {
      c.drawCircle(const Offset(118, 14), 12, _f(Colors.white));
      _text(c, '!', const Offset(118, 14), 17, AppColors.accentViolet);
    }

    // "z" melayang saat tidur.
    if (mood == MascotMood.sleep) {
      for (var k = 0; k < 2; k++) {
        final p = (t * 2.5 + k * 0.5) % 1;
        final a = (p < 0.3 ? p / 0.3 : 1 - (p - 0.3) / 0.7).clamp(0.0, 1.0);
        _text(c, k == 0 ? 'z' : 'Z', Offset(104 + p * 16, 22 - p * 26), 13 + p * 8,
            AppColors.textSecondary.withValues(alpha: a));
      }
    }
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.mood != mood || old.t != t || old.jump != jump || old.blink != blink;
}
