import 'package:dio/dio.dart';

import '../models/clan_chat_models.dart';
import 'authed_function.dart';

/// Chat clan lewat Edge Function `clan-chat`. Tidak ada akses langsung ke
/// tabel; clan target ditentukan SERVER dari keanggotaan user (bukan dari
/// parameter), dan UID pengirim diambil dari token.
class ClanChatRepository {
  ClanChatRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'clan-chat';

  /// [afterId] null/0 = muat 50 pesan terakhir; selain itu hanya pesan baru.
  Future<ClanChatPage> list({int? afterId}) async {
    final d = await callAuthedFunction(_dio, _fn, {
      'action': 'list',
      if (afterId != null && afterId > 0) 'after_id': afterId,
    });
    if (d is! Map) return const ClanChatPage(messages: [], deletedIds: {});
    final msgs = (d['messages'] is List ? d['messages'] as List : const [])
        .map(ClanMessage.tryParse)
        .whereType<ClanMessage>()
        .toList();
    final del = (d['deleted_ids'] is List ? d['deleted_ids'] as List : const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toSet();
    return ClanChatPage(messages: msgs, deletedIds: del);
  }

  Future<ClanMessage> send(String text, {int? replyToId}) async {
    final d = await callAuthedFunction(_dio, _fn, {
      'action': 'send',
      'text': text,
      if (replyToId != null) 'reply_to_id': replyToId,
    });
    final m = ClanMessage.tryParse(d);
    if (m == null) throw Exception('Server tidak mengembalikan pesan');
    return m;
  }

  Future<void> delete(int id) async {
    await callAuthedFunction(_dio, _fn, {'action': 'delete', 'id': id});
  }
}
