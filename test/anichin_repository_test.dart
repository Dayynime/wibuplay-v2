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
  test('cache: request dari jaringan selesai (tidak deadlock) & request bersamaan digabung', () async {
    final adapter = FakeAdapter({
      '/series/renegade-immortal/__data.json': envelope({'anime': series}),
    });
    final repo = AnichinRepository(dioWith(const {}, adapter));
    final both = await Future.wait([
      repo.getDetail('renegade-immortal'),
      repo.getDetail('renegade-immortal'),
    ]).timeout(const Duration(seconds: 5));
    expect(both.map((d) => d.name), ['Renegade Immortal', 'Renegade Immortal']);
    expect(adapter.calls.where((c) => c.contains('renegade-immortal')).length, 1);
    // panggilan berikutnya dari cache memori, tetap selesai
    final again = await repo.getDetail('renegade-immortal').timeout(const Duration(seconds: 5));
    expect(again.name, 'Renegade Immortal');
  });

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

  test('getVideoSource: tanpa OK.ru -> Dailymotion HLS kualitas auto', () async {
    final dm = Dio(BaseOptions(responseType: ResponseType.plain))
      ..httpClientAdapter = FakeAdapter({
        '/player/metadata/video/x1': {
          'qualities': {
            'auto': [
              {'type': 'application/x-mpegURL', 'url': 'https://cdn.dailymotion.com/x1.m3u8'},
            ],
          },
        },
      });
    final repo = AnichinRepository(
      dioWith(watchRoute([
        {'embed': 'https://www.dailymotion.com/embed/video/x1', 'host_name': 'Dailymotion'},
      ])),
      okruDio: dm,
    );
    final v = await repo.getVideoSource(epSlug);
    expect(v.medias.single.quality, 'auto');
    expect(v.medias.single.url, 'https://cdn.dailymotion.com/x1.m3u8');
  });

  test('getVideoSource: VIP -> HLS rmb.anichin.bio/hls/<id>.m3u8', () async {
    final cdn = Dio(BaseOptions(responseType: ResponseType.plain))
      ..httpClientAdapter = FakeAdapter({
        '/hls/v7eut5y.m3u8': '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=676000,RESOLUTION=640x360\n'
            'https://hugh.cdn.rumble.cloud/v/a.baa.tar?r_file=chunklist.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=4096000,RESOLUTION=1920x1080\n'
            'https://hugh.cdn.rumble.cloud/v/a.haa.tar?r_file=chunklist.m3u8\n',
      });
    final repo = AnichinRepository(
      dioWith(watchRoute([
        {'embed': 'https://rmb.anichin.bio/?id=v7eut5y', 'host_name': 'VIP'},
        {'embed': 'https://ok.ru/videoembed/#', 'host_name': 'OK.ru'},
      ])),
      okruDio: cdn,
    );
    final v = await repo.getVideoSource(epSlug);
    expect(v.hls, 'https://rmb.anichin.bio/hls/v7eut5y.m3u8');
    expect(v.medias.map((m) => m.quality), ['low', 'full']);
  });

  test('parseHlsMaster: varian VIP -> kualitas 360p..1080p', () {
    const master = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=676000,RESOLUTION=640x360
https://hugh.cdn.rumble.cloud/v/a.baa.tar?r_file=chunklist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1052000,RESOLUTION=854x480
https://hugh.cdn.rumble.cloud/v/a.caa.tar?r_file=chunklist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2137000,RESOLUTION=1280x720
https://hugh.cdn.rumble.cloud/v/a.gaa.tar?r_file=chunklist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=4096000,RESOLUTION=1920x1080
rel/1080.m3u8
''';
    final m = AnichinRepository.parseHlsMaster(master, Uri.parse('https://rmb.anichin.bio/hls/x.m3u8'));
    expect(m.map((e) => e.quality), ['low', 'sd', 'hd', 'full']);
    expect(m.last.url, 'https://rmb.anichin.bio/hls/rel/1080.m3u8');
    expect(AnichinRepository.pickMedia(m, maxQuality: 'sd')!.quality, 'sd');
    expect(AnichinRepository.parseHlsMaster('bukan m3u8', Uri.parse('https://x/')), isEmpty);
  });

  test('vipHls: hanya embed VIP dengan id valid', () {
    expect(AnichinRepository.vipHls('https://rmb.anichin.bio/?id=abc_12'),
        'https://rmb.anichin.bio/hls/abc_12.m3u8');
    expect(AnichinRepository.vipHls('https://rmb.anichin.bio/e/abc'), isNull);
    expect(AnichinRepository.vipHls('https://evil.example/?id=abc'), isNull);
    expect(AnichinRepository.vipHls('https://rmb.anichin.bio/?id=../x'), isNull);
  });

  test('getVideoSource: tidak ada server yang bisa diputar -> DioException 404 (pesan "belum tersedia")', () async {
    final repo = AnichinRepository(dioWith(watchRoute([
      {'embed': 'https://rmb.anichin.bio/e/abc', 'host_name': 'VIP'},
    ])));
    await expectLater(
      repo.getVideoSource(epSlug),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 404)),
    );
  });

  test('createAnichinDio: base URL tetap, tanpa Authorization default', () {
    final d = createAnichinDio(PremiumTokenManager(Dio()));
    expect(d.options.baseUrl, AnichinNetwork.baseUrl);
    expect(d.options.headers.containsKey('Authorization'), isFalse);
  });
}
