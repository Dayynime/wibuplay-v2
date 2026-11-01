import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'supabase/supabase_client.dart';

/// Badge yang dipasang tiap clan, dicari lewat TAG clan (tag unik di DB).
///
/// Tag clan tampil di banyak tempat (chat, komentar, profil, leaderboard)
/// dan sumber datanya beda-beda; semuanya cuma tahu teks tag. Jadi badge
/// diambil terpisah di sini: semua tag yang muncul di layar dikumpulkan
/// sebentar lalu diambil sekali jalan (`clans?tag=in.(...)`), dan disimpan
/// 5 menit. Gagal / kolom belum ada = tampil badge pelangi bawaan.
class ClanBadgeCache extends ChangeNotifier {
  ClanBadgeCache._();

  static final ClanBadgeCache instance = ClanBadgeCache._();

  static const Duration _ttl = Duration(minutes: 5);
  static const Duration _errorTtl = Duration(minutes: 2);
  static final RegExp _tagRe = RegExp(r'^[A-Z0-9]{2,6}$');

  Dio? _dio;
  Dio get _client => _dio ??= createSupabaseDio();

  final Map<String, String?> _styles = <String, String?>{};
  final Map<String, DateTime> _expires = <String, DateTime>{};
  final Set<String> _queued = <String>{};
  final Set<String> _inFlight = <String>{};
  Timer? _batch;
  bool _notifyScheduled = false;

  static String _key(String tag) => tag.trim().toUpperCase();

  /// Badge clan bertag [tag]; null = belum dipasang / belum diketahui.
  /// Kalau belum ada atau sudah kedaluwarsa, otomatis diambil di latar.
  String? styleFor(String tag) {
    final k = _key(tag);
    if (!_tagRe.hasMatch(k)) return null;
    final exp = _expires[k];
    if (exp == null || DateTime.now().isAfter(exp)) _enqueue(k);
    return _styles[k];
  }

  /// Isi langsung dari data yang sudah ada (mis. objek Clan), tanpa request.
  void prime(String tag, String? style) {
    final k = _key(tag);
    if (!_tagRe.hasMatch(k)) return;
    final changed = _styles[k] != style || !_styles.containsKey(k);
    _styles[k] = style;
    _expires[k] = DateTime.now().add(_ttl);
    if (changed) _scheduleNotify();
  }

  void _enqueue(String k) {
    if (_inFlight.contains(k) || !_queued.add(k)) return;
    _batch ??= Timer(const Duration(milliseconds: 60), _flush);
  }

  Future<void> _flush() async {
    _batch = null;
    final tags = _queued.take(60).toList();
    _queued.removeAll(tags);
    if (_queued.isNotEmpty) _batch = Timer(const Duration(milliseconds: 60), _flush);
    if (tags.isEmpty) return;
    _inFlight.addAll(tags);
    try {
      final res = await _client.get<dynamic>(
        'rest/v1/clans',
        queryParameters: {'tag': 'in.(${tags.join(',')})', 'select': 'tag,badge_style'},
      );
      final now = DateTime.now();
      final found = <String>{};
      final data = res.data;
      if (data is List) {
        for (final row in data.whereType<Map>()) {
          final tag = row['tag'];
          if (tag is! String) continue;
          final k = _key(tag);
          final st = row['badge_style'];
          _styles[k] = st is String && st.isNotEmpty ? st : null;
          _expires[k] = now.add(_ttl);
          found.add(k);
        }
      }
      for (final k in tags) {
        if (found.contains(k)) continue;
        _styles[k] = null;
        _expires[k] = now.add(_ttl);
      }
      _scheduleNotify();
    } catch (e) {
      if (kDebugMode) debugPrint('ClanBadgeCache: $e');
      final retry = DateTime.now().add(_errorTtl);
      for (final k in tags) {
        _expires[k] = retry;
      }
    } finally {
      _inFlight.removeAll(tags);
    }
  }

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    // Jangan memberi tahu listener di tengah build.
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
