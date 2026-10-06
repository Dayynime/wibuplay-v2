import 'package:dio/dio.dart';

import '../models/friend_models.dart';

/// Chat teman (DM) lewat PostgREST, tabel `private_messages` (sama dengan
/// PrivateChatRepository.kt di Zenime).
class PrivateChatRepository {
  PrivateChatRepository(this._dio);

  final Dio _dio;

  static const String _cols = 'id,sender_uid,recipient_uid,message,created_at,read_at,'
      'reply_to_id,reply_to_sender_uid,reply_to_message';

  static final RegExp _safeUid = RegExp(r'^[A-Za-z0-9_-]+$');

  static String _safe(String uid) {
    if (!_safeUid.hasMatch(uid)) throw ArgumentError('uid tidak valid');
    return uid;
  }

  static List<PrivateMessage> _parse(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => PrivateMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Urut lama -> baru (siap dirender dari atas ke bawah).
  Future<List<PrivateMessage>> getConversation(String myUid, String otherUid) async {
    final me = _safe(myUid);
    final other = _safe(otherUid);
    final res = await _dio.get<dynamic>(
      'rest/v1/private_messages',
      queryParameters: {
        'or': '(and(sender_uid.eq.$me,recipient_uid.eq.$other),'
            'and(sender_uid.eq.$other,recipient_uid.eq.$me))',
        'select': _cols,
        'order': 'created_at.desc',
        'limit': 100,
      },
    );
    return _parse(res.data)..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Pesan terbaru yang melibatkan user ini (buat menyusun daftar percakapan).
  Future<List<PrivateMessage>> getRecent(String myUid) async {
    final me = _safe(myUid);
    final res = await _dio.get<dynamic>(
      'rest/v1/private_messages',
      queryParameters: {
        'or': '(sender_uid.eq.$me,recipient_uid.eq.$me)',
        'select': _cols,
        'order': 'created_at.desc',
        'limit': 300,
      },
    );
    return _parse(res.data);
  }

  Future<PrivateMessage> send({
    required String myUid,
    required String otherUid,
    required String text,
    int? replyToId,
    String? replyToSenderUid,
    String? replyToMessage,
  }) async {
    final res = await _dio.post<dynamic>(
      'rest/v1/private_messages',
      data: {
        'sender_uid': myUid,
        'recipient_uid': otherUid,
        'message': text,
        'reply_to_id': replyToId,
        'reply_to_sender_uid': replyToSenderUid,
        'reply_to_message': replyToMessage,
      },
      options: Options(headers: {'Prefer': 'return=representation'}),
    );
    final list = _parse(res.data);
    if (list.isEmpty) throw StateError('Server tidak mengembalikan pesan');
    return list.first;
  }

  Future<void> markRead(String myUid, String otherUid) async {
    await _dio.patch<dynamic>(
      'rest/v1/private_messages',
      queryParameters: {
        'recipient_uid': 'eq.${_safe(myUid)}',
        'sender_uid': 'eq.${_safe(otherUid)}',
        'read_at': 'is.null',
      },
      data: {'read_at': DateTime.now().toUtc().toIso8601String()},
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );
  }
}
