import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wibuplay/data/api/anichin_network.dart';
import 'package:wibuplay/data/api/premium_token_manager.dart';
import 'package:wibuplay/data/repository/anichin_repository.dart';

import 'svelte_data_test.dart' show envelope;

/// Adapter palsu: kunci = "<path>" atau "<path>?<query>". Tanpa jaringan.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  final Map<String, Object> routes; // String (body) atau Object (di-jsonEncode)
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final u = options.uri;
    final key = u.query.isEmpty ? u.path : '${u.path}?${u.query}';
    calls.add('${options.method} $key');
    final body = routes[key];
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio dioWith(Map<String, Object> routes, [FakeAdapter? out]) {
  final d = Dio(BaseOptions(baseUrl: 'https://v1.anichin.space/', responseType: ResponseType.plain));
  d.httpClientAdapter = out ?? FakeAdapter(routes);
  return d;
}

const img = 'https://img.example/p.jpg';
const epSlug = 'renegade-immortal-episode-163-sub-indo';
const series = {
  'title': 'Renegade Immortal',
  'slug': 'renegade-immortal',
  'type': 'Donghua',
  'status': 'Ongoing',
  'thumbnail': img,
};

void main() {
  test('getHome: 3 section, eps int, duplikat dibuang', () async {
    final repo = AnichinRepository(dioWith({
      '/__data.json': envelope({
        'latestEpisodes': [
          {'title': 'RI 163', 'series': 'Renegade Immortal', 'slug': epSlug, 'latest_episode': '163', 'thumbnail': img},
          {'title': 'tanpa slug'},
        ],
        'popularSeries': [series, series],
      }),
      '/api/trending': [series],
    }));
    final home = await repo.getHome();
    final secs = {for (final s in home.results) s.section!: s.cards};
    expect(secs.keys, ['Rilis Terbaru', 'Trending', 'Populer']);
    expect(secs['Rilis Terbaru']!.single.eps, 163);
    expect(secs['Rilis Terbaru']!.single.slug, epSlug);
    expect(secs['Populer']!.length, 1);
    expect((await repo.getHome(page: 2)).results, isEmpty);
  });

  test('getHome: /api/trending gagal -> pakai trendingSlider', () async {
    final repo = AnichinRepository(dioWith({
      '/__data.json': envelope({
        'latestEpisodes': [],
        'popularSeries': [],
        'trendingSlider': [series],
      }),
    }));
    final home = await repo.getHome();
    final trending = home.results.firstWhere((s) => s.section == 'Trending');
    expect(trending.cards.single.slug, 'renegade-immortal');
  });

  test('cache: panggilan kedua tidak menembak jaringan lagi', () async {
    final adapter = FakeAdapter({
      '/__data.json': envelope({'latestEpisodes': [], 'popularSeries': []}),
      '/api/trending': [series],
    });
    final repo = AnichinRepository(dioWith({}, adapter));
    await repo.getHome();
    final n = adapter.calls.length;
    await repo.getHome();
    expect(adapter.calls.length, n);
  });

  test('search memakai /api/search?q=', () async {
    final repo = AnichinRepository(dioWith({
      '/api/search?q=renegade': [series],
    }));
    final r = await repo.search('  renegade ');
    expect(r.results.single.slug, 'renegade-immortal');
    expect(r.query, 'renegade');
    expect((await repo.search('   ')).results, isEmpty);
  });

  test('getAnimeList: ongoing, completed, dan semua', () async {
    final repo = AnichinRepository(dioWith({
      '/ongoing/__data.json?page=2': envelope({'ongoingSeries': [series], 'currentPage': 2, 'totalPages': 5}),
      '/completed/__data.json?page=1': envelope({'completedSeries': [series], 'currentPage': 1, 'totalPages': 2}),
      '/series/__data.json?page=1': envelope({'seriesData': [series], 'currentPage': 1, 'totalPages': 9}),
    }));
    final o = await repo.getAnimeList(status: 'Ongoing', order: 'update', extra: {'page': '2'});
    expect((o.page, o.total, o.results.length), (2, 5, 1));
    final c = await repo.getAnimeList(status: 'Completed');
    expect(c.total, 2);
    final a = await repo.getAnimeList();
    expect(a.total, 9);
  });

  test('getGenres: label di-unescape, duplikat dibuang', () async {
    final repo = AnichinRepository(dioWith({
      '/genres/__data.json': envelope({
        'dataList': [
          {'key': 'action', 'label': 'Action &amp; Adventure'},
          {'key': 'action', 'label': 'dobel'},
          {'label': 'tanpa key'},
        ],
      }),
    }));
    final g = await repo.getGenres();
    expect(g.length, 1);
    expect((g.single.slug, g.single.name), ('action', 'Action & Adventure'));
  });

  test('getByGenre: /series?genre=&page= dan validasi slug', () async {
    final repo = AnichinRepository(dioWith({
      '/series/__data.json?genre=action&page=3': envelope({'seriesData': [series], 'currentPage': 3, 'totalPages': 4}),
    }));
    final r = await repo.getByGenre('action', page: 3);
    expect((r.page, r.total, r.slug), (3, 4, 'action'));
    await expectLater(repo.getByGenre('Bad_Slug'), throwsException);
  });

  test('getDetail: sinopsis paragraf, info, episode', () async {
    final repo = AnichinRepository(dioWith({
      '/series/renegade-immortal/__data.json': envelope({
        'anime': {
          ...series,
          'rating': 8.6,
          'genres': [{'name': 'Action'}, 'Fantasy'],
          'description': '<p>Satu &amp; dua.</p><p>Tiga.</p>',
          'studio': ['Foch'],
          'season': ['Fall 2023'],
          'duration': '20 min',
          'all_episodes': [
            {'slug': epSlug, 'episode': 163, 'title': 'Ep 163'},
            {'slug': epSlug, 'episode': 163, 'title': 'dobel'},
            {'slug': 'renegade-immortal-episode-162-sub-indo', 'episode': 162, 'title': 'Ep 162'},
          ],
        },
      }),
    }));
    final d = await repo.getDetail('renegade-immortal');
    expect(d.name, 'Renegade Immortal');
    expect(d.rating, '8.6');
    expect(d.genres, ['Action', 'Fantasy']);
    expect(d.sinopsis, 'Satu & dua.\n\nTiga.');
    expect(d.episodes.map((e) => e.episode), ['163', '162']);
    expect(d.info['status'], 'Ongoing');
    expect(d.info['studio'], 'Foch');
    expect(d.info['season'], 'Fall 2023');
    expect(d.info['durasi'], '20 min');
  });

  test('getDetail: anime tidak ada -> error', () async {
    final repo = AnichinRepository(dioWith({
      '/series/x/__data.json': envelope({'anime': null}),
    }));
    await expectLater(repo.getDetail('x'), throwsException);
  });

  Map<String, Object> watchRoute(List<Map<String, Object>> videos) => {
        '/watch/$epSlug/__data.json': envelope({
          'episode': {
            'title': 'Renegade Immortal Episode 163',
            'slug': epSlug,
            'anime': {
              'slug': 'renegade-immortal',
              'title': 'Renegade Immortal',
              'thumbnail': img,
              'genres': ['Action'],
              'episodes': [{'slug': epSlug, 'episode': 163, 'title': 'Ep 163'}],
            },
            'videos': videos,
          },
        }),
      };

  test('getEpisode: root + players tersaring (VIP dulu)', () async {
    final repo = AnichinRepository(dioWith(watchRoute([
      {'embed': 'https://www.dailymotion.com/embed/video/x1', 'host_name': 'Dailymotion'},
      {'embed': 'https://evil.example/x', 'host_name': 'Evil'},
      {'embed': 'https://ok.ru/videoembed/', 'host_name': 'OK kosong'},
      {'embed': 'https://ok.ru/videoembed/12345', 'host_name': 'OK.ru'},
      {'embed': 'https://rmb.anichin.bio/e/abc', 'host_name': 'VIP'},
    ])));
    final e = await repo.getEpisode(epSlug);
    expect(e.root, 'renegade-immortal');
    expect(e.players.map((p) => p.name), ['VIP', 'Dailymotion', 'OK.ru']);
  });

  test('getVideoSource: OK.ru -> medias urut kualitas', () async {
    final okru = Dio(BaseOptions(responseType: ResponseType.plain))
      ..httpClientAdapter = FakeAdapter({
        '/dk': {
          'hlsManifestUrl': 'https://ok.ru/hls/1.m3u8',
          'videos': [
            {'name': 'hd', 'url': 'https://v.ok.ru/hd.mp4'},
            {'name': 'mobile', 'url': 'https://v.ok.ru/m.mp4'},
            {'name': 'sd', 'url': ''},
          ],
        },
      });
    final repo = AnichinRepository(
      dioWith(watchRoute([
        {'embed': 'https://ok.ru/videoembed/12345', 'host_name': 'OK.ru'},
      ])),
      okruDio: okru,
    );
    final v = await repo.getVideoSource(epSlug);
    expect(v.medias.map((m) => m.quality), ['mobile', 'hd']);
    expect(v.hls, 'https://ok.ru/hls/1.m3u8');
    expect(AnichinRepository.pickMedia(v.medias, maxQuality: 'sd')!.quality, 'mobile');
  });

  test('getVideoSource: tanpa OK.ru -> DioException 404 (pesan "belum tersedia")', () async {
    final repo = AnichinRepository(dioWith(watchRoute([
      {'embed': 'https://www.dailymotion.com/embed/video/x1', 'host_name': 'Dailymotion'},
    ])));
    await expectLater(
      repo.getVideoSource(epSlug),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 404)),
    );
  });

  test('createAnichinDio: base URL tetap, tanpa Authorization default', () {
    final d = createAnichinDio(PremiumTokenManager(Dio()));
    expect(d.options.baseUrl, 'https://v1.anichin.space/');
    expect(d.options.headers.containsKey('Authorization'), isFalse);
  });
}
