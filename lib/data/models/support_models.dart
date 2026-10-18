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

/// Satu baris Top Giver (total hari Premium yang diberikan, sepanjang masa).
class TopGiver {
  const TopGiver({
    required this.rank,
    required this.firebaseUid,
    required this.username,
    required this.days,
    this.avatarUrl,
    this.userNumber,
    this.usernameColor,
  });

  final int rank;
  final String firebaseUid;
  final String username;
  final int days;
  final String? avatarUrl;
  final int? userNumber;
  final String? usernameColor;

  factory TopGiver.fromJson(Map<String, dynamic> j, int rank) => TopGiver(
        rank: rank,
        firebaseUid: (j['firebase_uid'] as String?) ?? '',
        username: ((j['username'] as String?) ?? '').trim().isEmpty
            ? 'Pengguna'
            : (j['username'] as String).trim(),
        days: (j['days'] as num?)?.toInt() ?? 0,
        avatarUrl: j['avatar_url'] as String?,
        userNumber: (j['user_number'] as num?)?.toInt(),
        usernameColor: j['username_color'] as String?,
      );
}

/// Top Giver + data badge (clan & level) untuk ditampilkan.
class TopGiversData {
  const TopGiversData({required this.givers, this.clanTags = const {}, this.levels = const {}});

  final List<TopGiver> givers;
  final Map<String, String> clanTags;
  final Map<String, int> levels;
}
