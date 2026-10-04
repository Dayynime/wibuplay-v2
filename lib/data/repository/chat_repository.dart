import 'package:dio/dio.dart';

import '../models/chat_models.dart';

/// Chat Global lewat PostgREST Supabase Zenime (tabel `global_chat_messages`
/// dan `chat_profiles`). Port ChatRepository.kt.
class ChatRepository {
  ChatRepository(this._dio);

  final Dio _dio;

  static const String _messageColumns =
      'id,firebase_uid,username,avatar_url,message,created_at,reply_to_id,'
      'reply_to_username,reply_to_message,message_type,audio_url,duration_seconds';

  static const String _profileColumns =
      'firebase_uid,username,avatar_url,banner_url,username_color,user_number,'
      'updated_at,favorites_public,history_public';

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Pesan terbaru, urutan kronologis (lama -> baru).
  Future<List<ChatMessage>> getMessages({int limit = 50}) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/global_chat_messages',
      queryParameters: {
        'select': _messageColumns,
        'order': 'created_at.desc',
        'limit': limit,
      },
    );
    return _rows(res.data).map(ChatMessage.fromJson).toList().reversed.toList();
  }

  Future<ChatMessage> sendMessage({
    required String firebaseUid,
    required String username,
    String? avatarUrl,
    required String message,
    int? replyToId,
    String? replyToUsername,
    String? replyToMessage,
  }) async {
    final res = await _dio.post<dynamic>(
      'rest/v1/global_chat_messages',
      data: {
        'firebase_uid': firebaseUid,
        'username': username,
        'avatar_url': avatarUrl,
        'message': message,
        'reply_to_id': replyToId,
        'reply_to_username': replyToUsername,
        'reply_to_message': replyToMessage,
        'message_type': 'text',
      },
      options: Options(headers: {'Prefer': 'return=representation'}),
    );
    final rows = _rows(res.data);
    if (rows.isEmpty) {
      throw Exception('Server tidak mengembalikan pesan yang terkirim');
    }
    return ChatMessage.fromJson(rows.first);
  }

  /// Hapus pesan milik sendiri. Filter firebase_uid ikut dikirim di query
  /// (sama seperti Zenime) supaya request tidak bisa dipakai menghapus pesan orang lain.
  Future<void> deleteMessage(int id, String firebaseUid) async {
    await _dio.delete<dynamic>(
      'rest/v1/global_chat_messages',
      queryParameters: {'id': 'eq.$id', 'firebase_uid': 'eq.$firebaseUid'},
    );
  }

  Future<ChatProfile?> getProfile(String firebaseUid) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/chat_profiles',
      queryParameters: {
        'firebase_uid': 'eq.$firebaseUid',
        'select': _profileColumns,
        'limit': 1,
      },
    );
    final rows = _rows(res.data);
    return rows.isEmpty ? null : ChatProfile.fromJson(rows.first);
  }

  /// Upsert profil (firebase_uid = primary key). Upsert menimpa SEMUA kolom
  /// yang dikirim, jadi nilai yang tidak diubah tetap harus ikut dikirim.
  Future<void> saveProfile({
    required String firebaseUid,
    required String username,
    String? avatarUrl,
    String? bannerUrl,
    String? usernameColor,
    bool favoritesPublic = false,
    bool historyPublic = false,
  }) async {
    await _dio.post<dynamic>(
      'rest/v1/chat_profiles',
      queryParameters: {'on_conflict': 'firebase_uid'},
      data: {
        'firebase_uid': firebaseUid,
        'username': username,
        'avatar_url': avatarUrl,
        'banner_url': bannerUrl,
        'username_color': usernameColor,
        'favorites_public': favoritesPublic,
        'history_public': historyPublic,
      },
      options: Options(
        headers: {'Prefer': 'resolution=merge-duplicates,return=minimal'},
      ),
    );
  }

  /// Buat baris profil kalau belum ada. Kalau sudah ada (mis. dari Zenime)
  /// TIDAK disentuh, supaya username/avatar custom user tidak ketimpa.
  Future<void> ensureProfile(
    String firebaseUid,
    String defaultUsername,
    String? defaultAvatarUrl,
  ) async {
    try {
      final existing = await getProfile(firebaseUid);
      if (existing != null) return;
      await saveProfile(
        firebaseUid: firebaseUid,
        username: defaultUsername,
        avatarUrl: defaultAvatarUrl,
      );
    } catch (_) {
      // Best effort: gagal di sini tidak boleh menghalangi login/chat.
    }
  }

  /// Warna username + ID urut + avatar terkini untuk banyak uid dalam 1 request.
  Future<ChatBadgeData> getBadgeData(List<String> uids) async {
    final distinct = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (distinct.isEmpty) return const ChatBadgeData();
    final res = await _dio.get<dynamic>(
      'rest/v1/chat_profiles',
      queryParameters: {
        'firebase_uid': 'in.(${distinct.join(',')})',
        'select': 'firebase_uid,username,username_color,user_number,avatar_url',
      },
    );
    final colors = <String, String>{};
    final numbers = <String, int>{};
    final avatars = <String, String>{};
    for (final row in _rows(res.data)) {
      final p = ChatProfile.fromJson(row);
      final c = p.usernameColor;
      final n = p.userNumber;
      final a = p.avatarUrl;
      if (c != null && c.isNotEmpty) colors[p.firebaseUid] = c;
      if (n != null) numbers[p.firebaseUid] = n;
      if (a != null && a.isNotEmpty) avatars[p.firebaseUid] = a;
    }
    return ChatBadgeData(usernameColors: colors, userNumbers: numbers, avatarUrls: avatars);
  }

  /// Profil (username/avatar) banyak uid dalam 1 request, buat leaderboard.
  Future<Map<String, ChatProfile>> getProfilesForUids(List<String> uids) async {
    final distinct = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (distinct.isEmpty) return const {};
    final res = await _dio.get<dynamic>(
      'rest/v1/chat_profiles',
      queryParameters: {
        'firebase_uid': 'in.(${distinct.join(',')})',
        'select': 'firebase_uid,username,avatar_url,username_color,user_number',
      },
    );
    final out = <String, ChatProfile>{};
    for (final row in _rows(res.data)) {
      final p = ChatProfile.fromJson(row);
      if (p.firebaseUid.isNotEmpty) out[p.firebaseUid] = p;
    }
    return out;
  }
}
