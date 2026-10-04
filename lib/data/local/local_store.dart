import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'entities.dart';

/// Pengganti Room (AppDao): favorit + riwayat tonton disimpan sebagai JSON di
/// shared_preferences. Daftarnya kecil, jadi tidak perlu SQLite/codegen.
/// Setiap perubahan membuat list baru lalu memanggil notifyListeners(),
/// sehingga UI (Riverpod `select`) ikut diperbarui seperti Flow di Room.
class LocalStore extends ChangeNotifier {
  LocalStore._(this._prefs, this._favorites, this._history);

  static const String _favKey = 'favorites_v1';
  static const String _histKey = 'watch_history_v1';

  final SharedPreferences _prefs;
  List<FavoriteEntity> _favorites;
  List<WatchHistoryEntity> _history;

  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = _readList<FavoriteEntity>(prefs, _favKey, FavoriteEntity.fromJson)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final hist =
        _readList<WatchHistoryEntity>(prefs, _histKey, WatchHistoryEntity.fromJson)
          ..sort((a, b) => b.lastWatchedTime.compareTo(a.lastWatchedTime));
    return LocalStore._(prefs, favs, hist);
  }

  static List<T> _readList<T>(
    SharedPreferences prefs,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      final out = <T>[];
      for (final e in decoded) {
        if (e is Map) {
          out.add(fromJson(Map<String, dynamic>.from(e)));
        }
      }
      return out;
    } catch (_) {
      return <T>[];
    }
  }

  // ---- Favorites (urut timestamp terbaru dulu) ----

  List<FavoriteEntity> get favorites => _favorites;

  bool isFavorite(String id) => _favorites.any((f) => f.id == id);

  Future<void> insertFavorite(FavoriteEntity favorite) async {
    _favorites = [favorite, ..._favorites.where((f) => f.id != favorite.id)];
    await _saveFavorites();
  }

  Future<void> deleteFavorite(String id) async {
    _favorites = _favorites.where((f) => f.id != id).toList();
    await _saveFavorites();
  }

  Future<void> _saveFavorites() async {
    notifyListeners();
    await _prefs.setString(
      _favKey,
      jsonEncode(_favorites.map((e) => e.toJson()).toList()),
    );
  }

  // ---- Watch history (urut lastWatchedTime terbaru dulu) ----

  List<WatchHistoryEntity> get history => _history;

  WatchHistoryEntity? latestHistoryForMovie(String movieId) {
    for (final h in _history) {
      if (h.movieId == movieId) return h;
    }
    return null;
  }

  WatchHistoryEntity? historyForEpisode(String episodeId) {
    for (final h in _history) {
      if (h.episodeId == episodeId) return h;
    }
    return null;
  }

  Future<void> insertOrUpdateHistory(WatchHistoryEntity entry) async {
    final next = [entry, ..._history.where((h) => h.id != entry.id)]
      ..sort((a, b) => b.lastWatchedTime.compareTo(a.lastWatchedTime));
    _history = next;
    await _saveHistory();
  }

  Future<void> deleteHistory(String id) async {
    _history = _history.where((h) => h.id != id).toList();
    await _saveHistory();
  }

  Future<void> clearAllHistory() async {
    _history = <WatchHistoryEntity>[];
    await _saveHistory();
  }

  Future<void> _saveHistory() async {
    notifyListeners();
    await _prefs.setString(
      _histKey,
      jsonEncode(_history.map((e) => e.toJson()).toList()),
    );
  }
}
