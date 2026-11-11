import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// State kecerahan + volume untuk gesture swipe vertikal di pemutar
/// (port brightnessLevel/volumeLevel di PlayerScreen.kt Zenime).
///
/// Dimiliki oleh state layar player, bukan oleh layout, supaya nilainya tidak
/// hilang saat pindah portrait <-> fullscreen.
class PlayerLevels extends ChangeNotifier {
  double brightness = 0.5;
  double volume = 0.5;
  bool showBrightness = false;
  bool showVolume = false;

  Timer? _hideTimer;
  bool _touchedBrightness = false;
  bool _disposed = false;

  /// Baca level saat ini sekali di awal, supaya drag pertama mulai dari nilai
  /// yang benar (bukan loncat ke 50%).
  Future<void> init() async {
    try {
      brightness = (await ScreenBrightness.instance.application).clamp(0.0, 1.0).toDouble();
    } catch (_) {}
    try {
      VolumeController.instance.showSystemUI = false;
      volume = (await VolumeController.instance.getVolume()).clamp(0.0, 1.0).toDouble();
    } catch (_) {}
    _notify();
  }

  void begin({required bool left}) {
    _hideTimer?.cancel();
    if (left) {
      showBrightness = true;
    } else {
      showVolume = true;
    }
    _notify();
  }

  /// [fraction] positif = naik. Satu tinggi layar penuh = seluruh rentang.
  void change({required bool left, required double fraction}) {
    if (left) {
      brightness = (brightness + fraction).clamp(0.01, 1.0).toDouble();
      _touchedBrightness = true;
      ScreenBrightness.instance.setApplicationScreenBrightness(brightness).catchError((_) {});
    } else {
      volume = (volume + fraction).clamp(0.0, 1.0).toDouble();
      try {
        VolumeController.instance.setVolume(volume);
      } catch (_) {}
    }
    _notify();
  }

  /// Indikator hilang ~600ms setelah jari diangkat.
  void end() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 600), () {
      showBrightness = false;
      showVolume = false;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hideTimer?.cancel();
    // Kembalikan kecerahan ke pengaturan sistem begitu keluar dari player.
    if (_touchedBrightness) {
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    }
    super.dispose();
  }
}

/// Membungkus area video: swipe vertikal di setengah kiri = kecerahan,
/// setengah kanan = volume. Tap / double-tap / swipe horizontal tetap
/// ditangani widget di dalam/di atasnya.
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({super.key, required this.levels, required this.child});

  final PlayerLevels levels;
  final Widget child;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  bool _left = true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight <= 0 ? 1.0 : c.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (d) {
            _left = d.localPosition.dx < w / 2;
            widget.levels.begin(left: _left);
          },
          onVerticalDragUpdate: (d) {
            widget.levels.change(left: _left, fraction: -d.delta.dy / h);
          },
          onVerticalDragEnd: (_) => widget.levels.end(),
          onVerticalDragCancel: () => widget.levels.end(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              ListenableBuilder(
                listenable: widget.levels,
                builder: (context, _) {
                  final l = widget.levels;
                  return IgnorePointer(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: _LevelIndicator(
                              visible: l.showBrightness,
                              icon: _brightnessIcon(l.brightness),
                              level: l.brightness,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 24),
                            child: _LevelIndicator(
                              visible: l.showVolume,
                              icon: _volumeIcon(l.volume),
                              level: l.volume,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

IconData _brightnessIcon(double level) {
  if (level < 0.15) return Icons.brightness_low;
  if (level < 0.7) return Icons.brightness_medium;
  return Icons.brightness_high;
}

IconData _volumeIcon(double level) {
  if (level <= 0) return Icons.volume_off;
  if (level < 0.5) return Icons.volume_down;
  return Icons.volume_up;
}

/// Pill vertikal: ikon + bar level (gaya pill gesture Wibuplay).
class _LevelIndicator extends StatelessWidget {
  const _LevelIndicator({
    required this.visible,
    required this.icon,
    required this.level,
  });

  final bool visible;
  final IconData icon;
  final double level;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x990B0E14),
          borderRadius: AppShapes.pill,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.textWhite),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              width: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    const ColoredBox(color: Color(0x40FFFFFF), child: SizedBox.expand()),
                    FractionallySizedBox(
                      heightFactor: level.clamp(0.0, 1.0),
                      child: const ColoredBox(
                        color: AppColors.accentViolet,
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(level.clamp(0.0, 1.0) * 100).round()}',
              style: const TextStyle(
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
