import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'supabase/supabase_client.dart';

/// Badge level yang dipasang tiap user (tabel `level_badge_equipped`).
///
/// Badge level tampil di banyak tempat (chat, komentar, profil, leaderboard,
/// teman); semua uid yang muncul di layar dikumpulkan sebentar lalu diambil
/// sekali jalan, dan disimpan 5 menit. Gagal / tabel belum ada = tampil badge
/// level bawaan.
class LevelBadgeCache extends ChangeNotifier {
  LevelBadgeCache._();

  static final LevelBadgeCache instance = LevelBadgeCache._();

  static const Duration _ttl = Duration(minutes: 5);
  static const Duration _errorTtl = Duration(minutes: 2);
  static final RegExp _uidRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  Dio? _dio;
  Dio get _client => _dio ??= createSupabaseDio();

  final Map<String, String?> _styles = <String, String?>{};
  final Map<String, DateTime> _expires = <String, DateTime>{};
  final Set<String> _queued = <String>{};
  final Set<String> _inFlight = <String>{};
  Timer? _batch;
  bool _notifyScheduled = false;

  /// Badge yang dipasang [uid]; null = bawaan / belum diketahui.
  String? styleFor(String uid) {
    if (!_uidRe.hasMatch(uid)) return null;
    final exp = _expires[uid];
    if (exp == null || DateTime.now().isAfter(exp)) _enqueue(uid);
    return _styles[uid];
  }

  /// Isi langsung (mis. setelah user sendiri membeli / memasang badge).
  void prime(String uid, String? style) {
    if (!_uidRe.hasMatch(uid)) return;
    final changed = !_styles.containsKey(uid) || _styles[uid] != style;
    _styles[uid] = style;
    _expires[uid] = DateTime.now().add(_ttl);
    if (changed) _scheduleNotify();
  }

  void _enqueue(String uid) {
    if (_inFlight.contains(uid) || !_queued.add(uid)) return;
    _batch ??= Timer(const Duration(milliseconds: 60), _flush);
  }

  Future<void> _flush() async {
    _batch = null;
    final uids = _queued.take(60).toList();
    _queued.removeAll(uids);
    if (_queued.isNotEmpty) _batch = Timer(const Duration(milliseconds: 60), _flush);
    if (uids.isEmpty) return;
    _inFlight.addAll(uids);
    try {
      final res = await _client.get<dynamic>(
        'rest/v1/level_badge_equipped',
        queryParameters: {'firebase_uid': 'in.(${uids.join(',')})', 'select': 'firebase_uid,badge_id'},
      );
      final now = DateTime.now();
      final found = <String>{};
      final data = res.data;
      if (data is List) {
        for (final row in data.whereType<Map>()) {
          final uid = row['firebase_uid'];
          final id = row['badge_id'];
          if (uid is! String) continue;
          _styles[uid] = id is String && id.isNotEmpty ? id : null;
          _expires[uid] = now.add(_ttl);
          found.add(uid);
        }
      }
      for (final uid in uids) {
        if (found.contains(uid)) continue;
        _styles[uid] = null;
        _expires[uid] = now.add(_ttl);
      }
      _scheduleNotify();
    } catch (e) {
      if (kDebugMode) debugPrint('LevelBadgeCache: $e');
      final retry = DateTime.now().add(_errorTtl);
      for (final uid in uids) {
        _expires[uid] = retry;
      }
    } finally {
      _inFlight.removeAll(uids);
    }
  }

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
