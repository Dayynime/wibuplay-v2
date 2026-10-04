import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_config.dart';
import '../models/chat_models.dart';
import '../models/xp_models.dart';
import 'chat_repository.dart';

/// XP nonton, backend sama dengan Zenime. Port XpRepository.kt.
///
/// Heartbeat memakai Edge Function `watch-xp-heartbeat`, yang mengambil
/// firebase_uid dari Firebase ID Token yang diverifikasi server. JANGAN kirim
/// firebase_uid di body: itu celah yang membuat client dipercaya mengirim
/// identitasnya sendiri. XP, level, dan x2 Premium dihitung server.
///
/// Membaca XP/leaderboard lewat PostgREST (public SELECT, write ditolak RLS).
class XpRepository {
  XpRepository(this._dio, this._chat);

  final Dio _dio;
  final ChatRepository _chat;

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Kirim heartbeat "sudah nonton [minutes] menit". Best-effort: gagal kirim
  /// hanya berarti kehilangan sedikit XP, jadi tidak di-retry dan tidak melempar.
  /// Return true kalau server menjawab sukses.
  Future<bool> sendHeartbeat({int minutes = 1}) async {
    if (!FirebaseConfig.ready) return false;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final token = await user.getIdToken();
      if (token == null) return false;
      final res = await _dio.post<dynamic>(
        'functions/v1/watch-xp-heartbeat',
        data: {'minutes': minutes},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = res.data;
      return data is Map && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// XP/level sendiri. null = belum pernah dapat XP (belum ada baris).
  Future<UserXp?> getMyXp(String firebaseUid) async {
    final res = await _dio.get<dynamic>(
      'rest/v1/user_xp',
      queryParameters: {'firebase_uid': 'eq.$firebaseUid', 'select': '*', 'limit': 1},
    );
    final rows = _rows(res.data);
    return rows.isEmpty ? null : UserXp.fromJson(rows.first);
  }

  /// Level banyak uid sekaligus (badge level di bubble chat). User yang belum
  /// punya baris user_xp tidak masuk map: jangan tampilkan badge untuk mereka.
  Future<Map<String, int>> getLevelsForUids(List<String> uids) async {
    final distinct = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (distinct.isEmpty) return const {};
    final res = await _dio.get<dynamic>(
      'rest/v1/user_xp',
      queryParameters: {
        'firebase_uid': 'in.(${distinct.join(',')})',
        'select': 'firebase_uid,level',
      },
    );
    final out = <String, int>{};
    for (final row in _rows(res.data)) {
      final x = UserXp.fromJson(row);
      if (x.firebaseUid.isNotEmpty) out[x.firebaseUid] = x.level;
    }
    return out;
  }

  /// Status Premium lewat Edge Function `zenime-check-premium` (satu uid per
  /// request, sama seperti Zenime). Gagal cek dianggap tidak premium.
  Future<bool> isPremium(String firebaseUid) async {
    if (firebaseUid.isEmpty) return false;
    try {
      final res = await _dio.post<dynamic>(
        'functions/v1/zenime-check-premium',
        data: {'firebase_uid': firebaseUid},
      );
      final data = res.data;
      return data is Map && data['is_premium'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Bulan berjalan zona WIB (UTC+7), format "yyyy-MM".
  static String currentPeriod() {
    final wib = DateTime.now().toUtc().add(const Duration(hours: 7));
    return '${wib.year}-${wib.month.toString().padLeft(2, '0')}';
  }

  /// Top 100 leaderboard BULANAN (reset otomatis tiap tanggal 1 WIB karena
  /// ganti baris `period`), digabung username/avatar dari chat_profiles,
  /// status Premium, dan level kumulatif dari user_xp. Melempar kalau gagal
  /// (UI menampilkan error + coba lagi).
  Future<List<UserXpDisplay>> getLeaderboardDisplay() async {
    final res = await _dio.get<dynamic>(
      'rest/v1/user_xp_monthly',
      queryParameters: {
        'period': 'eq.${currentPeriod()}',
        'select': 'firebase_uid,xp',
        'order': 'xp.desc',
        'limit': 100,
      },
    );
    final top = _rows(res.data);
    if (top.isEmpty) return const [];
    final uids = top
        .map((r) => (r['firebase_uid'] as String?) ?? '')
        .where((u) => u.isNotEmpty)
        .toList();

    // Profil, level, dan Premium diambil BARENGAN, bukan berurutan.
    final results = await Future.wait<Object>([
      _chat.getProfilesForUids(uids),
      getLevelsForUids(uids).catchError((_) => <String, int>{}),
      Future.wait(uids.map((u) async => MapEntry(u, await isPremium(u)))),
    ]);
    final profiles = results[0] as Map<String, ChatProfile>;
    final levels = results[1] as Map<String, int>;
    final premium = {
      for (final e in results[2] as List<MapEntry<String, bool>>) e.key: e.value,
    };

    final list = top.map((row) {
      final uid = (row['firebase_uid'] as String?) ?? '';
      final profile = profiles[uid];
      final name = profile?.username ?? '';
      return UserXpDisplay(
        firebaseUid: uid,
        xp: (row['xp'] as num?)?.toInt() ?? 0,
        level: levels[uid] ?? 1,
        username: name.isEmpty ? 'Pengguna' : name,
        avatarUrl: profile?.avatarUrl,
        isPremium: premium[uid] == true,
      );
    }).toList()
      ..sort((a, b) => b.xp.compareTo(a.xp));
    return list;
  }
}
