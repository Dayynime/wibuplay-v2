/// Satu baris Top Support (hasil Edge Function `zenime-top-supporters`,
/// donatur SociaBuzz). Port TopSupporter dari Zenime.
class TopSupporter {
  const TopSupporter({
    required this.rank,
    required this.name,
    this.avatarUrl,
    required this.totalAmount,
    this.donationCount = 0,
  });

  final int rank;
  final String name;
  final String? avatarUrl;
  final int totalAmount;
  final int donationCount;

  factory TopSupporter.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] as String?)?.trim();
    return TopSupporter(
      rank: (j['rank'] as num?)?.toInt() ?? 0,
      name: (name == null || name.isEmpty) ? 'Anonim' : name,
      avatarUrl: j['avatar_url'] as String?,
      totalAmount: (j['total_amount'] as num?)?.toInt() ?? 0,
      donationCount: (j['donation_count'] as num?)?.toInt() ?? 0,
    );
  }
}
