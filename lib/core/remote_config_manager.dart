import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'firebase_config.dart';

/// Port RemoteConfigManager.kt: base URL API dibaca dari Firebase Remote
/// Config (parameter `api_base_url`), project Firebase yang SAMA dengan Zenime.
///
/// SENGAJA TIDAK ADA base URL cadangan di kode. Konsekuensinya:
/// - Parameter `api_base_url` kosong / belum diisi di Console = app tidak bisa
///   akses API sama sekali (dipakai juga sebagai kill-switch dari jarak jauh).
/// - Firebase belum dikonfigurasi (apiKey/appId belum diisi) = sama, API mati.
/// - Setelah pernah fetch sukses sekali, SDK Firebase menyimpan nilai terakhir
///   di device, jadi app tetap jalan offline (cache bawaan SDK, bukan fallback
///   buatan kita).
///
/// Setup di Firebase Console: Remote Config > tambah parameter
/// `api_base_url` (String) berisi host API, lalu Publish.
class RemoteConfigManager {
  RemoteConfigManager._();

  static const String _keyBaseUrl = 'api_base_url';
  static const Duration _fetchTimeout = Duration(seconds: 8);
  static const Duration _minFetchInterval = Duration(hours: 1);

  static FirebaseRemoteConfig? _rc;

  /// null selama Firebase belum siap (belum dikonfigurasi / gagal init).
  static FirebaseRemoteConfig? get _instance {
    if (!FirebaseConfig.ready) return null;
    return _rc ??= FirebaseRemoteConfig.instance;
  }

  static Future<void> _fetch({required Duration minInterval}) async {
    final rc = _instance;
    if (rc == null) return;
    try {
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: _fetchTimeout,
        minimumFetchInterval: minInterval,
      ));
      await rc.fetchAndActivate().timeout(_fetchTimeout + const Duration(seconds: 2));
    } catch (_) {
      // Fetch gagal (offline dll): lanjut pakai nilai fetch sukses terakhir
      // yang di-cache SDK Firebase di device ini.
    }
  }

  /// Fetch + activate (hormati cache 1 jam). Panggil sekali saat app start,
  /// sebelum request API pertama.
  static Future<void> refresh() => _fetch(minInterval: _minFetchInterval);

  /// Paksa fetch ke server, tidak peduli cache 1 jam. Dipakai tombol
  /// "Coba Lagi" supaya perubahan `api_base_url` terbaru langsung kebaca.
  static Future<void> forceRefresh() async {
    await _fetch(minInterval: Duration.zero);
  }

  /// Base URL API saat ini (selalu diakhiri "/"), atau null kalau kosong /
  /// belum pernah fetch sukses. TIDAK ada fallback hardcode.
  static String? get baseUrl {
    final rc = _instance;
    if (rc == null) return null;
    final v = rc.getString(_keyBaseUrl).trim();
    if (v.isEmpty) return null;
    return v.endsWith('/') ? v : '$v/';
  }
}
