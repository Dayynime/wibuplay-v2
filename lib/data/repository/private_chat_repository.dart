import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_config.dart';
import '../models/friend_models.dart';

/// Chat teman (DM) lewat Edge Function `private-chat`. Semua aksi memakai
/// Firebase ID Token; UID pengirim diambil server dari token, BUKAN dari body.
class PrivateChatRepository {
  PrivateChatRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'functions/v1/private-chat';

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

  Future<Options> _authOptions() async {
    if (!FirebaseConfig.ready) {
      throw Exception('Login belum tersedia di perangkat ini.');
    }
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Kamu harus login dulu');
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<dynamic> _call(Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<dynamic>(_fn, data: body, options: await _authOptions());
      return res.data;
    } catch (e) {
      if (e is DioException) {
        final d = e.response?.data;
        final msg = d is Map ? d['error'] : null;
        if (msg is String && msg.trim().isNotEmpty) throw Exception(msg.trim());
      }
      rethrow;
    }
  }

  /// Urut lama -> baru (siap dirender dari atas ke bawah).
  Future<List<PrivateMessage>> getConversation(String myUid, String otherUid) async {
    final data = await _call({'action': 'conversation', 'other_uid': _safe(otherUid)});
    return _parse(data)..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Pesan terbaru yang melibatkan user ini (buat menyusun daftar percakapan).
  Future<List<PrivateMessage>> getRecent(String myUid) async {
    return _parse(await _call({'action': 'recent'}));
  }

  Future<PrivateMessage> send({
    required String myUid,
    required String otherUid,
    required String text,
    int? replyToId,
    String? replyToSenderUid,
    String? replyToMessage,
  }) async {
    final data = await _call({
      'action': 'send',
      'other_uid': _safe(otherUid),
      'text': text,
      'reply_to_id': replyToId,
    });
    if (data is! Map) throw StateError('Server tidak mengembalikan pesan');
    return PrivateMessage.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> markRead(String myUid, String otherUid) async {
    await _call({'action': 'mark_read', 'other_uid': _safe(otherUid)});
  }
}
