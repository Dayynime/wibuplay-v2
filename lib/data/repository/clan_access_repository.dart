import 'package:dio/dio.dart';

import '../models/clan_models.dart';
import 'authed_function.dart';

/// Undangan clan yang masih menunggu jawaban user.
class ClanInvite {
  const ClanInvite({
    required this.inviteId,
    required this.clanId,
    required this.clanName,
    this.clanTag = '',
    this.photoUrl,
    this.fromName = '',
  });

  final String inviteId;
  final String clanId;
  final String clanName;
  final String clanTag;
  final String? photoUrl;
  final String fromName;

  factory ClanInvite.fromJson(Map<String, dynamic> j) => ClanInvite(
        inviteId: (j['invite_id'] as String?) ?? '',
        clanId: (j['clan_id'] as String?) ?? '',
        clanName: (j['clan_name'] as String?) ?? '',
        clanTag: (j['clan_tag'] as String?) ?? '',
        photoUrl: j['photo_url'] as String?,
        fromName: (j['from_name'] as String?) ?? '',
      );
}

/// Edge Function `clan-access`: mode join, level minimal, dan undangan clan.
/// UID pemanggil diambil server dari Firebase ID Token; semua aturan di SQL.
class ClanAccessRepository {
  ClanAccessRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'clan-access';

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final d = await callAuthedFunction(_dio, _fn, body);
    if (d is! Map) throw Exception('Server tidak merespons');
    return Map<String, dynamic>.from(d);
  }

  /// Ubah mode join & level minimal (leader saja).
  Future<Clan?> updateSettings({
    required String clanId,
    required String joinMode,
    required int minLevel,
  }) async {
    final d = await _call({
      'action': 'settings',
      'clan_id': clanId,
      'join_mode': joinMode,
      'min_level': minLevel,
    });
    final c = d['clan'];
    return c is Map ? Clan.fromJson(Map<String, dynamic>.from(c)) : null;
  }

  /// Undang user ke clan (leader & pengurus).
  Future<void> invite({required String clanId, required String uid}) async {
    await _call({'action': 'invite', 'clan_id': clanId, 'uid': uid});
  }

  /// Jawab undangan. Mengembalikan clan_id.
  Future<String?> respond(String inviteId, {required bool accept}) async {
    final d = await _call({'action': 'invite_respond', 'invite_id': inviteId, 'accept': accept});
    return d['clan_id'] as String?;
  }

  Future<List<ClanInvite>> myInvites() async {
    final d = await _call({'action': 'my_invites'});
    final raw = d['invites'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) ClanInvite.fromJson(Map<String, dynamic>.from(e)),
    ];
  }
}
