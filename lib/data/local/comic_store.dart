import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Favorit komik (port ComicFavoriteEntity). [slug] = kunci komik (ComicKey).
class ComicFavorite {
  const ComicFavorite({
    required this.slug,
    required this.title,
    this.cover,
    this.status,
    required this.timestamp,
  });

  final String slug;
  final String title;
  final String? cover;
  final String? status;
  final int timestamp;

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'title': title,
        'cover': cover,
        'status': status,
        'timestamp': timestamp,
      };

  factory ComicFavorite.fromJson(Map<String, dynamic> j) => ComicFavorite(
        slug: j['slug'] as String,
        title: (j['title'] as String?) ?? '',
        cover: j['cover'] as String?,
        status: j['status'] as String?,
        timestamp: (j['timestamp'] as num?)?.toInt() ?? 0,
      );
}

/// Progress baca (port ComicReadingProgressEntity): SATU baris per komik,
/// berisi chapter TERAKHIR yang dibaca + posisi scroll di dalamnya.
/// [comicSlug] = kunci komik (ComicKey).
///
/// Posisi = item (halaman gambar) pertama yang terlihat + [scrollAlignment]
/// (tepi atas item relatif tinggi layar; <= 0 berarti item sudah tergulir
/// sebagian ke atas).
class ComicProgress {
  const ComicProgress({
    required this.comicSlug,
    required this.comicTitle,
    this.comicCover,
    required this.chapterSlug,
    this.chapterLabel,
    this.scrollItemIndex = 0,
    this.scrollAlignment = 0.0,
    required this.updatedAt,
  });

  final String comicSlug;
  final String comicTitle;
  final String? comicCover;
  final String chapterSlug;
  final String? chapterLabel;
  final int scrollItemIndex;
  final double scrollAlignment;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'comicSlug': comicSlug,
        'comicTitle': comicTitle,
        'comicCover': comicCover,
        'chapterSlug': chapterSlug,
        'chapterLabel': chapterLabel,
        'scrollItemIndex': scrollItemIndex,
        'scrollAlignment': scrollAlignment,
        'updatedAt': updatedAt,
      };

  factory ComicProgress.fromJson(Map<String, dynamic> j) => ComicProgress(
        comicSlug: j['comicSlug'] as String,
        comicTitle: (j['comicTitle'] as String?) ?? '',
        comicCover: j['comicCover'] as String?,
        chapterSlug: (j['chapterSlug'] as String?) ?? '',
        chapterLabel: j['chapterLabel'] as String?,
        scrollItemIndex: (j['scrollItemIndex'] as num?)?.toInt() ?? 0,
        scrollAlignment: (j['scrollAlignment'] as num?)?.toDouble() ?? 0.0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Penyimpanan lokal komik (pengganti tabel Room comic_favorites &
/// comic_reading_progress). Sama seperti LocalStore: JSON di shared_preferences.
///
/// Dimuat async di konstruktor; yang butuh data pasti sudah terbaca
/// (mis. reader memulihkan posisi) menunggu [ready] dulu.
class ComicStore extends ChangeNotifier {
  ComicStore() {
    ready = _load();
  }

  static const String _favKey = 'comic_favorites_v1';
  static const String _progKey = 'comic_progress_v1';
  static const String _migratedKey = 'zenime_comic_room_migrated_v1';

  late final Future<void> ready;
  SharedPreferences? _prefs;
  List<ComicFavorite> _favorites = [];
  List<ComicProgress> _progress = [];

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _favorites = _readList(prefs, _favKey, ComicFavorite.fromJson)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _progress = _readList(prefs, _progKey, ComicProgress.fromJson)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
    try {
      await _migrateFromZenimeRoom(prefs);
    } catch (e) {
      if (kDebugMode) debugPrint('ComicStore: migrasi Room gagal: $e');
    }
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
          try {
            out.add(fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
      return out;
    } catch (_) {
      return <T>[];
    }
  }

  // ---- Favorit (terbaru dulu) ----

  List<ComicFavorite> get favorites => _favorites;

  bool isFavorite(String slug) => _favorites.any((f) => f.slug == slug);

  Future<void> addFavorite(ComicFavorite f) async {
    _favorites = [f, ..._favorites.where((x) => x.slug != f.slug)];
    await _saveFavorites();
  }

  Future<void> removeFavorite(String slug) async {
    _favorites = _favorites.where((f) => f.slug != slug).toList();
    await _saveFavorites();
  }

  Future<void> _saveFavorites() async {
    notifyListeners();
    await _prefs?.setString(
      _favKey,
      jsonEncode(_favorites.map((e) => e.toJson()).toList()),
    );
  }

  // ---- Progress baca (terbaru dulu) ----

  List<ComicProgress> get progress => _progress;

  ComicProgress? progressFor(String comicSlug) {
    for (final p in _progress) {
      if (p.comicSlug == comicSlug) return p;
    }
    return null;
  }

  Future<void> upsertProgress(ComicProgress entry) async {
    _progress = [entry, ..._progress.where((p) => p.comicSlug != entry.comicSlug)]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveProgress();
  }

  Future<void> deleteProgress(String comicSlug) async {
    _progress = _progress.where((p) => p.comicSlug != comicSlug).toList();
    await _saveProgress();
  }

  Future<void> _saveProgress() async {
    notifyListeners();
    await _prefs?.setString(
      _progKey,
      jsonEncode(_progress.map((e) => e.toJson()).toList()),
    );
  }

  // ---- Impor SEKALI dari Room Zenime (tabel comic_*) ----
  //
  // Wibuplay memakai applicationId yang sama dengan Zenime, jadi saat
  // meng-update file Room `zenime_database` masih ada. Aturan sama dengan
  // ZenimeRoomMigration: hanya SELECT, tidak menimpa data yang sudah ada,
  // flag selesai hanya ditulis kalau pembacaan berhasil.
  Future<void> _migrateFromZenimeRoom(SharedPreferences prefs) async {
    if (prefs.getBool(_migratedKey) ?? false) return;
    if (!Platform.isAndroid) {
      await prefs.setBool(_migratedKey, true);
      return;
    }
    Database? db;
    try {
      final path = p.join(await getDatabasesPath(), 'zenime_database');
      if (!await File(path).exists()) {
        await prefs.setBool(_migratedKey, true);
        return;
      }
      db = await openDatabase(path, singleInstance: false);

      var readOk = true;
      Future<List<Map<String, Object?>>> table(String sql) async {
        try {
          return await db!.rawQuery(sql);
        } catch (e) {
          if (e.toString().contains('no such table')) return const [];
          readOk = false;
          if (kDebugMode) debugPrint('ComicStore: gagal baca ($sql): $e');
          return const [];
        }
      }

      String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
      int num0(Object? v) => v is num ? v.toInt() : 0;

      final favRows = await table('SELECT * FROM comic_favorites');
      final progRows = await table('SELECT * FROM comic_reading_progress');

      final haveFav = _favorites.map((f) => f.slug).toSet();
      final freshFav = <ComicFavorite>[
        for (final r in favRows)
          if (str(r['slug']) != null && !haveFav.contains(r['slug']))
            ComicFavorite(
              slug: r['slug'] as String,
              title: str(r['title']) ?? '',
              cover: str(r['cover']),
              status: str(r['status']),
              timestamp: num0(r['timestamp']),
            ),
      ];

      final haveProg = _progress.map((e) => e.comicSlug).toSet();
      final freshProg = <ComicProgress>[
        for (final r in progRows)
          if (str(r['comicSlug']) != null &&
              str(r['chapterSlug']) != null &&
              !haveProg.contains(r['comicSlug']))
            ComicProgress(
              comicSlug: r['comicSlug'] as String,
              comicTitle: str(r['comicTitle']) ?? '',
              comicCover: str(r['comicCover']),
              chapterSlug: r['chapterSlug'] as String,
              chapterLabel: str(r['chapterLabel']),
              // Offset piksel Compose tidak bisa dipetakan; mulai dari awal item.
              scrollItemIndex: num0(r['scrollItemIndex']),
              scrollAlignment: 0.0,
              updatedAt: num0(r['updatedAt']),
            ),
      ];

      if (freshFav.isNotEmpty) {
        _favorites = [..._favorites, ...freshFav]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await _saveFavorites();
      }
      if (freshProg.isNotEmpty) {
        _progress = [..._progress, ...freshProg]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        await _saveProgress();
      }
      if (readOk) await prefs.setBool(_migratedKey, true);
    } catch (e) {
      if (kDebugMode) debugPrint('ComicStore: migrasi gagal: $e');
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }
}
