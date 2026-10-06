import 'package:dio/dio.dart';

import '../models/friend_models.dart';
import 'chat_repository.dart';

/// Fitur Add Friend lewat PostgREST langsung (tabel `friendships`), sama
/// dengan FriendRepository.kt di Zenime. Error dilempar (DioException) dan
/// ditangani pemanggil.
class FriendRepository {
  FriendRepository(this._dio, this._chat);

  final Dio _dio;
  final ChatRepository _chat;

  static const String _cols = 'id,requester_uid,addressee_uid,status,created_at';

  // uid masuk ke filter `or=(...)`; tolak karakter yang bisa merusak filter.
  static final RegExp _safeUid = RegExp(r'^[A-Za-z0-9_-]+$');

  static String _safe(String uid) {
    if (!_safeUid.hasMatch(uid)) throw ArgumentError('uid tidak valid');
    return uid;
  }

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Hubungan [myUid] terhadap [otherUid].
  Future<FriendRelation> getRelation(String myUid, String otherUid) async {
    final me = _safe(myUid);
    final other = _safe(otherUid);
    final res = await _dio.get<dynamic>(
      'rest/v1/friendships',
      queryParameters: {
        'or': '(and(requester_uid.eq.$me,addressee_uid.eq.$other),'
            'and(requester_uid.eq.$other,addressee_uid.eq.$me))',
        'select': _cols,
        'limit': 1,
      },
    );
    final rows = _rows(res.data);
    if (rows.isEmpty) return const FriendRelationNone();
    final f = Friendship.fromJson(rows.first);
    if (f.status == FriendStatus.accepted) return FriendRelationFriends(f.id);
    if (f.requesterUid == myUid) return FriendRelationOutgoing(f.id);
    return FriendRelationIncoming(f.id);
  }

  /// Jumlah permintaan pertemanan masuk yang belum direspon.
  Future<int> countIncomingRequests(String myUid) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/friendships',
      queryParameters: {
        'addressee_uid': 'eq.${_safe(myUid)}',
        'status': 'eq.${FriendStatus.pending}',
        'select': 'id',
        'limit': 100,
      },
    );
    return _rows(res.data).length;
  }

  Future<void> sendRequest(String myUid, String otherUid) async {
    await _dio.post<dynamic>(
      'rest/v1/friendships',
      data: {
        'requester_uid': myUid,
        'addressee_uid': otherUid,
        'status': FriendStatus.pending,
      },
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );
  }

  Future<void> accept(String friendshipId) async {
    await _dio.patch<dynamic>(
      'rest/v1/friendships',
      queryParameters: {'id': 'eq.$friendshipId'},
      data: {
        'status': FriendStatus.accepted,
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      },
      options: Options(headers: {'Prefer': 'return=minimal'}),
    );
  }

  /// Tolak permintaan masuk / batalkan permintaan keluar / hapus teman.
  Future<void> remove(String friendshipId) async {
    await _dio.delete<dynamic>(
      'rest/v1/friendships',
      queryParameters: {'id': 'eq.$friendshipId'},
    );
  }

  Future<FriendLists> getLists(String myUid) async {
    final me = _safe(myUid);
    final res = await _dio.get<dynamic>(
      'rest/v1/friendships',
      queryParameters: {
        'or': '(requester_uid.eq.$me,addressee_uid.eq.$me)',
        'select': _cols,
        'order': 'created_at.desc',
        'limit': 500,
      },
    );
    final rows = _rows(res.data).map(Friendship.fromJson).toList();
    final profiles = await _chat.getProfilesForUids(rows.map((f) => f.otherUid(myUid)).toList());

    FriendDisplay display(Friendship f) {
      final uid = f.otherUid(myUid);
      final p = profiles[uid];
      final name = p?.username.trim() ?? '';
      final avatar = p?.avatarUrl;
      return FriendDisplay(
        friendshipId: f.id,
        firebaseUid: uid,
        username: name.isEmpty ? 'Pengguna Zenime' : name,
        avatarUrl: (avatar == null || avatar.isEmpty) ? null : avatar,
      );
    }

    return FriendLists(
      friends: rows
          .where((f) => f.status == FriendStatus.accepted)
          .map(display)
          .toList()
        ..sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase())),
      incoming: rows
          .where((f) => f.status == FriendStatus.pending && f.addresseeUid == myUid)
          .map(display)
          .toList(),
      outgoing: rows
          .where((f) => f.status == FriendStatus.pending && f.requesterUid == myUid)
          .map(display)
          .toList(),
    );
  }
}
