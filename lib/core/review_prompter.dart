import 'dart:async';

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minta rating Play Store (In-App Review) di momen yang pas, bukan dari tombol.
///
/// Aturan:
///  * minimal sudah menamatkan [_minEpisodes] episode (anime / donghua),
///    atau baru saja menang giveaway;
///  * paling sering sekali tiap [_cooldown], maksimal [_maxAsks] kali;
///  * popup ditampilkan setelah user keluar dari player (tidak memotong
///    tontonan / hitung mundur episode berikutnya).
/// Google sendiri juga membatasi kemunculan popup, jadi tidak dijamin muncul.
class ReviewPrompter {
  ReviewPrompter._();

  static const _kEpisodes = 'rv_episodes';
  static const _kLastAsk = 'rv_last_ask_ms';
  static const _kAsks = 'rv_asks';
  static const int _minEpisodes = 3;
  static const int _maxAsks = 3;
  static const Duration _cooldown = Duration(days: 30);

  static bool _pending = false;
  static bool _busy = false;

  /// Panggil saat satu episode selesai ditonton.
  static Future<void> onEpisodeFinished() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = (p.getInt(_kEpisodes) ?? 0) + 1;
      await p.setInt(_kEpisodes, n);
      if (n >= _minEpisodes && _allowed(p)) _pending = true;
    } catch (_) {}
  }

  /// Panggil saat layar player ditutup: tampilkan popup kalau sedang menunggu.
  static void onPlayerClosed() {
    if (!_pending) return;
    _pending = false;
    // Beri waktu layar detail tampil dulu.
    Timer(const Duration(milliseconds: 900), () => unawaited(_ask()));
  }

  /// Panggil setelah momen menyenangkan (mis. menang giveaway).
  static void onHappyMoment() {
    Timer(const Duration(milliseconds: 1500), () async {
      try {
        final p = await SharedPreferences.getInstance();
        if (_allowed(p)) await _ask();
      } catch (_) {}
    });
  }

  static bool _allowed(SharedPreferences p) {
    if ((p.getInt(_kAsks) ?? 0) >= _maxAsks) return false;
    final last = p.getInt(_kLastAsk) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - last >= _cooldown.inMilliseconds;
  }

  static Future<void> _ask() async {
    if (_busy) return;
    _busy = true;
    try {
      final p = await SharedPreferences.getInstance();
      if (!_allowed(p)) return;
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      await p.setInt(_kLastAsk, DateTime.now().millisecondsSinceEpoch);
      await p.setInt(_kAsks, (p.getInt(_kAsks) ?? 0) + 1);
      await review.requestReview();
    } catch (_) {
      // Tidak tersedia (bukan dari Play Store, dsb.): diam saja.
    } finally {
      _busy = false;
    }
  }
}
