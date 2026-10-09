import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

import 'firebase_config.dart';

/// Pop up pengumuman in-app (port AnnouncementPopup di RemoteConfigManager.kt).
/// [id] menandai "popup ini sudah pernah dilihat"; ganti `popup_id` di Console
/// tiap mau menampilkan popup BARU.
class AnnouncementData {
  const AnnouncementData({
    required this.id,
    required this.title,
    required this.message,
    required this.buttonText,
    required this.buttonUrl,
    required this.footnote,
    required this.repeat,
  });

  final String id;
  final String title;
  final String message;
  final String buttonText;
  final String buttonUrl;
  final String footnote;

  /// true = muncul lagi tiap app dibuka; false = sekali saja (permanen).
  final bool repeat;

  /// Hanya http/https: URL datang dari Remote Config, jangan sampai memicu
  /// skema aneh (intent:, file:, dll).
  bool get hasAction {
    if (buttonText.isEmpty) return false;
    final u = buttonUrl.toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  @override
  bool operator ==(Object other) =>
      other is AnnouncementData &&
      other.id == id &&
      other.title == title &&
      other.message == message &&
      other.buttonText == buttonText &&
      other.buttonUrl == buttonUrl &&
      other.footnote == footnote &&
      other.repeat == repeat;

  @override
  int get hashCode =>
      Object.hash(id, title, message, buttonText, buttonUrl, footnote, repeat);
}

/// Status maintenance dari Remote Config (port maintenance_* di Zenime).
class MaintenanceInfo {
  const MaintenanceInfo({required this.title, required this.message});

  final String title;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is MaintenanceInfo && other.title == title && other.message == message;

  @override
  int get hashCode => Object.hash(title, message);
}

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

  // Base URL API donghua (Anichin). Parameter TERPISAH dari api_base_url.
  static const String _keyAnichinBaseUrl = 'anichin_base_url';

  // Header Referer buat API/gambar/download Animein. TANPA fallback hardcode.
  static const String _keyApiReferer = 'api_referer';

  // Pop up pengumuman (parameter sama dengan Zenime).
  static const String _keyPopupEnabled = 'popup_enabled';
  static const String _keyPopupId = 'popup_id';
  static const String _keyPopupTitle = 'popup_title';
  static const String _keyPopupMessage = 'popup_message';
  static const String _keyPopupButtonText = 'popup_button_text';
  static const String _keyPopupButtonUrl = 'popup_button_url';
  static const String _keyPopupFootnote = 'popup_footnote';
  static const String _keyPopupRepeat = 'popup_repeat';
  // Mode maintenance: blokir total app tanpa rilis versi baru.
  //   maintenance_mode     (Boolean) saklar utama
  //   maintenance_title    (String)  judul, kosong = pakai default
  //   maintenance_message  (String)  isi pesan, kosong = pakai default
  static const String _keyMaintenanceMode = 'maintenance_mode';
  static const String _keyMaintenanceTitle = 'maintenance_title';
  static const String _keyMaintenanceMessage = 'maintenance_message';
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
    syncMaintenance();
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

  /// Base URL API Anichin (donghua), murni dari Remote Config parameter
  /// `anichin_base_url`. Sama seperti [baseUrl]: null kalau kosong / belum
  /// pernah fetch sukses, TIDAK ada fallback hardcode.
  static String? get anichinBaseUrl {
    final rc = _instance;
    if (rc == null) return null;
    final v = rc.getString(_keyAnichinBaseUrl).trim();
    if (v.isEmpty) return null;
    return v.endsWith('/') ? v : '$v/';
  }

  /// Referer API Animein, murni dari Remote Config `api_referer`. Sama seperti
  /// [baseUrl]: null kalau kosong / belum pernah fetch sukses, TIDAK ada
  /// fallback hardcode. null = header Referer tidak dikirim.
  static String? get apiReferer {
    final rc = _instance;
    if (rc == null) return null;
    final v = rc.getString(_keyApiReferer).trim();
    return v.isEmpty ? null : v;
  }

  /// Status maintenance yang sedang berlaku (null = normal). UI cukup
  /// mendengarkan notifier ini; isinya diperbarui tiap fetch/activate dan
  /// tiap update real-time dari Console.
  static final ValueNotifier<MaintenanceInfo?> maintenance =
      ValueNotifier<MaintenanceInfo?>(null);

  static MaintenanceInfo? _readMaintenance() {
    final rc = _instance;
    if (rc == null || !rc.getBool(_keyMaintenanceMode)) return null;
    final title = rc.getString(_keyMaintenanceTitle).replaceAll(r'\n', '\n').trim();
    final message = rc.getString(_keyMaintenanceMessage).replaceAll(r'\n', '\n').trim();
    return MaintenanceInfo(
      title: title.isEmpty ? 'Sedang Maintenance' : title,
      message: message.isEmpty
          ? 'Server sedang dalam perbaikan. Wibuplay akan kembali normal sebentar lagi.'
          : message,
    );
  }

  /// Baca ulang status maintenance dari config yang sedang aktif.
  static void syncMaintenance() {
    final v = _readMaintenance();
    if (v != maintenance.value) maintenance.value = v;
  }

  static StreamSubscription<RemoteConfigUpdate>? _maintenanceSub;

  /// Pantau maintenance_* secara REAL-TIME selama app hidup: begitu kamu
  /// Publish di Console, [maintenance] berubah dan layar maintenance muncul
  /// (atau hilang) di user yang sedang membuka app, tanpa restart / relog.
  static void watchMaintenance() {
    if (_maintenanceSub != null) return;
    _maintenanceSub = listenUpdates(syncMaintenance);
    syncMaintenance();
  }

  /// Pop up yang sedang aktif, atau null kalau saklar `popup_enabled` OFF /
  /// judul dan isi sama-sama kosong.
  static AnnouncementData? currentPopup() {
    final rc = _instance;
    if (rc == null) return null;
    if (!rc.getBool(_keyPopupEnabled)) return null;
    final title = rc.getString(_keyPopupTitle).trim();
    // Ketik \n (backslash + huruf n) di Console buat ganti baris.
    final message = rc.getString(_keyPopupMessage).replaceAll(r'\n', '\n').trim();
    if (title.isEmpty && message.isEmpty) return null;
    final id = rc.getString(_keyPopupId).trim();
    return AnnouncementData(
      id: id.isEmpty ? '$title|$message'.hashCode.toString() : id,
      title: title,
      message: message,
      buttonText: rc.getString(_keyPopupButtonText).trim(),
      buttonUrl: rc.getString(_keyPopupButtonUrl).trim(),
      footnote: rc.getString(_keyPopupFootnote).replaceAll(r'\n', '\n').trim(),
      repeat: rc.getBool(_keyPopupRepeat),
    );
  }

  /// Dengar update Remote Config REAL-TIME (di-push server begitu Publish di
  /// Console, tidak kena cache 1 jam). Config baru di-activate dulu, baru
  /// [onUpdated] dipanggil. Batalkan subscription-nya saat tidak dipakai.
  static StreamSubscription<RemoteConfigUpdate>? listenUpdates(
    void Function() onUpdated,
  ) {
    final rc = _instance;
    if (rc == null) return null;
    try {
      return rc.onConfigUpdated.listen(
        (_) async {
          try {
            await rc.activate();
          } catch (_) {}
          onUpdated();
        },
        onError: (_) {},
      );
    } catch (_) {
      return null;
    }
  }
}
