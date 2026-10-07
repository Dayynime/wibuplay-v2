import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/remote_config_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../app_routes.dart';
import '../../components/mini_player.dart';

/// Pembungkus di MaterialApp.builder (di ATAS Navigator): begitu
/// `maintenance_mode` aktif, [MaintenanceScreen] menutup SELURUH app, termasuk
/// halaman yang sedang terbuka (player, detail, dst). Status datang real-time
/// dari Remote Config (lihat RemoteConfigManager.watchMaintenance), jadi tidak
/// perlu restart atau login ulang.
class MaintenanceOverlay extends StatefulWidget {
  const MaintenanceOverlay({super.key});

  @override
  State<MaintenanceOverlay> createState() => _MaintenanceOverlayState();
}

class _MaintenanceOverlayState extends State<MaintenanceOverlay> {
  MaintenanceInfo? _last;

  @override
  void initState() {
    super.initState();
    _last = RemoteConfigManager.maintenance.value;
    RemoteConfigManager.maintenance.addListener(_onChanged);
  }

  @override
  void dispose() {
    RemoteConfigManager.maintenance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final now = RemoteConfigManager.maintenance.value;
    final turnedOn = _last == null && now != null;
    _last = now;
    if (turnedOn) _stopEverything();
  }

  /// Tutup semua halaman di atas Beranda lalu hentikan mini player, supaya
  /// tidak ada video/audio yang terus jalan di balik layar maintenance.
  void _stopEverything() {
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    MiniPlayerManager.instance.close();
    // Player yang sedang di-pop bisa menitipkan videonya ke mini player saat
    // dispose; tutup sekali lagi setelah animasi pop selesai.
    Future<void>.delayed(
      const Duration(milliseconds: 450),
      MiniPlayerManager.instance.close,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MaintenanceInfo?>(
      valueListenable: RemoteConfigManager.maintenance,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        return Positioned.fill(
          child: MaintenanceScreen(title: info.title, message: info.message),
        );
      },
    );
  }
}

/// Layar satu-satunya saat maintenance (port MaintenanceScreen.kt): tidak ada
/// tombol skip. Cek ulang otomatis tiap [autoRetrySeconds] detik sebagai
/// cadangan real-time; tombol "Coba Sekarang" memaksa fetch ke server.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({
    super.key,
    required this.title,
    required this.message,
    this.autoRetrySeconds = 20,
  });

  final String title;
  final String message;
  final int autoRetrySeconds;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
  late final AnimationController _orbit =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);

  late int _secondsLeft = widget.autoRetrySeconds;
  Timer? _timer;
  bool _busy = false;
  bool _stillDown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _busy) return;
      if (_secondsLeft <= 1) {
        _retry(manual: false);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ring.dispose();
    _orbit.dispose();
    _pulse.dispose();
    _blink.dispose();
    super.dispose();
  }

  Future<void> _retry({required bool manual}) async {
    if (_busy) return;
    setState(() => _busy = true);
    await RemoteConfigManager.forceRefresh();
    // Kalau maintenance sudah dimatikan, overlay ini ikut dicopot (state-nya
    // di-dispose), jadi hanya perlu update UI kalau masih tampil.
    if (!mounted) return;
    setState(() {
      _busy = false;
      _secondsLeft = widget.autoRetrySeconds;
      if (manual) _stillDown = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.accentViolet;
    return Material(
      color: AppColors.backgroundDark,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 188,
                height: 188,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Container(
                        width: 188,
                        height: 188,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withValues(alpha: 0.18 + 0.24 * _pulse.value),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    RotationTransition(
                      turns: _ring,
                      child: const CustomPaint(
                        size: Size(168, 168),
                        painter: _RingPainter(accent),
                      ),
                    ),
                    RotationTransition(
                      turns: ReverseAnimation(_orbit),
                      child: const SizedBox(
                        width: 168,
                        height: 168,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: _GlowDot(size: 10, color: accent),
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) => Transform.scale(
                        scale: 0.94 + 0.14 * _pulse.value,
                        child: child,
                      ),
                      child: Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceDark,
                          border: Border.all(color: AppColors.surfaceElevated),
                        ),
                        child: const Icon(Icons.hub_rounded, size: 46, color: accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _blink,
                      builder: (_, __) => Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.25 + 0.75 * _blink.value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'SERVER OFFLINE',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : () => _retry(manual: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor: accent.withValues(alpha: 0.5),
                    shape: const StadiumBorder(),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Coba Sekarang',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _stillDown && !_busy
                    ? 'Masih maintenance. Cek ulang otomatis dalam $_secondsLeft dtk'
                    : 'Cek ulang otomatis dalam $_secondsLeft dtk',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowDot extends StatelessWidget {
  const _GlowDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

/// Cincin putus-putus dengan gradien sapuan (ekor memudar), diputar dari luar.
class _RingPainter extends CustomPainter {
  const _RingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.9),
          color.withValues(alpha: 0),
        ],
      ).createShader(rect);

    final path = Path()..addOval(rect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 16, metric.length)), paint);
        d += 16 + 12;
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}
