import 'package:dio/dio.dart';

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
    final res = await _dio.post<dynamic>(
      'functions/v1/$function',
      data: {'firebase_uid': firebaseUid},
    );
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// `zenime-check-premium` -> is_premium + expires_at.
  Future<PremiumStatus> getPremiumStatus(String firebaseUid) async {
    if (firebaseUid.isEmpty) return const PremiumStatus();
    try {
      final data = await _post('zenime-check-premium', firebaseUid);
      return data == null ? const PremiumStatus() : PremiumStatus.fromJson(data);
    } catch (_) {
      return const PremiumStatus();
    }
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
