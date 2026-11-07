import 'package:flutter/foundation.dart';

/// Pembatas frame untuk animasi dekorasi yang berulang terus-menerus
/// (badge level/clan/role, border, kilau kartu).
///
/// Animasinya TIDAK dimatikan dan tidak diubah: controller tetap berjalan
/// dengan durasi yang sama. Bedanya, badge hanya digambar ulang paling banyak
/// [fps] kali per detik, bukan tiap frame layar (60/90/120 Hz). Semua badge
/// memakai jam yang sama, jadi mereka berganti gambar di frame layar yang sama
/// dan frame di antaranya cukup memakai gambar lama (RepaintBoundary).
/// Di layar 120 Hz, kerja gambar badge turun sekitar 75%; di 60 Hz sekitar 50%.
///
/// Pakai sebagai `animation:` di AnimatedBuilder, dibuat SEKALI per State:
/// ```dart
/// late final Listenable _tick = DecorTick(_c);
/// AnimatedBuilder(animation: _tick, builder: ...)
/// ```
/// Animasi pendek yang harus mulus (intro, transisi, gestur) jangan dilewatkan
/// ke sini; gabungkan saja: `Listenable.merge([DecorTick(_c), _intro])`.
class DecorTick extends Listenable {
  DecorTick(this._source);

  /// Frame rate gambar ulang dekorasi. Naikkan kalau kurang halus.
  static const int fps = 30;

  static const int _bucketMicros = 1000000 ~/ fps;
  static final Stopwatch _clock = Stopwatch()..start();

  final Listenable _source;
  final Map<VoidCallback, VoidCallback> _wrapped = <VoidCallback, VoidCallback>{};

  @override
  void addListener(VoidCallback listener) {
    var lastBucket = -1;
    void filtered() {
      final bucket = _clock.elapsedMicroseconds ~/ _bucketMicros;
      if (bucket == lastBucket) return;
      lastBucket = bucket;
      listener();
    }

    final old = _wrapped[listener];
    if (old != null) _source.removeListener(old);
    _wrapped[listener] = filtered;
    _source.addListener(filtered);
  }

  @override
  void removeListener(VoidCallback listener) {
    final filtered = _wrapped.remove(listener);
    if (filtered != null) _source.removeListener(filtered);
  }
}
