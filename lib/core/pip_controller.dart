import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Jembatan ke MainActivity untuk Picture-in-Picture sistem Android
/// (port PipController.kt Zenime). Native-nya ada di android_native/MainActivity.kt.
class PipController {
  PipController._();

  static const MethodChannel _ch = MethodChannel('wibuplay/pip');

  /// True selagi Activity benar-benar dalam mode PiP.
  static final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  static bool _ready = false;

  static void _ensureInit() {
    if (_ready) return;
    _ready = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        isInPip.value = call.arguments == true;
      }
    });
  }

  /// Aktifkan auto-PiP saat user pindah app (hanya selama player memutar).
  static Future<void> setCanEnter(bool enabled) async {
    _ensureInit();
    try {
      await _ch.invokeMethod<void>('setCanEnter', enabled);
    } catch (_) {}
  }

  static Future<void> setAspectRatio(int width, int height) async {
    _ensureInit();
    try {
      await _ch.invokeMethod<void>('setAspectRatio', {'w': width, 'h': height});
    } catch (_) {}
  }

  /// Masuk PiP manual (tombol). Return false kalau tidak didukung / gagal.
  static Future<bool> enter() async {
    _ensureInit();
    try {
      return (await _ch.invokeMethod<bool>('enter', {'force': true})) ?? false;
    } catch (_) {
      return false;
    }
  }
}
