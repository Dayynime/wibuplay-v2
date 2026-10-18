import 'package:dio/dio.dart';

import 'authed_function.dart';

/// Alasan laporan (harus sama dengan CHECK di tabel user_reports).
enum ReportReason {
  spam('spam', 'Spam atau iklan'),
  harassment('pelecehan', 'Pelecehan atau perundungan'),
  hate('sara', 'Ujaran kebencian / SARA'),
  sexual('seksual', 'Konten seksual atau tidak pantas'),
  scam('penipuan', 'Penipuan'),
  other('lainnya', 'Lainnya');

  const ReportReason(this.id, this.label);
  final String id;
  final String label;
}

/// Tempat laporan dibuat (harus sama dengan CHECK di tabel user_reports).
enum ReportChannel { global, private, profile, clan, comment }

/// Laporkan, blokir, dan permintaan hapus akun lewat Edge Function
/// `zenime-safety`. UID diambil server dari Firebase ID Token.
class SafetyRepository {
  SafetyRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'zenime-safety';

  Future<void> report({
    required String targetUid,
    required ReportChannel channel,
    required ReportReason reason,
    int? messageId,
    String? messageText,
    String? note,
  }) async {
    await callAuthedFunction(_dio, _fn, {
      'action': 'report',
      'target_uid': targetUid,
      'channel': channel.name,
      'reason': reason.id,
      'message_id': messageId,
      'message_text': messageText,
      'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    });
  }

  Future<void> block(String targetUid) async {
    await callAuthedFunction(_dio, _fn, {'action': 'block', 'target_uid': targetUid});
  }

  Future<void> unblock(String targetUid) async {
    await callAuthedFunction(_dio, _fn, {'action': 'unblock', 'target_uid': targetUid});
  }

  /// Daftar uid yang diblokir user ini, beserta username (kalau ada).
  Future<List<BlockedUser>> listBlocks() async {
    final data = await callAuthedFunction(_dio, _fn, {'action': 'list_blocks'});
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => BlockedUser(
              uid: (e['blocked_uid'] as String?) ?? '',
              username: e['username'] as String?,
              avatarUrl: e['avatar_url'] as String?,
            ))
        .where((b) => b.uid.isNotEmpty)
        .toList();
  }

  /// Ajukan penghapusan akun. Server mencatat permintaan; data dihapus
  /// paling lambat 7 hari kerja (sesuai halaman /delete).
  Future<void> requestAccountDeletion({String? reason}) async {
    await callAuthedFunction(_dio, _fn, {
      'action': 'request_deletion',
      'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    });
  }
}

class BlockedUser {
  const BlockedUser({required this.uid, this.username, this.avatarUrl});

  final String uid;
  final String? username;
  final String? avatarUrl;
}
