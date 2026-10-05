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

/// Baris tabel `clans` (lengkap) buat halaman Clan.
class Clan {
  const Clan({
    required this.id,
    required this.tag,
    required this.name,
    this.description,
    this.photoUrl,
    this.leaderUid = '',
    this.level = 1,
    this.totalXp = 0,
    this.memberCount = 1,
    this.memberLimit = 30,
  });

  final String id;
  final String tag;
  final String name;
  final String? description;
  final String? photoUrl;
  final String leaderUid;
  final int level;
  final int totalXp;
  final int memberCount;
  final int memberLimit;

  factory Clan.fromJson(Map<String, dynamic> j) => Clan(
        id: (j['id'] as String?) ?? '',
        tag: (j['tag'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        description: j['description'] as String?,
        photoUrl: j['photo_url'] as String?,
        leaderUid: (j['leader_uid'] as String?) ?? '',
        level: (j['level'] as num?)?.toInt() ?? 1,
        totalXp: (j['total_xp'] as num?)?.toInt() ?? 0,
        memberCount: (j['member_count'] as num?)?.toInt() ?? 1,
        memberLimit: (j['member_limit'] as num?)?.toInt() ?? 30,
      );
}

/// Baris tabel `clan_members`.
class ClanMember {
  const ClanMember({
    required this.clanId,
    required this.firebaseUid,
    required this.role,
    this.totalContribution = 0,
    this.joinedAt = '',
  });

  final String clanId;
  final String firebaseUid;
  final String role;
  final int totalContribution;
  final String joinedAt;

  factory ClanMember.fromJson(Map<String, dynamic> j) => ClanMember(
        clanId: (j['clan_id'] as String?) ?? '',
        firebaseUid: (j['firebase_uid'] as String?) ?? '',
        role: (j['role'] as String?) ?? ClanRoles.member,
        totalContribution: (j['total_contribution'] as num?)?.toInt() ?? 0,
        joinedAt: (j['joined_at'] as String?) ?? '',
      );
}

/// Member clan digabung dengan profil chat (username/avatar/ID).
class ClanMemberDisplay {
  const ClanMemberDisplay({
    required this.firebaseUid,
    required this.role,
    required this.totalContribution,
    required this.joinedAt,
    required this.username,
    this.avatarUrl,
    this.userNumber,
  });

  final String firebaseUid;
  final String role;
  final int totalContribution;
  final String joinedAt;
  final String username;
  final String? avatarUrl;
  final int? userNumber;
}

/// Satu baris ranking "Donasi Hari Ini".
class ClanDonationEntry {
  const ClanDonationEntry({
    required this.firebaseUid,
    required this.username,
    this.avatarUrl,
    required this.role,
    required this.amountToday,
    required this.donationCountToday,
  });

  final String firebaseUid;
  final String username;
  final String? avatarUrl;
  final String role;
  final int amountToday;
  final int donationCountToday;
}

/// Hierarki role clan (tinggi -> rendah): Leader > Vice Leader > Admiral >
/// Officer > Member. Officer disimpan di DB sebagai "co_leader".
class ClanRoles {
  ClanRoles._();

  static const String leader = 'leader';
  static const String viceLeader = 'vice_leader';
  static const String admiral = 'admiral';
  static const String officer = 'co_leader';
  static const String member = 'member';

  static const List<String> all = [leader, viceLeader, admiral, officer, member];

  static int rank(String? role) {
    switch (role) {
      case leader:
        return 4;
      case viceLeader:
        return 3;
      case admiral:
        return 2;
      case officer:
        return 1;
      default:
        return 0;
    }
  }

  static String label(String? role) {
    switch (role) {
      case leader:
        return 'LEADER';
      case viceLeader:
        return 'VICE LEADER';
      case admiral:
        return 'ADMIRAL';
      case officer:
        return 'OFFICER';
      default:
        return 'MEMBER';
    }
  }
}

/// Batas XP awal per level clan. PERKIRAAN (sama seperti Zenime): rumus asli
/// ada di server (fungsi donate_to_clan), ini cuma menyocokkan data yang ada.
int clanXpFloor(int level) => 500 * level * (level - 1);

