import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../data/repository/notification_repository.dart';
import 'firebase_config.dart';

/// Token push (FCM) HP ini <-> akun yang login.
///
///  - Login  : minta izin notif (Android 13+), ambil token, daftarkan ke server.
///  - Token diperbarui Firebase -> daftar ulang otomatis.
///  - Logout : hapus token dari server SEBELUM sign out (masih punya token
///    login), supaya HP ini tidak lagi menerima notif akun tersebut.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  NotificationRepository? _repo;
  String? _uid;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  bool _busy = false;

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
      // Ditolak pun token tetap didaftarkan: kalau nanti izin dinyalakan
      // dari Pengaturan HP, notif langsung jalan tanpa login ulang.
      await fm.requestPermission();
      final token = await fm.getToken();
      if (token == null || token.isEmpty) return;
      await repo.registerToken(token);
      _uid = uid;
      _token = token;
      _refreshSub ??= fm.onTokenRefresh.listen((t) async {
        _token = t;
        if (_uid == null) return;
        try {
          await _repo?.registerToken(t);
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
    if (repo == null || token == null) return;
    try {
      await repo.unregisterToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('Push: hapus token gagal: $e');
    }
  }
}
