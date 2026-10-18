import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/comic_network.dart';
import '../local/comic_store.dart';
import '../repository/comic_repository.dart';
import 'bacakomik_source.dart';
import 'comic_source.dart';
import 'westmanga_source.dart';

/// Dio khusus API komik Sanka (base URL fixed, bukan dari Remote Config).
final comicDioProvider = Provider<Dio>((ref) => createComicDio());

/// Favorit + progress baca komik.
final comicStoreProvider = ChangeNotifierProvider<ComicStore>((ref) => ComicStore());

/// Urutan sumber di sini = urutan di pemilih sumber (layar Komik).
final comicRepositoryProvider = Provider<ComicRepository>((ref) {
  final dio = ref.watch(comicDioProvider);
  final List<ComicSource> sources = [BacakomikSource(dio), WestmangaSource(dio)];
  return ComicRepository(sources, ref.read(comicStoreProvider));
});
