import 'package:shared_preferences/shared_preferences.dart';

/// Batas ganti foto profil / banner pakai GIF: maks [maxPerDay] kali per hari
/// (gabungan pp + banner), per akun, reset tiap ganti hari (waktu HP).
///
/// Catatan: disimpan lokal di HP, jadi hanya pembatas di sisi app. Kalau mau
/// anti-bypass (hapus data app / ganti HP) harus dicek di server.
class GifQuota {
  GifQuota._();

  static const int maxPerDay = 2;

  static String _key(String uid) => 'gif_quota_$uid';

  static String _today() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  /// Sisa jatah GIF hari ini.
  static Future<int> remaining(String uid) async {
    final used = await _used(uid);
    final left = maxPerDay - used;
    return left < 0 ? 0 : left;
  }

  /// Panggil SETELAH upload GIF berhasil.
  static Future<void> consume(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final used = await _used(uid);
    await prefs.setString(_key(uid), '${_today()}|${used + 1}');
  }

  static Future<int> _used(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(uid));
    if (raw == null) return 0;
    final parts = raw.split('|');
    if (parts.length != 2 || parts[0] != _today()) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }
}
