import 'package:flutter/animation.dart';
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

/// Versi [DecorTick] berbentuk `Animation<double>`, untuk widget/painter yang
/// menerima animasi (bukan sekadar Listenable) dan membaca `.value`-nya.
/// Nilai dan status sama persis dengan [parent]; hanya pemberitahuan
/// "gambar ulang" yang dibatasi ke [DecorTick.fps].
///
/// ```dart
/// late final Animation<double> _loopTick = DecorAnimation(_loop);
/// ```
class DecorAnimation extends Animation<double> {
  DecorAnimation(this.parent) : _tick = DecorTick(parent);

  final Animation<double> parent;
  final DecorTick _tick;

  @override
  double get value => parent.value;

  @override
  AnimationStatus get status => parent.status;

  @override
  void addListener(VoidCallback listener) => _tick.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _tick.removeListener(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) => parent.addStatusListener(listener);

  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      parent.removeStatusListener(listener);
}
