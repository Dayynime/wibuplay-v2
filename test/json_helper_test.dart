import 'package:flutter_test/flutter_test.dart';
import 'package:wibuplay/core/constants.dart';
import 'package:wibuplay/core/json_helper.dart';

void main() {
  group('ekstraksi list dibungkus Map', () {
    final item = {'id': '1', 'title': 'A'};

    test('anime: movie / movies / data', () {
      expect(JsonHelper.parseAnimeList({'movie': [item]}).length, 1);
      expect(JsonHelper.parseAnimeList({'movies': [item]}).length, 1);
      expect(JsonHelper.parseAnimeList({'data': [item]}).length, 1);
    });

    test('List langsung, item bukan Map dilewati', () {
      expect(JsonHelper.parseAnimeList([item, 'bukan map', 3]).length, 1);
    });

    test('bukan List atau null -> kosong', () {
      expect(JsonHelper.parseAnimeList(null), isEmpty);
      expect(JsonHelper.parseAnimeList('x'), isEmpty);
      expect(JsonHelper.parseAnimeList({'movie': 'x'}), isEmpty);
      // key pertama yang non-null menang (setara operator ?: di Kotlin)
      expect(JsonHelper.parseAnimeList({'movie': 'x', 'data': [item]}), isEmpty);
    });

    test('genre, episode, cuplix, media', () {
      expect(JsonHelper.parseGenreList({'genres': [{'id': 1, 'title': 'Aksi'}]}).first.name, 'Aksi');
      expect(JsonHelper.parseEpisodeList({'episodes': [{'id': 1}]}).length, 1);
      expect(JsonHelper.parseCuplixList({'fyp': [{'id': 9}]}).length, 1);
      expect(JsonHelper.parseMediaList({'poster': [{'id': 1, 'url': '/a.jpg'}]}).first.image, '/a.jpg');
    });
  });

  group('fallback nama field', () {
    test('AnimeItem', () {
      final a = JsonHelper.parseAnimeItem({
        'id': 5,
        'anime': 'Judul',
        'count_views': 100,
        'poster': '/p.jpg',
        'cover': '/c.jpg',
      })!;
      expect(a.id, '5');
      expect(a.title, 'Judul');
      expect(a.views, '100');
      expect(a.imagePoster, '/p.jpg');
      expect(a.imageCover, '/c.jpg');

      final b = JsonHelper.parseAnimeItem({'image': '/i.jpg', 'poster': '/p.jpg'})!;
      expect(b.imagePoster, '/p.jpg');
      final c = JsonHelper.parseAnimeItem({'image': '/i.jpg'})!;
      expect(c.imagePoster, '/i.jpg');
      final d = JsonHelper.parseAnimeItem({'image_poster': '/x.jpg', 'poster': '/p.jpg'})!;
      expect(d.imagePoster, '/x.jpg');
    });

    test('parseAnimeItem(null) -> null', () {
      expect(JsonHelper.parseAnimeItem(null), isNull);
    });

    test('EpisodeItem', () {
      final e = JsonHelper.parseEpisodeItem({'id': 1, 'episode': 5, 'thumbnail': '/t.jpg'})!;
      expect(e.index, '5');
      expect(e.image, '/t.jpg');
      expect(e.title, 'Episode 5');
      expect(e.isNew, isNull);

      final f = JsonHelper.parseEpisodeItem({'title': 'Judul Eps', 'index': 2, 'is_new': true})!;
      expect(f.title, 'Judul Eps');
      expect(f.isNew, true);

      expect(JsonHelper.parseEpisodeItem({'id': 1})!.title, 'Episode ');
    });

    test('GenreItem name <- title', () {
      final g = JsonHelper.parseGenreList([{'id': 1, 'name': 'N', 'title': 'T', 'total': 3}]).first;
      expect(g.name, 'N');
      expect(g.total, '3');
    });

    test('CuplixItem: fallback, id null dilewati, waktu ke ms', () {
      final list = JsonHelper.parseCuplixList([
        {'caption': 'tanpa id'},
        {
          'id': 7,
          'thumbnail': '/th.jpg',
          'views': 10,
          'likes': 2,
          'comments': 1,
          'time_start': '1500',
          'time_end': 'abc',
        },
      ]);
      expect(list.length, 1);
      final c = list.first;
      expect(c.id, '7');
      expect(c.urlThumbnail, '/th.jpg');
      expect(c.countViews, '10');
      expect(c.countLikes, '2');
      expect(c.countComments, '1');
      expect(c.timeStartMs, 1500);
      expect(c.timeEndMs, 0);
    });

    test('MediaGalleryItem image <- image ?? url ?? cover', () {
      expect(JsonHelper.parseMediaList([{'cover': '/c.jpg'}]).first.image, '/c.jpg');
      expect(JsonHelper.parseMediaList([{'url': '/u.jpg', 'cover': '/c.jpg'}]).first.image, '/u.jpg');
    });
  });

  group('StreamData', () {
    test('episode_next bertipe Map -> hasNextEpisode true', () {
      final s = JsonHelper.parseStreamData({
        'episode': {'id': 1, 'index': 1},
        'episode_next': {'id': 2, 'index': 2},
        'server': [],
      });
      expect(s.hasNextEpisode, true);
      expect(s.episodeNext?.id, '2');
      expect(s.episode?.id, '1');
    });

    test('episode_next bertipe bool', () {
      expect(JsonHelper.parseStreamData({'episode_next': true}).hasNextEpisode, true);
      expect(JsonHelper.parseStreamData({'episode_next': true}).episodeNext, isNull);
      expect(JsonHelper.parseStreamData({'episode_next': false}).hasNextEpisode, false);
    });

    test('episode_next tidak ada / tipe lain -> false', () {
      expect(JsonHelper.parseStreamData({}).hasNextEpisode, false);
      expect(JsonHelper.parseStreamData({'episode_next': 'x'}).hasNextEpisode, false);
    });

    test('data bukan Map -> StreamData kosong', () {
      final s = JsonHelper.parseStreamData([1, 2]);
      expect(s.episode, isNull);
      expect(s.server, isEmpty);
      expect(s.hasNextEpisode, false);
    });

    test('server: name <- title, item bukan Map dilewati', () {
      final s = JsonHelper.parseStreamData({
        'server': [
          {'link': 'http://a/1.m3u8', 'quality': '720p', 'type': 'hls', 'title': 'Server A'},
          'rusak',
          {'link': 'http://b/2.mp4', 'name': 'Server B'},
        ],
      });
      expect(s.server.length, 2);
      expect(s.server[0].name, 'Server A');
      expect(s.server[0].quality, '720p');
      expect(s.server[1].name, 'Server B');
      expect(s.server[1].type, isNull);
    });
  });

  group('kursor cuplix', () {
    test('sanitizeCursorValue', () {
      expect(JsonHelper.sanitizeCursorValue(77.0), '77');
      expect(JsonHelper.sanitizeCursorValue(1.5), '1.5');
      expect(JsonHelper.sanitizeCursorValue(5), '5');
      expect(JsonHelper.sanitizeCursorValue('abc'), 'abc');
      expect(JsonHelper.sanitizeCursorValue(null), '');
    });

    test('extractCursors hanya key cursor_*', () {
      final c = JsonHelper.extractCursors({
        'cursor_likes': 77.0,
        'cursor_id': 'x1',
        'cursor_time': 12.25,
        'list': [],
        'other': 1,
      });
      expect(c, {'cursor_likes': '77', 'cursor_id': 'x1', 'cursor_time': '12.25'});
      expect(JsonHelper.extractCursors([1]), isEmpty);
      expect(JsonHelper.extractCursors(null), isEmpty);
    });
  });

  group('URL gambar relatif', () {
    test('buildFullUrl', () {
      expect(buildFullUrl(null), '');
      expect(buildFullUrl(''), '');
      expect(buildFullUrl('   '), '');
      expect(buildFullUrl('https://cdn.x/a.jpg'), 'https://cdn.x/a.jpg');
      expect(buildFullUrl('http://cdn.x/a.jpg'), 'http://cdn.x/a.jpg');
      expect(buildFullUrl('/img/a.jpg'), 'https://xyz-api.animein.net/img/a.jpg');
      expect(buildFullUrl('img/a.jpg'), 'https://xyz-api.animein.net/img/a.jpg');
    });

    test('cover fallback ke poster; model lain memakai buildFullUrl', () {
      final a = JsonHelper.parseAnimeItem({'poster': 'p.jpg'})!;
      expect(a.posterUrl, 'https://xyz-api.animein.net/p.jpg');
      expect(a.coverUrl, 'https://xyz-api.animein.net/p.jpg');

      final b = JsonHelper.parseAnimeItem({'poster': 'p.jpg', 'cover': '/c.jpg'})!;
      expect(b.coverUrl, 'https://xyz-api.animein.net/c.jpg');

      expect(JsonHelper.parseEpisodeItem({'image': 'e.jpg'})!.imageUrl,
          'https://xyz-api.animein.net/e.jpg');
      expect(JsonHelper.parseCuplixList([{'id': 1, 'thumbnail': 't.jpg'}]).first.thumbnailUrl,
          'https://xyz-api.animein.net/t.jpg');
      expect(JsonHelper.parseMediaList([{'image': '/g.jpg'}]).first.fullImageUrl,
          'https://xyz-api.animein.net/g.jpg');
    });
  });

  group('envelope', () {
    test('decode dari String JSON', () {
      final r = JsonHelper.decodeEnvelope('{"status":200,"error":false,"data":{"a":1}}');
      expect(r.status, 200);
      expect(r.error, false);
      expect((r.data as Map)['a'], 1);
    });

    test('bukan objek JSON -> FormatException', () {
      expect(() => JsonHelper.decodeEnvelope('[1,2]'), throwsFormatException);
      expect(() => JsonHelper.decodeEnvelope(''), throwsFormatException);
    });
  });
}
