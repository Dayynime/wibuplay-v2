import 'package:shared_preferences/shared_preferences.dart';

import '../../core/integrity_guard.dart';

/// Port PremiumStatusCache.kt (Zenime): status premium terakhir yang sukses
/// diambil dari server, HANYA buat fallback saat cek live gagal (offline /
/// WiFi jelek). Tiga lapis proteksi:
///  0. Tanda tangan HMAC (key AndroidKeyStore): edit manual prefs = tidak valid.
///  1. `expiresAt` user sendiri: sudah lewat = non-premium walau cache segar.
///  2. TTL 3 hari sejak sukses cek terakhir (jaga-jaga revoke manual admin).
/// Cache terikat ke uid, jadi tidak bocor ke akun lain di device yang sama.
class PremiumStatusCache {
  PremiumStatusCache._();

  static const String _kUid = 'premium_cache_uid';
  static const String _kIsPremium = 'premium_cache_is_premium';
  static const String _kExpiresAt = 'premium_cache_expires_at';
  static const String _kCheckedAt = 'premium_cache_last_checked_at';
  static const String _kSig = 'premium_cache_sig';

  static const Duration _ttl = Duration(days: 3);

  static String _payload(String uid, bool isPremium, String? expiresAt, int checkedAt) =>
      '$uid|$isPremium|${expiresAt ?? ''}|$checkedAt';

  /// Simpan hasil cek live yang sukses untuk [uid] (akun yang sedang login).
  static Future<void> save(String uid, bool isPremium, String? expiresAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await IntegrityGuard.hmacSign(_payload(uid, isPremium, expiresAt, now));
      if (sig.isEmpty) return; // tanpa tanda tangan, cache tidak berguna
      await prefs.setString(_kUid, uid);
      await prefs.setBool(_kIsPremium, isPremium);
      if (expiresAt != null) {
        await prefs.setString(_kExpiresAt, expiresAt);
      } else {
        await prefs.remove(_kExpiresAt);
      }
      await prefs.setInt(_kCheckedAt, now);
      await prefs.setString(_kSig, sig);
    } catch (_) {}
  }

  /// Status buat dipakai SAAT cek live gagal. null = cache tidak ada / basi /
  /// tidak valid -> pemanggil WAJIB anggap non-premium.
  static Future<({bool isPremium, String? expiresAt})?> getValidOffline(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kUid) != uid) return null;
      final isPremium = prefs.getBool(_kIsPremium);
      final checkedAt = prefs.getInt(_kCheckedAt);
      if (isPremium == null || checkedAt == null) return null;
      if (!isPremium) return (isPremium: false, expiresAt: null);

      final expiresAtIso = prefs.getString(_kExpiresAt);
      final stored = prefs.getString(_kSig) ?? '';
      final expected =
          await IntegrityGuard.hmacSign(_payload(uid, true, expiresAtIso, checkedAt));
      if (stored.isEmpty || expected.isEmpty || stored != expected) return null;

      final age = DateTime.now().millisecondsSinceEpoch - checkedAt;
      if (age > _ttl.inMilliseconds) return null;

      if (expiresAtIso != null) {
        final exp = DateTime.tryParse(expiresAtIso);
        if (exp != null && DateTime.now().isAfter(exp)) {
          return (isPremium: false, expiresAt: null);
        }
      }
      return (isPremium: true, expiresAt: expiresAtIso);
    } catch (_) {
      return null;
    }
  }

  /// Hapus cache (dipanggil saat logout).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [_kUid, _kIsPremium, _kExpiresAt, _kCheckedAt, _kSig]) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
