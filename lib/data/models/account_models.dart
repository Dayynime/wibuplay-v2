/// Status Premium dari Edge Function `zenime-check-premium`.
/// Port PremiumStatus + PremiumStatusResponse di Zenime.
class PremiumStatus {
  const PremiumStatus({this.isPremium = false, this.expiresAt});

  final bool isPremium;

  /// ISO 8601 dari server (`expires_at`). null = tidak ada / tidak premium.
  final String? expiresAt;

  /// Sisa hari aktif, null kalau [expiresAt] kosong atau formatnya tidak valid.
  int? get daysLeft => daysLeftFromIso(expiresAt);

  factory PremiumStatus.fromJson(Map<String, dynamic> j) => PremiumStatus(
        isPremium: j['is_premium'] == true,
        expiresAt: j['expires_at'] as String?,
      );
}

/// Kode akun + ID urut dari Edge Function `zenime-get-code`.
/// Port ZenimeCodeResponse di Zenime (server membuat kode otomatis kalau belum ada).
class ProfileIdentity {
  const ProfileIdentity({this.zenimeCode, this.userNumber});

  final String? zenimeCode;
  final int? userNumber;

  factory ProfileIdentity.fromJson(Map<String, dynamic> j) => ProfileIdentity(
        zenimeCode: j['zenime_code'] as String?,
        userNumber: (j['user_number'] as num?)?.toInt(),
      );
}

/// Sisa hari dari `expires_at` ISO. Port computeDaysLeft di HomeViewModel.kt:
/// dibulatkan ke bawah, minimal 0. null kalau format tidak valid.
int? daysLeftFromIso(String? iso, {DateTime? now}) {
  if (iso == null || iso.isEmpty) return null;
  final expiresAt = DateTime.tryParse(iso);
  if (expiresAt == null) return null;
  final days = expiresAt.difference(now ?? DateTime.now()).inDays;
  return days < 0 ? 0 : days;
}

/// Format saldo ZCoin ala id-ID: titik sebagai pemisah ribuan (902499 -> "902.499").
String formatZCoin(int balance) {
  final digits = balance.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return balance < 0 ? '-$out' : out.toString();
}
