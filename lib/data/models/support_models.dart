/// Satu baris Top Support (hasil Edge Function `zenime-top-supporters`,
/// donatur). Port TopSupporter dari Zenime.
class TopSupporter {
  const TopSupporter({
    required this.rank,
    required this.name,
    this.avatarUrl,
    this.usernameColor,
    required this.totalAmount,
    this.donationCount = 0,
    this.isLinked = false,
    this.firebaseUid,
  });

  final int rank;
  final String name;
  final String? avatarUrl;

  /// Warna username (hex) kalau donasi terhubung ke akun yang punya warna.
  final String? usernameColor;
  final int totalAmount;
  final int donationCount;

  /// true = donasi sudah terhubung ke akun Zenime (nama/foto dari akun).
  final bool isLinked;

  /// UID akun yang terhubung -- hanya terisi kalau Edge Function top-supporters
  /// mengirim `firebase_uid`. Dipakai untuk membuka profil publik donatur.
  final String? firebaseUid;

  factory TopSupporter.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] as String?)?.trim();
    return TopSupporter(
      rank: (j['rank'] as num?)?.toInt() ?? 0,
      name: (name == null || name.isEmpty) ? 'Anonim' : name,
      avatarUrl: j['avatar_url'] as String?,
      usernameColor: j['username_color'] as String?,
      totalAmount: (j['total_amount'] as num?)?.toInt() ?? 0,
      donationCount: (j['donation_count'] as num?)?.toInt() ?? 0,
      isLinked: j['is_linked'] == true,
      firebaseUid: j['firebase_uid'] as String?,
    );
  }
}
