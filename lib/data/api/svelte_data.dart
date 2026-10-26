import 'dart:convert';

/// Decoder format "flat" SvelteKit/devalue (respons `__data.json`).
///
/// Port dari `unpack_svelte()` di anichin_scraper.py: array datar berisi nilai
/// dan referensi indeks. Elemen 0 adalah akar. Indeks negatif (sentinel
/// undefined/null) menjadi null. Formatnya bisa berubah kapan saja di sisi
/// situs sumber.
Object? unpackSvelte(Object? data) {
  if (data is! List || data.isEmpty) {
    throw const FormatException('Struktur data SvelteKit tak dikenal');
  }
  final memo = <int, Object?>{};

  Object? resolve(Object? i) {
    if (i is! int || i < 0) return null;
    if (i >= data.length) {
      throw FormatException('Referensi indeks $i melampaui ukuran data');
    }
    if (memo.containsKey(i)) return memo[i];
    final value = data[i];
    if (value is Map) {
      final out = <String, Object?>{};
      memo[i] = out;
      value.forEach((k, ref) => out[k.toString()] = resolve(ref));
      return out;
    }
    if (value is List) {
      final out = <Object?>[];
      memo[i] = out;
      for (final ref in value) {
        out.add(resolve(ref));
      }
      return out;
    }
    return value;
  }

  return resolve(0);
}

/// Body `/<halaman>/__data.json` -> Map data halaman.
///
/// Scraper Python memakai node data PERTAMA. Di sini semua node bertipe `data`
/// di-unpack lalu digabung (node belakangan menimpa key yang sama), jadi data
/// halaman tetap terbaca walau SvelteKit menaruh data layout di node pertama.
Map<String, dynamic> parsePageData(String body) {
  final response = jsonDecode(body);
  if (response is! Map || response['type'] != 'data') {
    throw const FormatException('Respons bukan data SvelteKit');
  }
  final nodes = response['nodes'];
  final merged = <String, dynamic>{};
  var found = false;
  Object? lastError;
  if (nodes is List) {
    for (final node in nodes) {
      if (node is! Map || node['type'] != 'data') continue;
      try {
        final v = unpackSvelte(node['data']);
        if (v is Map) {
          merged.addAll(Map<String, dynamic>.from(v));
          found = true;
        }
      } on FormatException catch (e) {
        lastError = e;
      }
    }
  }
  if (!found) {
    throw lastError ?? const FormatException('Node data tidak ditemukan');
  }
  return merged;
}
