/// Baris tabel `user_xp` (sama dengan UserXp di Zenime).
class UserXp {
  const UserXp({required this.firebaseUid, this.totalXp = 0, this.level = 1});

  final String firebaseUid;
  final int totalXp;
  final int level;

  factory UserXp.fromJson(Map<String, dynamic> j) => UserXp(
        firebaseUid: (j['firebase_uid'] as String?) ?? '',
        totalXp: (j['total_xp'] as num?)?.toInt() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? 1,
      );
}

/// Satu baris leaderboard bulanan, sudah digabung profil + status premium.
/// [xp] adalah XP nonton BULAN BERJALAN; [level] kumulatif (tidak ikut reset).
class UserXpDisplay {
  const UserXpDisplay({
    required this.firebaseUid,
    required this.xp,
    required this.level,
    required this.username,
    this.avatarUrl,
    this.clanTag,
    this.isPremium = false,
  });

  final String firebaseUid;
  final int xp;
  final int level;
  final String username;
  final String? avatarUrl;

  /// Tag clan user (null = belum gabung clan).
  final String? clanTag;
  final bool isPremium;
}

class XpProgress {
  const XpProgress({
    required this.xpIntoLevel,
    required this.xpNeededForLevel,
    required this.fraction,
  });

  final int xpIntoLevel;
  final int xpNeededForLevel;
  final double fraction;
}

/// Formula level XP nonton, SAMA PERSIS dengan RPC `add_watch_xp` di server
/// (lihat XpLevelFormula.kt di Zenime). Kalau formula server berubah, ubah
/// di sini juga supaya progress bar tidak salah tampil.
///
/// Lihat totalXpForLevel. Level 1 = 0 XP.
class XpLevelFormula {
  XpLevelFormula._();

  /// Total XP minimal untuk mencapai level [n] (sama dengan server
  /// `level_for_total_xp`): Lv.1-20 rumus lama 100*n*(n-1), mulai Lv.20
  /// (38.000 XP) rata 2.000 XP per level.
  static int totalXpForLevel(int n) {
    if (n <= 1) return 0;
    return n <= 20 ? 100 * n * (n - 1) : 2000 * (n - 1);
  }

  static XpProgress progress(int totalXp, int level) {
    final floor = totalXpForLevel(level);
    final next = totalXpForLevel(level + 1);
    final into = (totalXp - floor) < 0 ? 0 : (totalXp - floor);
    final needed = (next - floor) < 1 ? 1 : (next - floor);
    return XpProgress(
      xpIntoLevel: into,
      xpNeededForLevel: needed,
      fraction: (into / needed).clamp(0.0, 1.0).toDouble(),
    );
  }
}
