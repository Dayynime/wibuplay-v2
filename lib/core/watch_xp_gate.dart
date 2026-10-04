/// Port WatchXpGate.kt. Penentu kapan boleh kirim satu heartbeat XP (1 menit).
///
/// Dipanggil player TIAP DETIK selama video beneran playing (bukan pause,
/// buffering, atau app di background). Setelah 60 detik aktif terkumpul,
/// [onActiveSecond] mengembalikan true sekali.
///
/// Server tetap yang berwenang membatasi XP; gate ini cuma mencegah client
/// mengirim berlebihan.
class WatchXpGate {
  WatchXpGate._();

  static const int _ownerTimeoutMs = 3000;
  static const int _heartbeatSeconds = 60;
  static const int _minGrantIntervalMs = 55000;

  static final Stopwatch _clock = Stopwatch()..start();

  static Object? _owner;
  static int _ownerLastTickAt = 0;
  static int _seconds = 0;
  static int? _lastGrantAt;

  /// [token] identitas pemutar (pakai `this` dari State-nya).
  /// Return true kalau sekarang boleh kirim satu heartbeat 1 menit.
  static bool onActiveSecond(Object token) {
    final now = _clock.elapsedMilliseconds;
    if (!identical(_owner, token)) {
      // Ada pemutar lain yang masih aktif menghitung -> yang ini tidak dihitung.
      if (_owner != null && now - _ownerLastTickAt < _ownerTimeoutMs) return false;
      _owner = token;
    }
    _ownerLastTickAt = now;

    _seconds++;
    if (_seconds < _heartbeatSeconds) return false;
    _seconds = 0;

    final last = _lastGrantAt;
    if (last != null && now - last < _minGrantIntervalMs) return false;
    _lastGrantAt = now;
    return true;
  }

  /// Panggil saat pemutar dilepas, supaya pemutar lain bisa jadi pemilik.
  static void release(Object token) {
    if (identical(_owner, token)) _owner = null;
  }
}
