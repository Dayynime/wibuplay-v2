import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository/notification_repository.dart';
import 'firebase_config.dart';

/// Token push (FCM) HP ini <-> akun yang login.
///
/// Dibuat seringan mungkin supaya tidak rebutan jaringan dengan data akun
/// saat app baru dibuka:
///  - dijalankan TERTUNDA (dipanggil PushHost beberapa detik setelah app siap);
///  - token cuma dikirim ke server kalau BERUBAH (beda token / beda akun) atau
///    sudah lebih dari 7 hari sejak terakhir didaftarkan. Buka app biasa =
///    0 request ke server untuk push.
///  - Logout: hapus token dari server SEBELUM sign out.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const String _prefKey = 'push_registration_v1'; // "uid|token|epochMs"
  static const Duration _refreshEvery = Duration(days: 7);

  NotificationRepository? _repo;
  String? _uid;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  bool _busy = false;

  Future<bool> _alreadyRegistered(String uid, String token) async {
    try {
      final p = await SharedPreferences.getInstance();
      final parts = (p.getString(_prefKey) ?? '').split('|');
      if (parts.length != 3 || parts[0] != uid || parts[1] != token) return false;
      final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[2]) ?? 0);
      return DateTime.now().difference(at) < _refreshEvery;
    } catch (_) {
      return false;
    }
  }

  Future<void> _remember(String uid, String token) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, '$uid|$token|${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {}
  }

  Future<void> _forget() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefKey);
    } catch (_) {}
  }

  Future<void> _register(String uid, String token) async {
    if (await _alreadyRegistered(uid, token)) return;
    await _repo!.registerToken(token);
    await _remember(uid, token);
  }

  Future<void> syncForUser(NotificationRepository repo, String? uid) async {
    _repo = repo;
    if (!FirebaseConfig.ready) return;
    if (uid == null || uid.isEmpty) {
      _uid = null;
      return;
    }
    if (_uid == uid || _busy) return;
    _busy = true;
    try {
      final fm = FirebaseMessaging.instance;
      // Dialog izin cuma muncul sekali (Android 13+); setelahnya instan.
      await fm.requestPermission();
      final token = await fm.getToken();
      if (token == null || token.isEmpty) return;
      await _register(uid, token);
      _uid = uid;
      _token = token;
      _refreshSub ??= fm.onTokenRefresh.listen((t) async {
        _token = t;
        final u = _uid;
        if (u == null) return;
        try {
          await _register(u, t);
        } catch (e) {
          if (kDebugMode) debugPrint('Push: daftar ulang token gagal: $e');
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Push: sync gagal: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> unregister() async {
    final repo = _repo;
    final token = _token;
    _uid = null;
    await _forget();
    if (repo == null || token == null) return;
    try {
      await repo.unregisterToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('Push: hapus token gagal: $e');
    }
  }
}
