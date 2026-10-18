import 'package:dio/dio.dart';

import '../../core/json_helper.dart';

/// Port ApiService.kt (Retrofit). Semua endpoint mengembalikan envelope
/// [ApiResponse]; parsing isi `data` dilakukan JsonHelper di repository.
class ApiService {
  ApiService(this._dio);

  final Dio _dio;

  Future<ApiResponse> _get(String path, [Map<String, dynamic>? query]) async {
    final res = await _dio.get<dynamic>(path, queryParameters: query);
    return JsonHelper.decodeEnvelope(res.data);
  }

  static String _p(String v) => Uri.encodeComponent(v);

  // Beranda
  Future<ApiResponse> getHomeCategory(String category, {int page = 0}) =>
      _get('3/2/home/${_p(category)}', {'page': page});

  Future<ApiResponse> getHomeList({int limit = 10, String day = 'SENIN'}) =>
      _get('data/home/list', {'limit': limit, 'day': day});

  Future<ApiResponse> getSchedule(String day, {String sort = 'views', int page = 0}) =>
      _get('3/2/schedule/data', {'day': day, 'sort': sort, 'page': page});

  // Cari & Jelajah
  Future<ApiResponse> exploreMovie({String keyword = '', String sort = 'views', int page = 0}) =>
      _get('3/2/explore/movie', {'keyword': keyword, 'sort': sort, 'page': page});

  Future<ApiResponse> exploreByGenre(String idGenre, {String sort = 'views', int page = 0}) =>
      _get('3/2/explore/movie_genre', {'id_genre': idGenre, 'sort': sort, 'page': page});

  Future<ApiResponse> exploreByType(String type, {String sort = 'views', int page = 0}) =>
      _get('3/2/explore/movie_type', {'type': type, 'sort': sort, 'page': page});

  Future<ApiResponse> exploreByYear(String year,
          {String season = '', String sort = 'views', int page = 0}) =>
      _get('3/2/explore/movie_year', {'year': year, 'season': season, 'sort': sort, 'page': page});

  Future<ApiResponse> exploreByStudio(String studio, {String sort = 'views', int page = 0}) =>
      _get('3/2/explore/movie_studio', {'studio': studio, 'sort': sort, 'page': page});

  Future<ApiResponse> getGenreList() => _get('3/2/explore/genre');

  // Detail & Streaming
  Future<ApiResponse> getMovieDetail(String id) => _get('3/2/movie/detail/${_p(id)}');

  Future<ApiResponse> getMovieEpisodes(String id, {int page = 0, String search = ''}) =>
      _get('3/2/movie/episode/${_p(id)}', {'page': page, 'search': search});

  Future<ApiResponse> getEpisodeStream(String idEpisode) =>
      _get('3/2/episode/streamnew/${_p(idEpisode)}');

  // Tab Detail
  Future<ApiResponse> getMovieCovers(String idMovie, {int page = 0}) =>
      _get('3/2/movie_cover/data', {'id_movie': idMovie, 'page': page});

  Future<ApiResponse> getMoviePosters(String idMovie, {int page = 0}) =>
      _get('3/2/movie_poster/data', {'id_movie': idMovie, 'page': page});

  Future<ApiResponse> getMovieCuplix(String idMovie, {int page = 0, String type = 'NEW'}) =>
      _get('data/movie/fyp/list_new', {'id_movie': idMovie, 'page': page, 'type': type});

  // Cuplix Global. sort: scroll_likes | scroll_new | scroll_old
  Future<ApiResponse> getCuplixScroll({
    int limit = 30,
    String sort = 'scroll_likes',
    String keyIdFyp = '',
    Map<String, String> cursorParams = const {},
  }) =>
      _get('data/fyp2/list_scroll', {
        'limit': limit,
        'sort': sort,
        'key_id_fyp': keyIdFyp,
        ...cursorParams,
      });
}
