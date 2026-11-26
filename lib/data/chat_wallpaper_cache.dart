import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'models/wallpaper_models.dart';
import 'supabase/supabase_client.dart';

/// Wallpaper yang tampil sebagai latar bubble chat tiap user.
///
/// Sama dengan wallpaper komentar (`wp_equipped_view`); kalau user tidak
/// memasang wallpaper komentar, dipakai wallpaper banner profil
/// (`wp_banner_view`). uid yang muncul di layar dikumpulkan sebentar lalu
/// diambil sekali jalan, disimpan 5 menit. Gagal = bubble biasa.
///
/// Nama wallpaper (untuk badge) dicoba diambil dari kolom `name` di view;
/// kalau view belum punya kolom itu, otomatis jatuh ke tanpa nama.
class ChatWallpaperCache extends ChangeNotifier {
  ChatWallpaperCache._();

  static final ChatWallpaperCache instance = ChatWallpaperCache._();

  static const Duration _ttl = Duration(minutes: 5);
  static final RegExp _uidRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  Dio? _dio;
  Dio get _client => _dio ??= createSupabaseDio();

  final Map<String, ChatWallpaper?> _items = {};
  final Map<String, DateTime> _expires = {};
  final Set<String> _queued = {};
  final Set<String> _inFlight = {};
  Timer? _batch;
  bool _notifyScheduled = false;

  /// null = view tidak punya kolom `name` (sudah dicoba sekali).
  bool _nameColumn = true;

  ChatWallpaper? forUid(String uid) {
    if (!_uidRe.hasMatch(uid)) return null;
    final exp = _expires[uid];
    if (exp == null || DateTime.now().isAfter(exp)) _enqueue(uid);
    return _items[uid];
  }

  void _enqueue(String uid) {
    if (_inFlight.contains(uid) || !_queued.add(uid)) return;
    _batch ??= Timer(const Duration(milliseconds: 80), _flush);
  }

  Future<List<Map<String, dynamic>>> _rows(String view, List<String> uids) async {
    Future<List<Map<String, dynamic>>> get(String select) async {
      final res = await _client.get<dynamic>(
        'rest/v1/$view',
        queryParameters: {'firebase_uid': 'in.(${uids.join(',')})', 'select': select},
      );
      final d = res.data;
      return d is List ? d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
    }

    const base = 'firebase_uid,wallpaper_id,rarity,file_name';
    if (_nameColumn) {
      try {
        return await get('$base,name');
      } on DioException catch (e) {
        // 400 = kolom `name` tidak ada di view: jangan coba lagi.
        if (e.response?.statusCode == 400) {
          _nameColumn = false;
        } else {
          rethrow;
        }
      }
    }
    return get(base);
  }

  Future<void> _flush() async {
    _batch = null;
    final uids = _queued.take(60).toList();
    _queued.removeAll(uids);
    if (_queued.isNotEmpty) _batch = Timer(const Duration(milliseconds: 80), _flush);
    if (uids.isEmpty) return;
    _inFlight.addAll(uids);
    try {
      final found = <String, ChatWallpaper>{};
      void take(List<Map<String, dynamic>> rows) {
        for (final m in rows) {
          final uid = m['firebase_uid'];
          final w = CommentWallpaper.fromJson(m);
          if (uid is! String || w == null || found.containsKey(uid)) continue;
          final name = m['name'];
          found[uid] = ChatWallpaper(w, name is String && name.trim().isNotEmpty ? name.trim() : null);
        }
      }

      take(await _rows('wp_equipped_view', uids));
      final rest = uids.where((u) => !found.containsKey(u)).toList();
      if (rest.isNotEmpty) {
        try {
          take(await _rows('wp_banner_view', rest));
        } catch (_) {
          // view banner belum ada: abaikan
        }
      }
      final now = DateTime.now();
      for (final uid in uids) {
        _items[uid] = found[uid];
        _expires[uid] = now.add(_ttl);
      }
      if (found.isNotEmpty) _scheduleNotify();
    } catch (_) {
      final retry = DateTime.now().add(const Duration(minutes: 2));
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

class ChatWallpaper {
  const ChatWallpaper(this.wallpaper, this.name);

  final CommentWallpaper wallpaper;

  /// Nama wallpaper untuk badge (null = view belum menyediakan nama).
  final String? name;
}
