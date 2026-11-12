import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/moviebox_network.dart';
import '../models/moviebox_models.dart';

/// Urutan daftar film (/movies?sort=).
enum MbSort {
  recommend('RECOMMEND', 'Rekomendasi'),
  latest('LATEST', 'Terbaru'),
  rating('RATING', 'Rating');

  const MbSort(this.value, this.label);
  final String value;
  final String label;
}

/// Repository film MovieBox. Endpoint relatif ke base URL Remote Config `moviebox_base_url`:
///   GET movies?page=&per_page=&sort=     daftar film
///   GET search?q=&page=&per_page=        cari (maks 20 per halaman)
///   GET detail/{id}                      detail + daftar dub
///   GET api/stream/{id}?se=0&ep=0&detail_path=
///   GET api/stream/{id}/captions?se=0&ep=0
class MovieBoxRepository {
  MovieBoxRepository(this._dio, this._subDio);

  final Dio _dio;
  final Dio _subDio;

  static const int pageSize = 24;

  Map<String, dynamic> _map(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) return Map<String, dynamic>.from(jsonDecode(data) as Map);
    throw Exception('Format data server tidak dikenal');
  }

  List<Map<String, dynamic>> _list(Object? v) => [
        for (final e in (v as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];

  Future<List<MbItem>> getMovies({int page = 1, MbSort sort = MbSort.recommend}) async {
    final res = await _dio.get<dynamic>('movies', queryParameters: {
      'page': page,
      'per_page': pageSize,
      'sort': sort.value,
    });
    return _list(_map(res.data)['items'])
        .map(MbItem.fromJson)
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  /// Cari film saja (series, musik, dan upload lain dibuang). MovieBox
  /// membatasi 20 per halaman, jadi diambil 2 halaman sekaligus.
  Future<List<MbItem>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final pages = await Future.wait([
      for (final p in [1, 2])
        _dio
            .get<dynamic>('search', queryParameters: {'q': q, 'page': p, 'per_page': 20})
            .then((r) => _list(_map(r.data)['results']))
            .catchError((Object _) => <Map<String, dynamic>>[]),
    ]);
    final seen = <String>{};
    return [
      for (final page in pages)
        for (final j in page) MbItem.fromJson(j),
    ].where((m) => m.id.isNotEmpty && m.subjectType == 1 && seen.add(m.id)).toList();
  }

  Future<MbDetail> getDetail(String id) async {
    final res = await _dio.get<dynamic>('detail/$id');
    return MbDetail.fromJson(_map(res.data));
  }

  /// Link MP4 yang bisa diputar (DASH dibuang). Server sudah mengurutkan
  /// h264 dulu, lalu kualitas tertinggi.
  Future<List<MbStream>> getStreams(String id, {String? detailPath}) async {
    final res = await _dio.get<dynamic>('api/stream/$id', queryParameters: {
      'se': 0,
      'ep': 0,
      if ((detailPath ?? '').isNotEmpty) 'detail_path': detailPath,
    });
    return _list(_map(res.data)['streams'])
        .map(MbStream.fromJson)
        .where((s) => s.url.isNotEmpty && !s.isDash)
        .toList();
  }

  Future<List<MbCaption>> getCaptions(String id) async {
    final res = await _dio.get<dynamic>('api/stream/$id/captions', queryParameters: {'se': 0, 'ep': 0});
    return _list(_map(res.data)['captions'])
        .map(MbCaption.fromJson)
        .where((c) => c.url.isNotEmpty)
        .toList();
  }

  /// Isi file subtitle (SRT/VTT) langsung dari CDN.
  Future<String> fetchSubtitle(String url) async {
    final res = await _subDio.get<List<int>>(url);
    return utf8.decode(res.data ?? const [], allowMalformed: true);
  }
}

final movieBoxRepositoryProvider = Provider<MovieBoxRepository>(
  (ref) => MovieBoxRepository(MovieBoxNetwork.createDio(), MovieBoxNetwork.createSubtitleDio()),
);
