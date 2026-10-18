/// Model Panel Admin. Port AdminModels.kt (Zenime). Role disimpan sebagai
/// String ('developer' | 'admin' | 'moderator'); konversi ke ZenimeRole
/// dilakukan di layer UI (lihat `ZenimeRole.fromValue` di role_badges.dart).

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Teks pengganti kalau user belum punya username (UID Firebase sengaja tidak ditampilkan).
const String adminNoUsername = 'Tanpa username';

/// Role user yang sedang login (zenime-admin-get-role). role null = user biasa.
class AdminMyRole {
  const AdminMyRole({this.role, this.badgeColor});

  final String? role;
  final String? badgeColor;

  factory AdminMyRole.fromJson(Map<String, dynamic> j) => AdminMyRole(
        role: j['role'] as String?,
        badgeColor: j['badge_color'] as String?,
      );
}

/// Satu baris di zenime-admin-list-roles (tab "Pemegang Role").
class AdminRoleEntry {
  const AdminRoleEntry({
    required this.firebaseUid,
    required this.role,
    this.badgeColor,
    this.assignedBy = '',
    this.createdAt = '',
    this.username,
    this.avatarUrl,
  });

  final String firebaseUid;
  final String role;
  final String? badgeColor;
  final String assignedBy;
  final String createdAt;
  final String? username;
  final String? avatarUrl;

  /// Username untuk ditampilkan.
  String get displayName => _blank(username) ? adminNoUsername : username!;

  /// Salinan dengan username/avatar yang kosong diisi dari profil chat.
  AdminRoleEntry withProfile({String? username, String? avatarUrl}) => AdminRoleEntry(
        firebaseUid: firebaseUid,
        role: role,
        badgeColor: badgeColor,
        assignedBy: assignedBy,
        createdAt: createdAt,
        username: _blank(this.username) ? username : this.username,
        avatarUrl: _blank(this.avatarUrl) ? avatarUrl : this.avatarUrl,
      );

  factory AdminRoleEntry.fromJson(Map<String, dynamic> j) => AdminRoleEntry(
        firebaseUid: (j['firebase_uid'] as String?) ?? '',
        role: (j['role'] as String?) ?? '',
        badgeColor: j['badge_color'] as String?,
        assignedBy: (j['assigned_by'] as String?) ?? '',
        createdAt: (j['created_at'] as String?) ?? '',
        username: j['username'] as String?,
        avatarUrl: j['avatar_url'] as String?,
      );
}

/// Satu baris di zenime-admin-list-users (tab "Semua User").
class AdminUser {
  const AdminUser({
    required this.firebaseUid,
    this.username,
    this.avatarUrl,
    this.zenimeCode,
    this.userNumber,
    this.lastDeviceId,
    this.role,
    this.badgeColor,
    this.bannedAccount = false,
    this.bannedDevice = false,
  });

  final String firebaseUid;
  final String? username;
  final String? avatarUrl;
  final String? zenimeCode;
  final int? userNumber;
  final String? lastDeviceId;
  final String? role;
  final String? badgeColor;
  final bool bannedAccount;
  final bool bannedDevice;

  /// Username untuk ditampilkan.
  String get displayName => _blank(username) ? adminNoUsername : username!;

  /// Salinan dengan username/avatar yang kosong diisi dari profil chat.
  AdminUser withProfile({String? username, String? avatarUrl}) => AdminUser(
        firebaseUid: firebaseUid,
        username: _blank(this.username) ? username : this.username,
        avatarUrl: _blank(this.avatarUrl) ? avatarUrl : this.avatarUrl,
        zenimeCode: zenimeCode,
        userNumber: userNumber,
        lastDeviceId: lastDeviceId,
        role: role,
        badgeColor: badgeColor,
        bannedAccount: bannedAccount,
        bannedDevice: bannedDevice,
      );

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        firebaseUid: (j['firebase_uid'] as String?) ?? '',
        username: j['username'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        zenimeCode: j['zenime_code'] as String?,
        userNumber: (j['user_number'] as num?)?.toInt(),
        lastDeviceId: j['last_device_id'] as String?,
        role: j['role'] as String?,
        badgeColor: j['badge_color'] as String?,
        bannedAccount: j['banned_account'] == true,
        bannedDevice: j['banned_device'] == true,
      );
}
