import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../local/entities.dart';
import '../models/public_profile_models.dart';

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

  // ---------------------------------------------------------------- baca publik

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Favorit/riwayat user LAIN lewat PostgREST. Toggle privasi dibaca dulu dari
  /// `chat_profiles` (supaya "privat" beda dari "publik tapi kosong"); tabel
  /// konten baru ditarik, BARENGAN, hanya kalau toggle-nya nyala. Port
  /// PublicProfileRepository.getPublicContent di Zenime.
  Future<PublicProfileContent> getPublicContent(String targetFirebaseUid) async {
    final profileRes = await _dio.get<dynamic>(
      'rest/v1/chat_profiles',
      queryParameters: {
        'firebase_uid': 'eq.$targetFirebaseUid',
        'select': 'favorites_public,history_public',
        'limit': 1,
      },
    );
    final profile = _rows(profileRes.data).firstOrNull;
    final favPublic = profile?['favorites_public'] == true;
    final histPublic = profile?['history_public'] == true;

    Future<List<PublicFavoriteRow>?> favs() async {
      if (!favPublic) return null;
      final res = await _dio.get<dynamic>(
        'rest/v1/user_favorites',
        queryParameters: {
          'firebase_uid': 'eq.$targetFirebaseUid',
          'select': 'anime_id,title,poster_url,type,status',
          'order': 'created_at.desc',
        },
      );
      return _rows(res.data).map(PublicFavoriteRow.fromJson).toList();
    }

    Future<List<PublicHistoryRow>?> hist() async {
      if (!histPublic) return null;
      final res = await _dio.get<dynamic>(
        'rest/v1/user_watch_history',
        queryParameters: {
          'firebase_uid': 'eq.$targetFirebaseUid',
          'select':
              'anime_id,anime_title,poster_url,episode_id,episode_title,episode_index,progress_ms,duration_ms,last_updated',
          'order': 'last_updated.desc',
        },
      );
      return _rows(res.data).map(PublicHistoryRow.fromJson).toList();
    }

    final results = await Future.wait<Object?>([favs(), hist()]);
    return PublicProfileContent(
      favoritesPublic: favPublic,
      historyPublic: histPublic,
      favorites: results[0] as List<PublicFavoriteRow>?,
      history: results[1] as List<PublicHistoryRow>?,
    );
  }
}
