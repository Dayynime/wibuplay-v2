import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wibuplay/data/api/svelte_data.dart';

/// Meratakan pohon Map/List ke format flat devalue (akar di indeks 0).
List<Object?> flat(Object? root) {
  final out = <Object?>[];
  int add(Object? v) {
    final idx = out.length;
    out.add(null);
    if (v is Map) {
      out[idx] = {for (final e in v.entries) e.key: add(e.value)};
    } else if (v is List) {
      out[idx] = [for (final x in v) add(x)];
    } else {
      out[idx] = v;
    }
    return idx;
  }

  add(root);
  return out;
}

String envelope(Object? tree) => jsonEncode({
      'type': 'data',
      'nodes': [
        {'type': 'data', 'data': flat(tree)},
      ],
    });

void main() {
  group('unpackSvelte', () {
    test('Map dan List bersarang', () {
      final tree = {
        'a': 'x',
        'b': [1, 2, 3],
        'c': {'d': null, 'e': [{'f': true}]},
      };
      expect(unpackSvelte(flat(tree)), tree);
    });

    test('indeks negatif jadi null', () {
      expect(unpackSvelte([{'a': -1, 'b': 1}, 'ok']), {'a': null, 'b': 'ok'});
    });

    test('referensi bersama dipakai ulang', () {
      final r = unpackSvelte([{'p': 1, 'q': 1}, {'n': 2}, 'v']) as Map;
      expect(identical(r['p'], r['q']), isTrue);
    });

    test('input tak dikenal / indeks di luar batas', () {
      expect(() => unpackSvelte('x'), throwsFormatException);
      expect(() => unpackSvelte(<Object?>[]), throwsFormatException);
      expect(() => unpackSvelte([{'a': 9}]), throwsFormatException);
    });
  });

  group('parsePageData', () {
    test('membaca node data', () {
      final m = parsePageData(envelope({'totalPages': 5, 'items': [{'slug': 'a'}]}));
      expect(m['totalPages'], 5);
      expect((m['items'] as List).single, {'slug': 'a'});
    });

    test('node layout + halaman digabung, node belakangan menimpa', () {
      final body = jsonEncode({
        'type': 'data',
        'nodes': [
          {'type': 'data', 'data': flat({'site': 'x', 'k': 'layout'})},
          {'type': 'skip'},
          {'type': 'data', 'data': flat({'k': 'page', 'list': [1]})},
        ],
      });
      final m = parsePageData(body);
      expect(m['site'], 'x');
      expect(m['k'], 'page');
      expect(m['list'], [1]);
    });

    test('bukan data SvelteKit', () {
      expect(() => parsePageData('{"type":"redirect"}'), throwsFormatException);
      expect(() => parsePageData('{"type":"data","nodes":[]}'), throwsFormatException);
    });
  });
}
