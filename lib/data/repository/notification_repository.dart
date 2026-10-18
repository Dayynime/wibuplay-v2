import 'package:dio/dio.dart';

import '../models/notification_models.dart';
import 'authed_function.dart';

/// Lonceng + token push lewat Edge Function `zenime-notify`. uid selalu
/// diambil server dari token Firebase, jadi user cuma bisa baca/ubah
/// notifikasinya sendiri.
class NotificationRepository {
  NotificationRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'zenime-notify';
  static const int pageSize = 30;

  Future<NotificationPage> list({int? beforeId}) async {
    final d = await callAuthedFunction(_dio, _fn, {
      'action': 'list',
      'limit': pageSize,
      if (beforeId != null) 'before_id': beforeId,
    });
    if (d is! Map) return const NotificationPage();
    final raw = d['notifications'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <AppNotification>[];
    return NotificationPage(items: items, unread: (d['unread'] as num?)?.toInt() ?? 0);
  }

  Future<int> unreadCount() async {
    final d = await callAuthedFunction(_dio, _fn, {'action': 'unread_count'});
    return d is Map ? (d['unread'] as num?)?.toInt() ?? 0 : 0;
  }

  /// [ids] kosong = tandai semua dibaca.
  Future<void> markRead([List<int> ids = const []]) async {
    await callAuthedFunction(_dio, _fn, {
      'action': 'mark_read',
      if (ids.isNotEmpty) 'ids': ids,
    });
  }

  Future<void> clearAll() async {
    await callAuthedFunction(_dio, _fn, {'action': 'clear'});
  }

  Future<void> registerToken(String token) async {
    await callAuthedFunction(_dio, _fn, {
      'action': 'register_token',
      'token': token,
      'platform': 'android',
    });
  }

  Future<void> unregisterToken(String token) async {
    await callAuthedFunction(_dio, _fn, {
      'action': 'unregister_token',
      'token': token,
    });
  }
}
