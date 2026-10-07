import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/premium_access.dart';
import '../local/entities.dart';
import '../local/local_store.dart';
import '../models/stream_data.dart';

/// Download episode untuk nonton offline (port EpisodeDownloadManager.kt).
/// KHUSUS Premium -- gating dicek di pemanggil lewat [isDownloadAllowed].
///
/// Memakai android.app.DownloadManager sistem lewat MethodChannel
/// `wibuplay/download` (lihat android_native/MainActivity.kt), jadi download
/// tetap jalan walau app di-swipe. Dart hanya mencatat status/progres ke
/// [LocalStore] (polling tiap 500ms selama app hidup, disambung lagi lewat
/// [reconcileActiveDownloads] saat app dibuka).
///
/// File selalu di getExternalFilesDir(MOVIES) (app-private), SAMA dengan
/// Zenime, sehingga file hasil download Zenime langsung terbaca.
class EpisodeDownloadManager {
  EpisodeDownloadManager(this._store);

  final LocalStore _store;

  static const MethodChannel _ch = MethodChannel('wibuplay/download');

  static const Map<String, String> _headers = {
    'Referer': 'https://animeinweb.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  // Kode status DownloadManager Android.
  static const int _statusSuccessful = 8;
  static const int _statusFailed = 16;

  final Map<String, Timer> _pollers = {};

  static String _sanitize(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  Future<Directory> _moviesDir() async {
    try {
      final dirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (dirs != null && dirs.isNotEmpty) return dirs.first;
    } catch (_) {}
    final base = await getExternalStorageDirectory();
    if (base == null) throw StateError('Penyimpanan tidak tersedia');
    return Directory('${base.path}/Movies');
  }

  Future<File> _destinationFile(String animeId, String episodeId) async {
    final root = await _moviesDir();
    final dir = Directory('${root.path}/${_sanitize(animeId)}');
    await dir.create(recursive: true);
    return File('${dir.path}/${_sanitize(episodeId)}.mp4');
  }

  /// Pilihan kualitas download dari data stream yang BARU diambil: tanpa link
  /// kosong, unik per label kualitas, tertinggi dulu. Link-nya signed URL yang
  /// cepat kedaluwarsa, jadi harus langsung dipakai [startDownload].
  static List<StreamServer> qualityOptions(StreamData data) {
    final seen = <String>{};
    final out = <StreamServer>[];
    for (final s in data.server) {
      final link = s.link;
      if (link == null || link.trim().isEmpty) continue;
      if (!seen.add(s.quality ?? '')) continue;
      out.add(s);
    }
    out.sort((a, b) => (qualityValueP(b.quality) ?? -1).compareTo(qualityValueP(a.quality) ?? -1));
    return out;
  }

  /// Mulai download satu episode. Mengembalikan pesan error, atau null kalau sukses.
  Future<String?> startDownload({
    required String episodeId,
    required String animeId,
    required String animeTitle,
    String? posterUrl,
    String? episodeTitle,
    String? episodeIndex,
    String? quality,
    required String videoUrl,
    String? episodeThumbnailUrl,
  }) async {
    final existing = _store.downloadFor(episodeId);
    if (existing != null && (existing.isCompleted || existing.isActive)) {
      return null; // sudah ada / sedang jalan
    }
    if (_store.activeDownloadCount >= kMaxActiveDownloads) {
      return 'Batas maksimal $kMaxActiveDownloads episode offline sudah tercapai. '
          'Hapus beberapa episode yang sudah didownload dulu.';
    }

    try {
      final file = await _destinationFile(animeId, episodeId);
      if (await file.exists()) await file.delete();

      final id = await _ch.invokeMethod<int>('enqueue', {
        'url': videoUrl,
        'path': file.path,
        'title': animeTitle,
        'description': (episodeTitle != null && episodeTitle.isNotEmpty)
            ? episodeTitle
            : 'Episode ${episodeIndex ?? ''}',
        'headers': _headers,
      });
      if (id == null) return 'Gagal memulai download';

      final now = DateTime.now().millisecondsSinceEpoch;
      await _store.upsertDownload(
        DownloadedEpisodeEntity(
          episodeId: episodeId,
          animeId: animeId,
          animeTitle: animeTitle,
          posterUrl: posterUrl,
          episodeTitle: episodeTitle,
          episodeIndex: episodeIndex,
          quality: quality,
          localFilePath: file.path,
          status: 'QUEUED',
          workRequestId: id.toString(),
          createdAt: now,
          updatedAt: now,
          episodeThumbnailUrl: episodeThumbnailUrl,
        ),
      );
      _poll(episodeId, id);
      return null;
    } on PlatformException catch (e) {
      return 'Gagal memulai download${e.message == null ? '' : ': ${e.message}'}';
    } on MissingPluginException {
      return 'Download hanya tersedia di Android';
    } catch (e) {
      return 'Gagal memulai download';
    }
  }

  /// File lokal kalau episode ini sudah COMPLETED dan filenya masih ada di disk.
  File? localFileFor(String episodeId) {
    final entry = _store.downloadFor(episodeId);
    if (entry == null || !entry.isCompleted) return null;
    final path = entry.localFilePath;
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  }

  /// Dipanggil sekali saat app dibuka: DownloadManager sistem jalan terus walau
  /// app sempat mati, jadi cuma menyambung lagi polling progres baris yang
  /// masih QUEUED/DOWNLOADING.
  void reconcileActiveDownloads() {
    for (final e in List<DownloadedEpisodeEntity>.of(_store.downloads)) {
      if (!e.isActive) continue;
      final id = int.tryParse(e.workRequestId ?? '');
      if (id != null) {
        _poll(e.episodeId, id);
      } else {
        unawaited(_markFailed(e.episodeId));
      }
    }
  }

  void _poll(String episodeId, int downloadId) {
    _pollers[episodeId]?.cancel();
    var busy = false;
    var tick = 0;
    _pollers[episodeId] = Timer.periodic(const Duration(milliseconds: 500), (t) async {
      if (busy) return;
      busy = true;
      try {
        Map<dynamic, dynamic>? row;
        try {
          row = await _ch.invokeMapMethod<dynamic, dynamic>('query', {'id': downloadId});
        } catch (_) {
          row = null;
        }
        if (row == null) {
          t.cancel();
          _pollers.remove(episodeId);
          await _markFailed(episodeId);
          return;
        }
        final status = (row['status'] as num?)?.toInt() ?? 0;
        final bytes = (row['bytes'] as num?)?.toInt() ?? 0;
        final total = (row['total'] as num?)?.toInt() ?? 0;
        if (status == _statusSuccessful) {
          t.cancel();
          _pollers.remove(episodeId);
          await _update(episodeId, bytes, total, 'COMPLETED', persist: true);
        } else if (status == _statusFailed) {
          t.cancel();
          _pollers.remove(episodeId);
          await _markFailed(episodeId);
        } else {
          tick++;
          // Progres sering berubah: cukup update memori/UI, tulis ke disk tiap ~5 detik.
          await _update(episodeId, bytes, total, 'DOWNLOADING', persist: tick % 10 == 0);
        }
      } finally {
        busy = false;
      }
    });
  }

  Future<void> _update(
    String episodeId,
    int bytes,
    int total,
    String status, {
    required bool persist,
  }) async {
    final cur = _store.downloadFor(episodeId);
    if (cur == null) return;
    await _store.upsertDownload(
      cur.copyWith(
        downloadedBytes: bytes,
        totalBytes: total > 0 ? total : cur.totalBytes,
        status: status,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      persist: persist || status != cur.status,
    );
  }

  Future<void> _markFailed(String episodeId) async {
    final cur = _store.downloadFor(episodeId);
    if (cur == null) return;
    await _store.upsertDownload(
      cur.copyWith(status: 'FAILED', updatedAt: DateTime.now().millisecondsSinceEpoch),
    );
  }

  /// Batalkan download yang sedang jalan (kalau ada), hapus file + barisnya.
  Future<void> deleteDownload(String episodeId) async {
    final entry = _store.downloadFor(episodeId);
    if (entry == null) return;
    _pollers.remove(episodeId)?.cancel();
    final id = int.tryParse(entry.workRequestId ?? '');
    if (id != null) {
      try {
        await _ch.invokeMethod<int>('remove', {'id': id});
      } catch (_) {}
    }
    final path = entry.localFilePath;
    if (path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (e) {
        if (kDebugMode) debugPrint('EpisodeDownloadManager: gagal hapus file: $e');
      }
    }
    await _store.deleteDownloadRow(episodeId);
  }
}
