import 'dart:convert';

/// Decoder format "flat" SvelteKit/devalue (respons `__data.json`).
///
/// Port dari `unpack_svelte()` di anichin_scraper.py: array datar berisi nilai
/// dan referensi indeks. Elemen 0 adalah akar. Indeks negatif (sentinel
/// undefined/null) menjadi null. Formatnya bisa berubah kapan saja di sisi
/// situs sumber.
///
/// Tipe khusus devalue (`["Date", "..."]`, `["Promise", ref]`, dst.) juga
/// dikenali. Promise yang di-stream SvelteKit diisi dari [chunks] (id -> data
/// datar chunk itu).
Object? unpackSvelte(Object? data, {Map<int, Object?> chunks = const {}}) {
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
      // Tipe khusus devalue: elemen pertama berupa nama tipe (String).
      if (value.isNotEmpty && value.first is String) {
        final type = value.first as String;
        switch (type) {
          case 'Date':
          case 'BigInt':
          case 'RegExp':
          case 'URL':
            return memo[i] = value.length > 1 ? value[1] : null;
          case 'Object':
            return memo[i] = value.length > 1 ? value[1] : null;
          case 'Set':
            final s = <Object?>[];
            memo[i] = s;
            for (final ref in value.skip(1)) {
              s.add(resolve(ref));
            }
            return s;
          case 'Map':
            final m = <String, Object?>{};
            memo[i] = m;
            for (var j = 1; j + 1 < value.length; j += 2) {
              m[resolve(value[j]).toString()] = resolve(value[j + 1]);
            }
            return m;
          case 'null':
            final m = <String, Object?>{};
            memo[i] = m;
            for (var j = 1; j + 1 < value.length; j += 2) {
              m[value[j].toString()] = resolve(value[j + 1]);
            }
            return m;
          case 'Promise':
            // Arg = referensi ke id chunk (angka).
            final arg = value.length > 1 ? value[1] : null;
            final rawId = arg is int && arg >= 0 && arg < data.length ? data[arg] : arg;
            final id = rawId is int ? rawId : int.tryParse('$rawId');
            final chunk = id == null ? null : chunks[id];
            return memo[i] = chunk == null ? null : unpackSvelte(chunk);
          default:
            // Reviver lain: nilainya ada di argumen pertama.
            return memo[i] = value.length > 1 ? resolve(value[1]) : null;
        }
      }
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

/// Halaman sumber minta pindah ke path lain (`{"type":"redirect"}`).
class SvelteRedirect implements Exception {
  const SvelteRedirect(this.location);
  final String location;
  @override
  String toString() => 'SvelteRedirect($location)';
}

/// Body `/<halaman>/__data.json` -> Map data halaman.
///
/// Body bisa berupa SATU objek JSON, atau beberapa baris (NDJSON) kalau
/// SvelteKit men-stream data yang lambat: baris pertama data utama, baris
/// berikutnya `{"type":"chunk","id":n,"data":[...]}`. Dua-duanya didukung.
///
/// Semua node bertipe `data` di-unpack lalu digabung (node belakangan menimpa
/// key yang sama), jadi data halaman tetap terbaca walau SvelteKit menaruh
/// data layout di node pertama.
///
/// Melempar [SvelteRedirect] kalau sumber minta redirect, [FormatException]
/// kalau bentuknya tidak dikenali.
Map<String, dynamic> parsePageData(String body) {
  final lines = const LineSplitter()
      .convert(body.trim())
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) throw const FormatException('Respons kosong');

  Object? response;
  final chunks = <int, Object?>{};
  try {
    response = jsonDecode(lines.first);
  } on FormatException {
    // Mungkin satu JSON yang dipecah baris (pretty-print).
    response = jsonDecode(body);
    lines.clear();
  }
  for (final line in lines.skip(1)) {
    try {
      final c = jsonDecode(line);
      if (c is Map && c['type'] == 'chunk' && c['id'] is int) {
        chunks[c['id'] as int] = c['data'];
      }
    } on FormatException {
      // baris rusak -> abaikan, data utama tetap dipakai
    }
  }

  if (response is Map && response['type'] == 'redirect') {
    final loc = response['location'];
    if (loc is String && loc.isNotEmpty) throw SvelteRedirect(loc);
  }
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
        final v = unpackSvelte(node['data'], chunks: chunks);
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
