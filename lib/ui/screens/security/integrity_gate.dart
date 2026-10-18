import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/integrity_guard.dart';
import '../../../core/theme/app_colors.dart';

/// Gerbang keamanan paling luar (port blockedTool di MainActivity.kt Zenime).
///
/// Dicek SEBELUM [onClear] (init Firebase / Remote Config) dan sebelum [child]
/// dibangun, jadi kalau kedeteksi tidak ada request API sama sekali. Dicek
/// lagi tiap app balik ke foreground: app terlarang baru dipasang = langsung
/// diblokir; sudah di-uninstall = app lanjut normal tanpa force-close.
class IntegrityGate extends StatefulWidget {
  const IntegrityGate({super.key, required this.onClear, required this.child});

  /// Dipanggil sekali, setelah lolos cek pertama (init backend).
  final Future<void> Function() onClear;
  final Widget child;

  @override
  State<IntegrityGate> createState() => _IntegrityGateState();
}

class _IntegrityGateState extends State<IntegrityGate> with WidgetsBindingObserver {
  String? _blocked;
  bool _ready = false;
  bool _initStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final tool = await IntegrityGuard.detectedTool();
    if (!mounted) return;
    setState(() => _blocked = tool);
    if (tool == null && !_initStarted) {
      _initStarted = true;
      await widget.onClear();
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = _blocked;
    if (tool != null) {
      return BlockedToolScreen(
        toolName: tool,
        onExit: () => SystemNavigator.pop(),
      );
    }
    if (!_ready) {
      return const Scaffold(backgroundColor: AppColors.backgroundDark);
    }
    return widget.child;
  }
}

/// Layar blokir bergaya terminal "hacker": hujan karakter, garis scan,
/// judul glitch, dan log pemindaian yang diketik. Tombol back juga cuma keluar.
class BlockedToolScreen extends StatefulWidget {
  const BlockedToolScreen({super.key, required this.toolName, required this.onExit});

  final String toolName;
  final VoidCallback onExit;

  @override
  State<BlockedToolScreen> createState() => _BlockedToolScreenState();
}

const Color _neon = Color(0xFF39FF88);
const Color _alert = Color(0xFFFF3B5C);
const Color _bg = Color(0xFF05080B);
const String _mono = 'monospace';

class _BlockedToolScreenState extends State<BlockedToolScreen> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _type;
  late final List<_LogLine> _lines;
  late final int _totalChars;

  @override
  void initState() {
    super.initState();
    _lines = [
      const _LogLine('> zenime-guard --scan', _neon),
      const _LogLine('[ OK ] memindai perangkat...', _neon),
      const _LogLine('[ OK ] memeriksa integritas aplikasi...', _neon),
      _LogLine('[ !! ] ancaman terdeteksi: ${widget.toolName}', _alert),
      const _LogLine('[ !! ] sesi diblokir demi keamanan akun', _alert),
    ];
    _totalChars = _lines.fold(0, (a, l) => a + l.text.length);
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _type = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: reduce ? 1 : _totalChars * 28),
    )..forward();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _loop.dispose();
    _type.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onExit();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Hujan karakter
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _loop,
                builder: (_, __) => CustomPaint(painter: _RainPainter(_loop.value)),
              ),
            ),
            // Vignette supaya teks tetap terbaca
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.9,
                  colors: [Color(0xCC05080B), Color(0xF205080B)],
                ),
              ),
            ),
            // Garis scan
            IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _loop,
                  builder: (_, __) => CustomPaint(painter: _ScanPainter(_loop.value)),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _statusBar(),
                    const Spacer(),
                    _Radar(loop: _loop),
                    const SizedBox(height: 22),
                    _GlitchText(loop: _loop, text: 'AKSES DITOLAK'),
                    const SizedBox(height: 6),
                    const Text(
                      'Woy, ngapain itu?',
                      style: TextStyle(color: Colors.white70, fontSize: 15, fontFamily: _mono),
                    ),
                    const SizedBox(height: 20),
                    _terminal(),
                    const SizedBox(height: 14),
                    Text(
                      'Nonton tinggal nonton aja... hapus atau matiin dulu "${widget.toolName}".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF8FA3A0), fontSize: 13, height: 1.4),
                    ),
                    const Spacer(),
                    _exitButton(),
                    const SizedBox(height: 12),
                    const Text(
                      'Udah dihapus atau dimatiin? Buka Zenime lagi, langsung jalan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0x998FA3A0), fontSize: 11.5),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar() {
    return AnimatedBuilder(
      animation: _loop,
      builder: (_, __) {
        final on = (_loop.value * 12).floor().isEven;
        return Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? _alert : _alert.withValues(alpha: 0.25),
                boxShadow: on ? [BoxShadow(color: _alert.withValues(alpha: 0.8), blurRadius: 8)] : null,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'SECURITY ALERT',
              style: TextStyle(
                color: _alert,
                fontFamily: _mono,
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            const Text(
              'ZENIME-GUARD',
              style: TextStyle(color: Color(0x8039FF88), fontFamily: _mono, fontSize: 11, letterSpacing: 1.5),
            ),
          ],
        );
      },
    );
  }

  Widget _terminal() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xCC0A1210),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _neon.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: _neon.withValues(alpha: 0.10), blurRadius: 24)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)]) ...[
                Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 4),
              const Text('root@zenime: ~',
                  style: TextStyle(color: Color(0x8039FF88), fontFamily: _mono, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: Listenable.merge([_type, _loop]),
            builder: (_, __) {
              var budget = (_type.value * _totalChars).floor();
              final children = <Widget>[];
              for (final l in _lines) {
                if (budget <= 0) break;
                final n = budget.clamp(0, l.text.length);
                budget -= l.text.length;
                children.add(Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    l.text.substring(0, n),
                    style: TextStyle(color: l.color, fontFamily: _mono, fontSize: 12.5, height: 1.3),
                  ),
                ));
              }
              final cursorOn = (_loop.value * 18).floor().isEven;
              children.add(Text(
                cursorOn ? '> _' : '>  ',
                style: const TextStyle(color: _neon, fontFamily: _mono, fontSize: 12.5),
              ));
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
            },
          ),
        ],
      ),
    );
  }

  Widget _exitButton() {
    return AnimatedBuilder(
      animation: _type,
      builder: (_, child) => Opacity(opacity: Curves.easeOut.transform(_type.value), child: child),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: _alert.withValues(alpha: 0.35), blurRadius: 22)],
          ),
          child: FilledButton(
            onPressed: widget.onExit,
            style: FilledButton.styleFrom(
              backgroundColor: _alert,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'OKE, GUE KELUAR DULU',
              style: TextStyle(fontFamily: _mono, fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogLine {
  const _LogLine(this.text, this.color);
  final String text;
  final Color color;
}

/// Ikon perisai dengan cincin radar berputar & denyut.
class _Radar extends StatelessWidget {
  const _Radar({required this.loop});

  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: AnimatedBuilder(
        animation: loop,
        builder: (_, __) {
          final t = loop.value;
          final pulse = (math.sin(t * math.pi * 6) + 1) / 2;
          return CustomPaint(
            painter: _RadarPainter(t),
            child: Center(
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _alert.withValues(alpha: 0.10 + 0.08 * pulse),
                  border: Border.all(color: _alert.withValues(alpha: 0.7)),
                  boxShadow: [BoxShadow(color: _alert.withValues(alpha: 0.25 + 0.3 * pulse), blurRadius: 30)],
                ),
                child: const Icon(Icons.gpp_bad_outlined, color: _alert, size: 38),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _neon.withValues(alpha: 0.18);
    canvas.drawCircle(c, r, thin);
    canvas.drawCircle(c, r * 0.72, thin);

    // Sapuan radar
    final rect = Rect.fromCircle(center: c, radius: r);
    final start = t * 2 * math.pi * 2;
    canvas.drawArc(
      rect,
      start,
      math.pi / 2.2,
      true,
      Paint()
        ..shader = SweepGradient(
          colors: [_neon.withValues(alpha: 0), _neon.withValues(alpha: 0.22)],
          stops: const [0, 1],
          transform: GradientRotation(start),
          endAngle: math.pi / 2.2,
        ).createShader(rect),
    );

    // Cincin putus-putus berputar berlawanan
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = _alert.withValues(alpha: 0.6);
    const segs = 12;
    for (var i = 0; i < segs; i++) {
      final a = -t * 2 * math.pi + i * 2 * math.pi / segs;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.86), a, 0.25, false, dash);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

/// Judul dengan efek glitch (pergeseran merah/hijau sesekali).
class _GlitchText extends StatelessWidget {
  const _GlitchText({required this.loop, required this.text});

  final Animation<double> loop;
  final String text;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: _mono,
      fontSize: 30,
      fontWeight: FontWeight.w900,
      letterSpacing: 3,
    );
    return AnimatedBuilder(
      animation: loop,
      builder: (_, __) {
        final phase = (loop.value * 40).floor();
        // Glitch singkat tiap beberapa saat
        final glitch = phase % 13 == 0 || phase % 17 == 0;
        final dx = glitch ? (phase.isEven ? 3.0 : -3.0) : 0.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(dx, 0),
              child: Text(text, style: style.copyWith(color: _alert.withValues(alpha: glitch ? 0.8 : 0.0))),
            ),
            Transform.translate(
              offset: Offset(-dx, 0),
              child: Text(text, style: style.copyWith(color: _neon.withValues(alpha: glitch ? 0.6 : 0.0))),
            ),
            Text(
              text,
              style: style.copyWith(
                color: Colors.white,
                shadows: const [Shadow(color: _alert, blurRadius: 18)],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Hujan karakter ala terminal.
class _RainPainter extends CustomPainter {
  _RainPainter(this.t);
  final double t;

  static const String _glyphs = '01アイウエオカキクケコサシスセソ<>/{}#\$%ZENIME';
  static final Map<String, TextPainter> _cache = {};

  static TextPainter _glyph(String ch, int level) {
    final key = '$ch$level';
    return _cache.putIfAbsent(key, () {
      final alpha = switch (level) { 0 => 0.95, 1 => 0.45, _ => 0.18 };
      final color = level == 0 ? const Color(0xFFB8FFD6) : _neon.withValues(alpha: alpha);
      return TextPainter(
        text: TextSpan(text: ch, style: TextStyle(color: color, fontSize: 13, fontFamily: _mono)),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    const colW = 16.0;
    const rowH = 16.0;
    final cols = (size.width / colW).ceil();
    final rows = (size.height / rowH).ceil();
    for (var c = 0; c < cols; c++) {
      // kecepatan & fase berbeda tiap kolom (deterministik)
      final seed = (c * 7919) % 97;
      final speed = 0.6 + (seed % 7) / 7;
      final head = ((t * speed * rows * 2 + seed * 3) % (rows + 14)).floor();
      for (var k = 0; k < 14; k++) {
        final row = head - k;
        if (row < 0 || row > rows) continue;
        final gi = (seed + row * 13 + (t * 30).floor() * (k == 0 ? 1 : 0)) % _glyphs.length;
        final level = k == 0 ? 0 : (k < 5 ? 1 : 2);
        _glyph(_glyphs[gi], level).paint(canvas, Offset(c * colW, row * rowH));
      }
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => old.t != t;
}

/// Garis scan tipis + pita terang yang turun pelan.
class _ScanPainter extends CustomPainter {
  _ScanPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = const Color(0x0AFFFFFF);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    final y = ((t * 2) % 1) * (size.height + 120) - 60;
    final band = Rect.fromLTWH(0, y, size.width, 60);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_neon.withValues(alpha: 0), _neon.withValues(alpha: 0.07), _neon.withValues(alpha: 0)],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.t != t;
}
