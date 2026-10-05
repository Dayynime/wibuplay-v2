import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../local/entities.dart';

/// Sinkronisasi Favorit & Riwayat Tontonan ke Supabase (`user_favorites`,
/// `user_watch_history`), sama seperti PublicProfileRepository.kt di Zenime.
///
/// LocalStore tetap sumber utama buat pemilik data. Semua fungsi di sini
/// best-effort: dipanggil SETELAH tulis lokal berhasil, dan gagal sync tidak
/// dilempar balik (supaya nonton/favorit tidak terganggu saat offline).
/// Status HTTP non-2xx dicek manual (validateStatus) lalu di-log.
class PublicProfileRepository {
  PublicProfileRepository(this._dio);

  final Dio _dio;

  static final Options _anyStatus = Options(validateStatus: (_) => true);

  void _logIfFailed(String action, Response<dynamic> res) {
    final code = res.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      debugPrint('PublicProfileSync: $action GAGAL -- HTTP $code: ${res.data}');
    }
  }

  Future<void> syncFavoriteAdded(String firebaseUid, FavoriteEntity fav) async {
    try {
      final res = await _dio.post<dynamic>(
        'rest/v1/user_favorites',
        queryParameters: {'on_conflict': 'firebase_uid,anime_id'},
        data: {
          'firebase_uid': firebaseUid,
          'anime_id': fav.id,
          'title': fav.title,
          'poster_url': fav.posterUrl,
          'type': fav.type,
          'status': fav.status,
        },
        options: _anyStatus.copyWith(
          headers: {'Prefer': 'resolution=merge-duplicates'},
        ),
      );
      _logIfFailed('syncFavoriteAdded', res);
    } catch (e) {
      debugPrint('PublicProfileSync: syncFavoriteAdded EXCEPTION: $e');
    }
  }

  Future<void> syncFavoriteRemoved(String firebaseUid, String animeId) async {
    try {
      final res = await _dio.delete<dynamic>(
        'rest/v1/user_favorites',
        queryParameters: {
          'firebase_uid': 'eq.$firebaseUid',
          'anime_id': 'eq.$animeId',
        },
        options: _anyStatus,
      );
      _logIfFailed('syncFavoriteRemoved', res);
    } catch (e) {
      debugPrint('PublicProfileSync: syncFavoriteRemoved EXCEPTION: $e');
    }
  }

  /// Lewat RPC `upsert_watch_history` (SECURITY DEFINER) supaya lolos RLS
  /// saat toggle "Riwayat publik" mati.
  /// Progress disimpan tiap ~5 detik saat nonton; ke server cukup tiap
  /// [_progressMinGap] per episode supaya tidak spam request.
  static const Duration _progressMinGap = Duration(seconds: 20);
  final Map<String, DateTime> _lastProgressSync = {};

  Future<void> syncWatchProgress(
    String firebaseUid,
    WatchHistoryEntity h,
  ) async {
    final key = '${h.movieId}|${h.episodeId}';
    final now = DateTime.now();
    final last = _lastProgressSync[key];
    if (last != null && now.difference(last) < _progressMinGap) return;
    _lastProgressSync[key] = now;
    try {
      final res = await _dio.post<dynamic>(
        'rest/v1/rpc/upsert_watch_history',
        data: {
          'firebase_uid': firebaseUid,
          'anime_id': h.movieId,
          'anime_title': h.movieTitle,
          'poster_url': h.moviePoster,
          'episode_id': h.episodeId,
          'episode_title': h.episodeTitle,
          'episode_index': h.episodeIndex,
          'progress_ms': h.playbackPositionMs,
          'duration_ms': h.durationMs,
        },
        options: _anyStatus,
      );
      _logIfFailed('syncWatchProgress', res);
    } catch (e) {
      debugPrint('PublicProfileSync: syncWatchProgress EXCEPTION: $e');
    }
  }

  Future<void> syncHistoryRemoved(
    String firebaseUid,
    String animeId,
    String episodeId,
  ) async {
    _lastProgressSync.remove('$animeId|$episodeId');
    try {
      final res = await _dio.delete<dynamic>(
        'rest/v1/user_watch_history',
        queryParameters: {
          'firebase_uid': 'eq.$firebaseUid',
          'anime_id': 'eq.$animeId',
          'episode_id': 'eq.$episodeId',
        },
        options: _anyStatus,
      );
      _logIfFailed('syncHistoryRemoved', res);
    } catch (e) {
      debugPrint('PublicProfileSync: syncHistoryRemoved EXCEPTION: $e');
    }
  }
}
