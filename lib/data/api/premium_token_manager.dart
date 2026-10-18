import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_config.dart';

/// Token premium bertanda tangan SERVER (edge function `zenime-premium-token`).
/// Port PremiumTokenManager.kt.
///
/// Ini inti anti-mod: keputusan "boleh nonton donghua atau nggak" diambil
/// server, bukan flag isPremium di app. Token cuma dikasih ke akun yang
/// beneran premium, disimpan di memori saja (tidak ditulis ke disk), dan
/// umurnya pendek.
class PremiumTokenManager {
  PremiumTokenManager(this._supabase);

  /// Dio Supabase (header `apikey` sudah terpasang).
  final Dio _supabase;

  String? _token;
  String? _tokenUid;
  int _expiresAtMs = 0;
  Future<String?>? _inflight;

  void invalidate() {
    _token = null;
    _tokenUid = null;
    _expiresAtMs = 0;
  }

  /// Token valid, atau null kalau belum login / bukan premium / gagal ambil.
  Future<String?> get() async {
    if (!FirebaseConfig.ready) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final cached = _cached(user.uid);
    if (cached != null) return cached;
    // Satu request sekaligus (setara Mutex di Kotlin): pemanggil lain ikut menunggu.
    return _inflight ??= _fetch(user).whenComplete(() => _inflight = null);
  }

  Future<String?> _fetch(User user) async {
    try {
      final idToken = await user.getIdToken(false);
      if (idToken == null || idToken.isEmpty) return null;
      final res = await _supabase.post<dynamic>(
        'functions/v1/zenime-premium-token',
        data: <String, String>{},
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      final data = res.data;
      if (data is! Map) return null;
      final isPremium = data['is_premium'] == true;
      final t = data['token'];
      if (isPremium && t is String && t.isNotEmpty) {
        _token = t;
        _tokenUid = user.uid;
        final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 1800;
        _expiresAtMs = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
        return t;
      }
      invalidate();
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _cached(String uid) {
    final t = _token;
    if (t == null) return null;
    // Sisakan 60 detik supaya tidak terpakai pas hampir kadaluarsa.
    final alive = DateTime.now().millisecondsSinceEpoch < _expiresAtMs - 60000;
    return (_tokenUid == uid && alive) ? t : null;
  }
}
