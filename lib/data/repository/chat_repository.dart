import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_config.dart';
import '../models/chat_models.dart';
import '../models/clan_models.dart';

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

  /// Pesan error dari body Edge Function (mis. "Terlalu cepat, tunggu sebentar").
  static String? _serverMessage(Object e) {
    if (e is! DioException) return null;
    final d = e.response?.data;
    final msg = d is Map ? d['error'] : null;
    return (msg is String && msg.trim().isNotEmpty) ? msg.trim() : null;
  }

  /// Kirim pesan lewat Edge Function `chat-global`. UID, username, avatar, dan
  /// kutipan balasan diisi SERVER; parameter lama dipertahankan hanya agar
  /// pemanggil tidak berubah dan tidak ada yang dikirim ke server.
  Future<ChatMessage> sendMessage({
    required String firebaseUid,
    required String username,
    String? avatarUrl,
    required String message,
    int? replyToId,
    String? replyToUsername,
    String? replyToMessage,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        'functions/v1/chat-global',
        data: {'action': 'send', 'message': message, 'reply_to_id': replyToId},
        options: await _authOptions(),
      );
      final d = res.data;
      if (d is! Map) {
        throw Exception('Server tidak mengembalikan pesan yang terkirim');
      }
      return ChatMessage.fromJson(Map<String, dynamic>.from(d));
    } catch (e) {
      final m = _serverMessage(e);
      if (m != null) throw Exception(m);
      rethrow;
    }
  }

  /// Hapus pesan milik sendiri. Server hanya menghapus kalau pesan itu milik
  /// uid di token.
  Future<void> deleteMessage(int id, String firebaseUid) async {
    try {
      await _dio.post<dynamic>(
        'functions/v1/chat-global',
        data: {'action': 'delete', 'id': id},
        options: await _authOptions(),
      );
    } catch (e) {
      final m = _serverMessage(e);
      if (m != null) throw Exception(m);
      rethrow;
    }
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

  /// Header Authorization berisi Firebase ID Token asli (bukan anon key).
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

  /// Simpan profil lewat Edge Function `chat-save-profile`. UID diambil server
  /// dari token, BUKAN dari body. Parameter [firebaseUid] dipertahankan hanya
  /// agar pemanggil lama tidak berubah; nilainya tidak dikirim.
  Future<void> saveProfile({
    required String firebaseUid,
    required String username,
    String? avatarUrl,
    String? bannerUrl,
    String? usernameColor,
    bool favoritesPublic = false,
    bool historyPublic = false,
  }) async {
    try {
      await _dio.post<dynamic>(
        'functions/v1/chat-save-profile',
        data: {
          'username': username,
          'avatar_url': avatarUrl,
          'banner_url': bannerUrl,
          'username_color': usernameColor,
          'favorites_public': favoritesPublic,
          'history_public': historyPublic,
        },
        options: await _authOptions(),
      );
    } on DioException catch (e) {
      // Tampilkan pesan dari server (mis. "Username sudah dipakai").
      final d = e.response?.data;
      final msg = d is Map ? d['error'] : null;
      if (msg is String && msg.trim().isNotEmpty) {
        throw Exception(msg.trim());
      }
      rethrow;
    }
  }

  /// Buat baris profil kalau belum ada. Kalau sudah ada (mis. dari Zenime)
  /// TIDAK disentuh. Nama default dipilih server dari akun Firebase.
  Future<void> ensureProfile(
    String firebaseUid,
    String defaultUsername,
    String? defaultAvatarUrl,
  ) async {
    try {
      final existing = await getProfile(firebaseUid);
      if (existing != null) return;
      await _dio.post<dynamic>(
        'functions/v1/chat-save-profile',
        data: <String, dynamic>{},
        options: await _authOptions(),
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

  /// Tag clan banyak uid dalam 1 request (embedding PostgREST
  /// clan_members.clan_id -> clans.id, sama seperti Zenime). Uid yang tidak
  /// gabung clan tidak masuk map.
  Future<Map<String, String>> getClanTagsForUids(List<String> uids) async {
    final distinct = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (distinct.isEmpty) return const {};
    final res = await _dio.get<dynamic>(
      'rest/v1/clan_members',
      queryParameters: {
        'firebase_uid': 'in.(${distinct.join(',')})',
        'select': 'firebase_uid,clans(tag)',
      },
    );
    final out = <String, String>{};
    for (final row in _rows(res.data)) {
      final uid = (row['firebase_uid'] as String?) ?? '';
      final clan = row['clans'];
      final tag = clan is Map ? clan['tag'] as String? : null;
      if (uid.isNotEmpty && tag != null && tag.isNotEmpty) out[uid] = tag;
    }
    return out;
  }

  /// Top clan (level tertinggi, lalu total XP) buat slide Top Leaderboard.
  Future<List<ClanSummary>> getTopClans({int limit = 4}) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/clans',
      queryParameters: {
        'select': 'id,tag,photo_url,level,total_xp',
        'order': 'level.desc,total_xp.desc',
        'limit': limit,
      },
    );
    return _rows(res.data)
        .map(ClanSummary.fromJson)
        .where((c) => c.tag.isNotEmpty)
        .toList();
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
