import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'entities.dart';
import 'local_store.dart';

/// Impor SEKALI data lokal app Zenime lama (Kotlin/Room) ke LocalStore Wibuplay.
///
/// Wibuplay memakai applicationId yang sama dengan Zenime, jadi saat meng-update,
/// file Room `databases/zenime_database` masih ada di penyimpanan app. Tanpa
/// migrasi ini, Flutter hanya membaca shared_preferences sehingga favorit,
/// riwayat tonton, dan data download dari Zenime terlihat "hilang".
///
/// Aturan:
/// - Database Room TIDAK pernah diubah atau dihapus (hanya SELECT).
/// - Data yang sudah ada di Wibuplay tidak ditimpa.
/// - Flag selesai hanya ditulis kalau pembacaan berhasil, jadi gagal = dicoba
///   lagi di peluncuran berikutnya.
/// - Tiap tabel dibaca terpisah (DB versi lama mungkin belum punya semua tabel).
class ZenimeRoomMigration {
  ZenimeRoomMigration._();

  static const String _dbName = 'zenime_database';

  static Future<void> run(LocalStore store) async {
    if (store.roomMigrated) return;
    if (!Platform.isAndroid) {
      await store.setRoomMigrated();
      return;
    }
    Database? db;
    try {
      final path = p.join(await getDatabasesPath(), _dbName);
      if (!await File(path).exists()) {
        // Instal baru / bukan update dari Zenime: tidak ada yang diimpor.
        await store.setRoomMigrated();
        return;
      }

      // Dibuka tanpa `version` -> sqflite tidak menjalankan onCreate/onUpgrade,
      // jadi skema Room tidak tersentuh. Hanya SELECT yang dijalankan.
      db = await openDatabase(path, singleInstance: false);

      var readOk = true;

      Future<List<Map<String, Object?>>> table(String sql) async {
        try {
          return await db!.rawQuery(sql);
        } catch (e) {
          // Tabel belum ada di DB versi lama = bukan error.
          final msg = e.toString();
          if (msg.contains('no such table')) return const [];
          readOk = false;
          if (kDebugMode) debugPrint('ZenimeRoomMigration: gagal baca ($sql): $e');
          return const [];
        }
      }

      String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
      int num0(Object? v) => v is num ? v.toInt() : 0;

      final favRows = await table('SELECT * FROM favorites');
      final histRows = await table('SELECT * FROM watch_history');
      final dlRows = await table('SELECT * FROM downloaded_episodes');

      final favorites = <FavoriteEntity>[
        for (final r in favRows)
          if (str(r['id']) != null)
            FavoriteEntity(
              id: r['id'] as String,
              title: str(r['title']) ?? '',
              posterUrl: str(r['posterUrl']) ?? '',
              coverUrl: str(r['posterUrl']) ?? '',
              status: str(r['status']),
              type: str(r['type']),
              timestamp: num0(r['timestamp']),
            ),
      ];

      final history = <WatchHistoryEntity>[
        for (final r in histRows)
          if (str(r['animeId']) != null && str(r['episodeId']) != null)
            WatchHistoryEntity(
              id: '${r['animeId']}_${r['episodeId']}',
              movieId: r['animeId'] as String,
              movieTitle: str(r['animeTitle']) ?? '',
              moviePoster: str(r['posterUrl']) ?? '',
              episodeId: r['episodeId'] as String,
              episodeIndex: str(r['episodeIndex']) ?? '',
              episodeTitle: str(r['episodeTitle']) ?? '',
              playbackPositionMs: num0(r['progressMs']),
              durationMs: num0(r['durationMs']),
              lastWatchedTime: num0(r['lastUpdated']),
            ),
      ];

      final downloads = <DownloadedEpisodeEntity>[
        for (final r in dlRows)
          if (str(r['episodeId']) != null)
            DownloadedEpisodeEntity(
              episodeId: r['episodeId'] as String,
              animeId: str(r['animeId']) ?? '',
              animeTitle: str(r['animeTitle']) ?? '',
              posterUrl: str(r['posterUrl']),
              episodeTitle: str(r['episodeTitle']),
              episodeIndex: str(r['episodeIndex']),
              quality: str(r['quality']),
              localFilePath: str(r['localFilePath']),
              totalBytes: num0(r['totalBytes']),
              downloadedBytes: num0(r['downloadedBytes']),
              status: str(r['status']) ?? 'QUEUED',
              createdAt: num0(r['createdAt']),
              updatedAt: num0(r['updatedAt']),
              episodeThumbnailUrl: str(r['episodeThumbnailUrl']),
              workRequestId: str(r['workRequestId']),
            ),
      ];

      await store.mergeFavorites(favorites);
      await store.mergeHistory(history);
      await store.mergeDownloads(downloads);

      if (readOk) await store.setRoomMigrated();
    } catch (e) {
      // Jangan ganggu start app; dicoba lagi di peluncuran berikutnya.
      if (kDebugMode) debugPrint('ZenimeRoomMigration: gagal: $e');
    } finally {
      await db?.close();
    }
  }
}
