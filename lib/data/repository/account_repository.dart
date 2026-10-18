import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_config.dart';
import '../local/premium_status_cache.dart';
import '../models/account_models.dart';

/// Data akun untuk kartu profil Beranda. Backend sama dengan Zenime
/// (Supabase Edge Functions, uid dikirim di body seperti `zenime-check-premium`).
/// Port PremiumRepository.checkPremiumStatus / getProfileIdentity dan
/// CoinRepository.getBalance. Semua best-effort: gagal = nilai default,
/// sama seperti `getOrNull() ?: default` di HomeViewModel.kt.
class AccountRepository {
  AccountRepository(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>?> _post(String function, String firebaseUid) async {
    // Sertakan Firebase ID Token kalau ada, supaya function yang nanti
    // mewajibkan token (anti IDOR) tetap jalan. Gagal ambil token = tanpa header.
    Options? options;
    if (FirebaseConfig.ready) {
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null && token.isNotEmpty) {
          options = Options(headers: {'Authorization': 'Bearer $token'});
        }
      } catch (_) {}
    }
    final res = await _dio.post<dynamic>(
      'functions/v1/$function',
      data: {'firebase_uid': firebaseUid},
      options: options,
    );
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// `zenime-check-premium` -> is_premium + expires_at.
  ///
  /// Untuk akun yang sedang login, hasil sukses disimpan ke
  /// [PremiumStatusCache]; kalau cek live gagal karena jaringan (offline,
  /// timeout, 5xx) dipakai fallback cache bertanda tangan (port Zenime), bukan
  /// langsung dianggap non-premium. Penolakan server (4xx) TIDAK memakai cache.
  Future<PremiumStatus> getPremiumStatus(String firebaseUid) async {
    if (firebaseUid.isEmpty) return const PremiumStatus();
    final isMe = FirebaseConfig.ready &&
        FirebaseAuth.instance.currentUser?.uid == firebaseUid;
    try {
      final data = await _post('zenime-check-premium', firebaseUid);
      if (data == null) return const PremiumStatus();
      final status = PremiumStatus.fromJson(data);
      if (isMe) {
        unawaited(PremiumStatusCache.save(firebaseUid, status.isPremium, status.expiresAt));
      }
      return status;
    } catch (e) {
      if (isMe && _isNetworkFailure(e)) {
        final cached = await PremiumStatusCache.getValidOffline(firebaseUid);
        if (cached != null) {
          return PremiumStatus(isPremium: cached.isPremium, expiresAt: cached.expiresAt);
        }
      }
      return const PremiumStatus();
    }
  }

  static bool _isNetworkFailure(Object e) {
    if (e is! DioException) return true;
    if (e.type == DioExceptionType.badResponse) {
      return (e.response?.statusCode ?? 0) >= 500;
    }
    return true;
  }

  /// `zenime-get-code` -> zenime_code + user_number.
  Future<ProfileIdentity> getProfileIdentity(String firebaseUid) async {
    if (firebaseUid.isEmpty) return const ProfileIdentity();
    try {
      final data = await _post('zenime-get-code', firebaseUid);
      return data == null ? const ProfileIdentity() : ProfileIdentity.fromJson(data);
    } catch (_) {
      return const ProfileIdentity();
    }
  }

  /// `zenime-get-coin-balance` -> balance (saldo ZCoin). Gagal = 0.
  Future<int> getCoinBalance(String firebaseUid) async {
    if (firebaseUid.isEmpty) return 0;
    try {
      final data = await _post('zenime-get-coin-balance', firebaseUid);
      return (data?['balance'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
