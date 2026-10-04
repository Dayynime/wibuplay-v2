/// Ringkasan clan buat slide Top Leaderboard (baris tabel `clans` di Zenime,
/// cuma kolom yang dipakai).
class ClanSummary {
  const ClanSummary({
    required this.id,
    required this.tag,
    this.photoUrl,
    this.level = 1,
    this.totalXp = 0,
  });

  final String id;
  final String tag;
  final String? photoUrl;
  final int level;
  final int totalXp;

  factory ClanSummary.fromJson(Map<String, dynamic> j) => ClanSummary(
        id: (j['id'] as String?) ?? '',
        tag: (j['tag'] as String?) ?? '',
        photoUrl: j['photo_url'] as String?,
        level: (j['level'] as num?)?.toInt() ?? 1,
        totalXp: (j['total_xp'] as num?)?.toInt() ?? 0,
      );
}
