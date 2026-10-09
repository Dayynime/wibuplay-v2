import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_config.dart';
import '../models/admin_models.dart';

/// Error yang pesannya sudah siap ditampilkan ke user.
class AdminException implements Exception {
  const AdminException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fitur Panel Admin (role developer/admin/moderator, ban akun/device),
/// backend sama dengan Zenime. Port AdminRepository.kt.
///
/// Semua aksi lewat Edge Function dan WAJIB membawa Firebase ID Token asli di
/// header Authorization. Role dicek ULANG di server, jadi gating di UI cuma
/// untuk menyembunyikan tombol.
class AdminRepository {
  AdminRepository(this._dio);

  final Dio _dio;

  static const int pageSize = 20;

  Future<String> _authHeader() async {
    if (!FirebaseConfig.ready) {
      throw const AdminException('Login belum tersedia di perangkat ini.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const AdminException('Kamu harus login dulu');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const AdminException('Gagal ambil token login, coba login ulang');
    }
    return 'Bearer $token';
  }

  /// Ambil pesan "error" dari body Edge Function; kalau tidak ada, pakai
  /// pesan koneksi / [fallback].
  String _errorMessage(Object e, String fallback) {
    if (e is AdminException) return e.message;
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
      throw AdminException(_errorMessage(e, fallback));
    }
  }

  Future<Map<String, dynamic>> _get(
    String function,
    String fallback, {
    Map<String, dynamic>? query,
  }) =>
      _guard(fallback, () async {
        final res = await _dio.get<dynamic>(
          'functions/v1/$function',
          queryParameters: query,
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
        final d = res.data;
        return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
      });

  /// POST aksi admin. Berhasil kalau body berisi `success: true`.
  Future<void> _action(String function, Map<String, dynamic> body, String fallback) =>
      _guard(fallback, () async {
        final res = await _dio.post<dynamic>(
          'functions/v1/$function',
          data: body,
          options: Options(headers: {'Authorization': await _authHeader()}),
        );
        final d = res.data;
        final map = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
        if (map['success'] != true) {
          final err = map['error'];
          throw AdminException(err is String && err.trim().isNotEmpty ? err.trim() : fallback);
        }
      });

  /// Role user yang lagi login (role null = user biasa). Dipakai buat gating UI.
  Future<AdminMyRole> getMyRole() async {
    final map = await _get('zenime-admin-get-role', 'Gagal cek role');
    return AdminMyRole.fromJson(map);
  }

  /// Daftar semua pemegang role. Khusus developer (ditolak server kalau bukan).
  Future<List<AdminRoleEntry>> listRoles() async {
    final map = await _get('zenime-admin-list-roles', 'Gagal memuat daftar role');
    final roles = map['roles'];
    if (roles is! List) return const [];
    return roles
        .whereType<Map>()
        .map((e) => AdminRoleEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Daftar/cari SEMUA user (nama, kode Zenime, atau UID). Mengembalikan
  /// (daftar user, masih ada halaman berikutnya?).
  Future<(List<AdminUser>, bool)> listUsers({String? search, int offset = 0}) async {
    final q = search?.trim() ?? '';
    final map = await _get(
      'zenime-admin-list-users',
      'Gagal memuat daftar user',
      query: {
        if (q.isNotEmpty) 'search': q,
        'limit': pageSize,
        'offset': offset,
      },
    );
    final users = map['users'];
    final list = users is List
        ? users
            .whereType<Map>()
            .map((e) => AdminUser.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <AdminUser>[];
    return (list, map['has_more'] == true);
  }

  /// Kasih/ganti role + opsional warna badge custom (#RRGGBB). Khusus developer.
  Future<void> setRole(String targetUid, String role, {String? badgeColor}) => _action(
        'zenime-admin-set-role',
        {
          'target_uid': targetUid,
          'role': role,
          'remove': false,
          if (badgeColor != null) 'badge_color': badgeColor,
        },
        'Gagal set role',
      );

  /// Cabut role (balik jadi user biasa). Khusus developer.
  Future<void> removeRole(String targetUid) => _action(
        'zenime-admin-set-role',
        {'target_uid': targetUid, 'role': '', 'remove': true},
        'Gagal cabut role',
      );

  /// Ban akun (admin/developer). Server menolak kalau target punya role.
  Future<void> banUser(String targetUid, {String? reason}) => _action(
        'zenime-admin-ban-user',
        {'target_uid': targetUid, if (reason != null) 'reason': reason},
        'Gagal ban akun',
      );

  Future<void> unbanUser(String targetUid) => _action(
        'zenime-admin-unban-user',
        {'target_uid': targetUid},
        'Gagal cabut ban akun',
      );

  /// Ban device dari uid target (khusus developer). Server menolak kalau target punya role.
  Future<void> banDevice(String targetUid, {String? reason}) => _action(
        'zenime-admin-ban-device',
        {'target_uid': targetUid, if (reason != null) 'reason': reason},
        'Gagal ban device',
      );

  Future<void> unbanDevice(String deviceId) => _action(
        'zenime-admin-unban-device',
        {'device_id': deviceId},
        'Gagal cabut ban device',
      );

  /// Hapus pesan Chat Global milik orang lain (admin/developer). Lewat Edge
  /// Function yang sama dengan Zenime; role dicek ULANG di server.
  Future<void> deleteMessage(int messageId) => _action(
        'zenime-admin-delete-message',
        {'message_id': messageId},
        'Gagal hapus pesan',
      );
}
