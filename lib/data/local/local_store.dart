import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'entities.dart';

/// Pengganti Room (AppDao): favorit + riwayat tonton disimpan sebagai JSON di
/// shared_preferences. Daftarnya kecil, jadi tidak perlu SQLite/codegen.
/// Setiap perubahan membuat list baru lalu memanggil notifyListeners(),
/// sehingga UI (Riverpod `select`) ikut diperbarui seperti Flow di Room.
class LocalStore extends ChangeNotifier {
  LocalStore._(this._prefs, this._favorites, this._history, this._downloads);

  static const String _favKey = 'favorites_v1';
  static const String _histKey = 'watch_history_v1';
  static const String _dlKey = 'zenime_downloads_v1';
  static const String _roomMigratedKey = 'zenime_room_migrated_v1';

  final SharedPreferences _prefs;
  List<FavoriteEntity> _favorites;
  List<WatchHistoryEntity> _history;
  List<DownloadedEpisodeEntity> _downloads;

  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = _readList<FavoriteEntity>(prefs, _favKey, FavoriteEntity.fromJson)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final hist =
        _readList<WatchHistoryEntity>(prefs, _histKey, WatchHistoryEntity.fromJson)
          ..sort((a, b) => b.lastWatchedTime.compareTo(a.lastWatchedTime));
    final dls = _readList<DownloadedEpisodeEntity>(
      prefs,
      _dlKey,
      DownloadedEpisodeEntity.fromJson,
    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return LocalStore._(prefs, favs, hist, dls);
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

  // ---- Pop up pengumuman: id terakhir yang ditutup user ----

  static const String _lastSeenPopupKey = 'last_seen_popup_id';

  /// Kosong = belum pernah menutup popup apa pun.
  String get lastSeenPopupId => _prefs.getString(_lastSeenPopupKey) ?? '';

  Future<void> setLastSeenPopupId(String id) =>
      _prefs.setString(_lastSeenPopupKey, id);

  // ---- Pengaturan pemutar (sama dengan Zenime: default aktif) ----

  static const String _autoSkipIntroKey = 'player_auto_skip_intro';
  static const String _autoSkipOutroKey = 'player_auto_skip_outro';

  bool get autoSkipIntro => _prefs.getBool(_autoSkipIntroKey) ?? true;
  bool get autoSkipOutro => _prefs.getBool(_autoSkipOutroKey) ?? true;

  Future<void> setAutoSkipIntro(bool enabled) async {
    await _prefs.setBool(_autoSkipIntroKey, enabled);
    notifyListeners();
  }

  Future<void> setAutoSkipOutro(bool enabled) async {
    await _prefs.setBool(_autoSkipOutroKey, enabled);
    notifyListeners();
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

  // ---- Migrasi dari Room Zenime (zenime_database) ----

  /// true = data Room Zenime sudah diimpor (atau memang tidak ada).
  bool get roomMigrated => _prefs.getBool(_roomMigratedKey) ?? false;

  Future<void> setRoomMigrated() => _prefs.setBool(_roomMigratedKey, true);

  /// Gabungkan favorit hasil migrasi. Data yang sudah ada di Wibuplay tidak
  /// ditimpa (lebih baru). Mengembalikan jumlah item baru.
  Future<int> mergeFavorites(List<FavoriteEntity> incoming) async {
    final have = _favorites.map((f) => f.id).toSet();
    final fresh = incoming.where((f) => f.id.isNotEmpty && !have.contains(f.id)).toList();
    if (fresh.isEmpty) return 0;
    _favorites = [..._favorites, ...fresh]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    await _saveFavorites();
    return fresh.length;
  }

  Future<int> mergeHistory(List<WatchHistoryEntity> incoming) async {
    final have = _history.map((h) => h.id).toSet();
    final fresh = incoming.where((h) => h.movieId.isNotEmpty && !have.contains(h.id)).toList();
    if (fresh.isEmpty) return 0;
    _history = [..._history, ...fresh]
      ..sort((a, b) => b.lastWatchedTime.compareTo(a.lastWatchedTime));
    await _saveHistory();
    return fresh.length;
  }

  // ---- Download Zenime (hanya data; belum ada UI/pemutaran offline) ----

  List<DownloadedEpisodeEntity> get downloads => _downloads;

  Future<int> mergeDownloads(List<DownloadedEpisodeEntity> incoming) async {
    final have = _downloads.map((d) => d.episodeId).toSet();
    final fresh =
        incoming.where((d) => d.episodeId.isNotEmpty && !have.contains(d.episodeId)).toList();
    if (fresh.isEmpty) return 0;
    _downloads = [..._downloads, ...fresh]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
    await _prefs.setString(
      _dlKey,
      jsonEncode(_downloads.map((e) => e.toJson()).toList()),
    );
    return fresh.length;
  }
}
