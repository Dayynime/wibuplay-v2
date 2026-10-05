import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_config.dart';
import '../models/chat_models.dart';
import '../models/clan_models.dart';
import 'chat_repository.dart';

/// Error yang pesannya sudah siap ditampilkan ke user.
class ClanException implements Exception {
  const ClanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fitur Clan, backend sama dengan Zenime. Port ClanRepository.kt.
///
/// Baca data publik (clan, member, log donasi) lewat PostgREST (public
/// SELECT). Aksi yang menyentuh identitas/uang (join, donasi, keluar) lewat
/// Edge Function dan WAJIB membawa Firebase ID Token asli di header
/// Authorization; JANGAN kirim firebase_uid di body.
class ClanRepository {
  ClanRepository(this._dio, this._chat);

  final Dio _dio;
  final ChatRepository _chat;

  static const String _memberColumns =
      'clan_id,firebase_uid,role,total_contribution,joined_at';

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<String> _authHeader() async {
    if (!FirebaseConfig.ready) {
      throw const ClanException('Login belum tersedia di perangkat ini.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ClanException('Kamu harus login dulu');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const ClanException('Gagal ambil token login, coba login ulang');
    }
    return 'Bearer $token';
  }

  /// Ambil pesan "error" dari body Edge Function; kalau tidak ada, pakai
  /// pesan koneksi / [fallback].
  String _errorMessage(Object e, String fallback) {
    if (e is ClanException) return e.message;
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map) {
        final msg = d['error'];
        if (msg is String && msg.trim().isNotEmpty) return msg.trim();
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return 'Koneksi bermasalah, coba lagi.';
        default:
          break;
      }
    }
    return fallback;
  }

  Future<T> _guard<T>(String fallback, Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw ClanException(_errorMessage(e, fallback));
    }
  }

  // ------------------------------------------------------------------ baca

  /// Semua clan, urut level lalu total XP (dasar halaman Browse + Leaderboard).
  Future<List<Clan>> browseClans({int limit = 50}) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/clans',
      queryParameters: {
        'select': '*',
        'order': 'level.desc,total_xp.desc',
        'limit': limit,
      },
    );
    return _rows(res.data).map(Clan.fromJson).where((c) => c.id.isNotEmpty).toList();
  }

  Future<Clan> getClan(String clanId) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/clans',
      queryParameters: {'id': 'eq.$clanId', 'select': '*', 'limit': 1},
    );
    final rows = _rows(res.data);
    if (rows.isEmpty) throw const ClanException('Clan tidak ditemukan');
    return Clan.fromJson(rows.first);
  }

  /// Clan yang sedang diikuti user (null = belum gabung clan mana pun).
  Future<ClanMember?> getMyMembership(String firebaseUid) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/clan_members',
      queryParameters: {
        'firebase_uid': 'eq.$firebaseUid',
        'select': _memberColumns,
        'limit': 1,
      },
    );
    final rows = _rows(res.data);
    return rows.isEmpty ? null : ClanMember.fromJson(rows.first);
  }

  /// Apakah user sudah punya request join yang menunggu di clan ini.
  /// Gagal cek dianggap tidak ada.
  Future<bool> getMyJoinRequestPending(String clanId) async {
    try {
      final res = await _dio.get<dynamic>(
        'functions/v1/zenime-clan-my-request-status',
        queryParameters: {'clan_id': clanId},
        options: Options(headers: {'Authorization': await _authHeader()}),
      );
      final d = res.data;
      return d is Map && d['pending'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Profil chat banyak uid (dipecah per 50 uid biar URL tidak kepanjangan).
  Future<Map<String, ChatProfile>> _profiles(List<String> uids) async {
    final distinct = uids.where((u) => u.isNotEmpty).toSet().toList();
    final out = <String, ChatProfile>{};
    for (var i = 0; i < distinct.length; i += 50) {
      final end = i + 50 > distinct.length ? distinct.length : i + 50;
      out.addAll(await _chat.getProfilesForUids(distinct.sublist(i, end)));
    }
    return out;
  }

  /// Member clan + profil, urut dari role tertinggi (Leader) ke terendah.
  /// Di dalam role yang sama urutan kontribusi dari server dipertahankan.
  Future<List<ClanMemberDisplay>> getMembers(String clanId) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/clan_members',
      queryParameters: {
        'clan_id': 'eq.$clanId',
        'select': _memberColumns,
        'order': 'total_contribution.desc',
        'limit': 500,
      },
    );
    final members = _rows(res.data).map(ClanMember.fromJson).toList();
    final profiles = await _profiles(members.map((m) => m.firebaseUid).toList());
    final list = [
      for (final m in members)
        ClanMemberDisplay(
          firebaseUid: m.firebaseUid,
          role: m.role,
          totalContribution: m.totalContribution,
          joinedAt: m.joinedAt,
          username: (profiles[m.firebaseUid]?.username ?? '').isEmpty
              ? 'Pengguna'
              : profiles[m.firebaseUid]!.username,
          avatarUrl: profiles[m.firebaseUid]?.avatarUrl,
          userNumber: profiles[m.firebaseUid]?.userNumber,
        ),
    ];
    // List.sort Dart tidak dijamin stabil, jadi index ikut jadi pembanding.
    final indexed = list.asMap().entries.toList()
      ..sort((a, b) {
        final byRole = ClanRoles.rank(b.value.role).compareTo(ClanRoles.rank(a.value.role));
        return byRole != 0 ? byRole : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  /// Ranking "Donasi Hari Ini": log donasi sejak 00:00 waktu perangkat,
  /// dijumlah per user, urut dari yang terbesar.
  Future<List<ClanDonationEntry>> getTodayDonations(
    String clanId, {
    required Map<String, String> roleByUid,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final res = await _dio.get<dynamic>(
      'rest/v1/clan_donation_log',
      queryParameters: {
        'clan_id': 'eq.$clanId',
        'created_at': 'gte.$start',
        'select': 'firebase_uid,amount,created_at',
        'order': 'created_at.desc',
        'limit': 1000,
      },
    );
    final sums = <String, int>{};
    final counts = <String, int>{};
    for (final row in _rows(res.data)) {
      final uid = (row['firebase_uid'] as String?) ?? '';
      if (uid.isEmpty) continue;
      sums[uid] = (sums[uid] ?? 0) + ((row['amount'] as num?)?.toInt() ?? 0);
      counts[uid] = (counts[uid] ?? 0) + 1;
    }
    final profiles = await _profiles(sums.keys.toList());
    final list = [
      for (final e in sums.entries)
        ClanDonationEntry(
          firebaseUid: e.key,
          username: (profiles[e.key]?.username ?? '').isEmpty
              ? 'Pengguna'
              : profiles[e.key]!.username,
          avatarUrl: profiles[e.key]?.avatarUrl,
          role: roleByUid[e.key] ?? ClanRoles.member,
          amountToday: e.value,
          donationCountToday: counts[e.key] ?? 0,
        ),
    ]..sort((a, b) => b.amountToday.compareTo(a.amountToday));
    return list;
  }

  // ------------------------------------------------------------------ aksi

  Future<void> submitJoinRequest(String clanId) => _guard('Gagal mengirim request join', () async {
        await _dio.post<dynamic>(
          'functions/v1/zenime-clan-join-request',
          data: {'clan_id': clanId},
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
      });

  Future<void> donate(String clanId, int amount) => _guard('Gagal donasi ZCoin', () async {
        await _dio.post<dynamic>(
          'functions/v1/zenime-clan-donate',
          data: {'clan_id': clanId, 'amount': amount},
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
      });

  /// Keluar dari clan sendiri. Leader ditolak server (harus transfer/bubarkan dulu).
  Future<void> leaveClan(String clanId) => _guard('Gagal keluar clan', () async {
        await _dio.post<dynamic>(
          'functions/v1/zenime-clan-leave',
          data: {'clan_id': clanId},
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
      });

  /// Daftar request join yang menunggu; cuma bisa dibaca officer ke atas
  /// (dicek di Edge Function).
  Future<List<PendingJoinRequestDisplay>> getPendingJoinRequests(String clanId) =>
      _guard('Gagal ambil daftar request join', () async {
        final res = await _dio.get<dynamic>(
          'functions/v1/zenime-clan-pending-requests',
          queryParameters: {'clan_id': clanId},
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
        final d = res.data;
        final items = d is Map && d['requests'] is List
            ? _rows(d['requests'])
            : <Map<String, dynamic>>[];
        final uids = [for (final it in items) (it['firebase_uid'] as String?) ?? ''];
        final profiles = await _profiles(uids);
        return [
          for (final it in items)
            PendingJoinRequestDisplay(
              requestId: (it['id'] ?? '').toString(),
              firebaseUid: (it['firebase_uid'] as String?) ?? '',
              username: (profiles[it['firebase_uid']]?.username ?? '').isEmpty
                  ? 'Pengguna'
                  : profiles[it['firebase_uid']]!.username,
              avatarUrl: profiles[it['firebase_uid']]?.avatarUrl,
              requestedAt: (it['requested_at'] as String?) ?? '',
            ),
        ];
      });

  Future<void> respondJoinRequest(String requestId, bool approve) =>
      _guard('Gagal memproses request join', () async {
        await _dio.post<dynamic>(
          'functions/v1/zenime-clan-respond-request',
          data: {'request_id': requestId, 'approve': approve},
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
      });

  Future<void> kickMember(String clanId, String targetUid) =>
      _guard('Gagal kick member', () async {
        await _dio.post<dynamic>(
          'functions/v1/zenime-clan-kick',
          data: {'clan_id': clanId, 'target_uid': targetUid},
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
      });

  /// [role]: salah satu dari [ClanRoles] (vice_leader / admiral / co_leader / member).
  Future<void> setMemberRole(String clanId, String targetUid, String role) =>
      _guard('Gagal ubah role member', () async {
        await _dio.post<dynamic>(
          'functions/v1/zenime-clan-set-role',
          data: {'clan_id': clanId, 'target_uid': targetUid, 'role': role},
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
      });

  /// Ubah nama/tag clan (khusus leader). Field null tidak dikirim.
  Future<void> updateClanSettings(String clanId, {String? name, String? tag}) =>
      _guard('Gagal update settingan clan', () async {
        await _dio.post<dynamic>(
          'functions/v1/zenime-clan-settings',
          data: {
            'clan_id': clanId,
            if (name != null) 'name': name,
            if (tag != null) 'tag': tag,
          },
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
      });

  /// Beli [packs] paket kuota member pakai saldo donasi clan (khusus leader,
  /// dicek di server).
  Future<void> buyMemberSlots(String clanId, int packs) =>
      _guard('Gagal beli kuota member', () async {
        await _dio.post<dynamic>(
          'functions/v1/zenime-clan-buy-slots',
          data: {'clan_id': clanId, 'packs': packs},
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
      });
}
