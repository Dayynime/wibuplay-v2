import 'package:dio/dio.dart';

import '../models/chat_models.dart';
import '../models/friend_models.dart';
import 'authed_function.dart';
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
    // Pengirim = uid di token ([myUid] tidak dikirim).
    await callAuthedFunction(_dio, 'friends-action', {
      'action': 'send',
      'other_uid': _safe(otherUid),
    });
  }

  Future<void> accept(String friendshipId) async {
    await callAuthedFunction(_dio, 'friends-action', {
      'action': 'accept',
      'friendship_id': friendshipId,
    });
  }

  /// Tolak permintaan masuk / batalkan permintaan keluar / hapus teman.
  Future<void> remove(String friendshipId) async {
    await callAuthedFunction(_dio, 'friends-action', {
      'action': 'remove',
      'friendship_id': friendshipId,
    });
  }

  /// Level XP banyak uid sekaligus (tabel `user_xp`, public SELECT).
  Future<Map<String, int>> _getLevels(List<String> uids) async {
    final distinct = uids.where(_safeUid.hasMatch).toSet().toList();
    if (distinct.isEmpty) return <String, int>{};
    final res = await _dio.get<dynamic>(
      'rest/v1/user_xp',
      queryParameters: {
        'firebase_uid': 'in.(${distinct.join(',')})',
        'select': 'firebase_uid,level',
      },
    );
    final out = <String, int>{};
    for (final row in _rows(res.data)) {
      final uid = (row['firebase_uid'] as String?) ?? '';
      final lv = (row['level'] as num?)?.toInt();
      if (uid.isNotEmpty && lv != null) out[uid] = lv;
    }
    return out;
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
    final uids = rows.map((f) => f.otherUid(myUid)).toList();
    // Profil wajib, level best-effort (gagal = badge level tidak tampil).
    final results = await Future.wait<Object>([
      _chat.getProfilesForUids(uids),
      _getLevels(uids).catchError((_) => <String, int>{}),
    ]);
    final profiles = results[0] as Map<String, ChatProfile>;
    final levels = results[1] as Map<String, int>;

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
        userNumber: p?.userNumber,
        level: levels[uid],
        usernameColor: p?.usernameColor,
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

  // ------------------------------------------------------------ cari user

  /// Bersihkan input pencarian: karakter yang punya arti di filter PostgREST
  /// (koma, kurung, wildcard, dst.) dibuang supaya filter tidak rusak.
  static String _cleanQuery(String raw) {
    var q = raw.trim().replaceFirst(RegExp(r'^#\s*'), '');
    q = q.replaceAll(RegExp(r'[,()*%\\"\x00-\x1f]'), ' ');
    return q.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Hubungan [myUid] dengan banyak uid sekaligus (1 request). Uid tanpa
  /// baris friendships tidak masuk map (= belum ada hubungan).
  Future<Map<String, FriendRelation>> getRelationsFor(String myUid, List<String> otherUids) async {
    final me = _safe(myUid);
    final others = otherUids.where(_safeUid.hasMatch).toSet().toList();
    if (others.isEmpty) return <String, FriendRelation>{};
    final list = others.join(',');
    final res = await _dio.get<dynamic>(
      'rest/v1/friendships',
      queryParameters: {
        'or': '(and(requester_uid.eq.$me,addressee_uid.in.($list)),'
            'and(addressee_uid.eq.$me,requester_uid.in.($list)))',
        'select': _cols,
        'limit': 500,
      },
    );
    final out = <String, FriendRelation>{};
    for (final f in _rows(res.data).map(Friendship.fromJson)) {
      final other = f.otherUid(myUid);
      if (f.status == FriendStatus.accepted) {
        out[other] = FriendRelationFriends(f.id);
      } else if (f.requesterUid == myUid) {
        out[other] = FriendRelationOutgoing(f.id);
      } else {
        out[other] = FriendRelationIncoming(f.id);
      }
    }
    return out;
  }

  /// Cari semua user (tabel `chat_profiles`) lewat username atau ID urut.
  /// [query] kosong = tampilkan semua user (ID terbaru dulu). Diri sendiri
  /// tidak ikut. Halaman berikutnya lewat [offset] = `nextOffset` sebelumnya.
  Future<FriendSearchPage> searchUsers(
    String myUid,
    String query, {
    int offset = 0,
    int limit = 30,
  }) async {
    final me = _safe(myUid);
    final q = _cleanQuery(query);
    final n = int.tryParse(q);
    final byId = n != null && n >= 0 && n <= 2147483647;

    final params = <String, dynamic>{
      'select': 'firebase_uid,username,avatar_url,username_color,user_number',
      'firebase_uid': 'neq.$me',
      'username': 'neq.',
      'order': 'user_number.desc.nullslast',
      'limit': limit + 1,
      'offset': offset,
    };
    if (q.isNotEmpty) {
      params['or'] = byId ? '(user_number.eq.$n,username.ilike.*$q*)' : '(username.ilike.*$q*)';
    }

    final res = await _dio.get<dynamic>('rest/v1/chat_profiles', queryParameters: params);
    var rows = _rows(res.data);
    final hasMore = rows.length > limit;
    if (hasMore) rows = rows.sublist(0, limit);

    final profiles = rows
        .map(ChatProfile.fromJson)
        .where((p) => _safeUid.hasMatch(p.firebaseUid) && p.username.trim().isNotEmpty)
        .toList();
    final uids = profiles.map((p) => p.firebaseUid).toList();

    // Hubungan wajib (supaya tombol benar), level best-effort.
    final results = await Future.wait<Object>([
      getRelationsFor(myUid, uids),
      _getLevels(uids).catchError((_) => <String, int>{}),
    ]);
    final relations = results[0] as Map<String, FriendRelation>;
    final levels = results[1] as Map<String, int>;

    var items = profiles.map((p) {
      final avatar = p.avatarUrl;
      return FriendSearchItem(
        firebaseUid: p.firebaseUid,
        username: p.username.trim(),
        avatarUrl: (avatar == null || avatar.isEmpty) ? null : avatar,
        userNumber: p.userNumber,
        level: levels[p.firebaseUid],
        usernameColor: p.usernameColor,
        relation: relations[p.firebaseUid] ?? const FriendRelationNone(),
      );
    }).toList();

    // Cocok persis dengan ID yang diketik: taruh paling atas.
    if (byId && offset == 0) {
      final exact = items.where((e) => e.userNumber == n).toList();
      items = [...exact, ...items.where((e) => e.userNumber != n)];
    }

    return FriendSearchPage(items: items, hasMore: hasMore, nextOffset: offset + rows.length);
  }
}
