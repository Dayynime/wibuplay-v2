import 'dart:async';

/// "Titipan" data per layar: satu request besar (Edge Function `screen-data`)
/// dibagi ke banyak provider kecil supaya mereka tidak menembak server sendiri.
///
/// Alur: layar memanggil [begin] (sebelum build pertama) lalu mengambil data;
/// provider yang dibangun di layar itu menunggu lewat [take]; setelah data
/// datang layar memanggil [finish]. Titipan dipakai SEKALI per bagian; refresh
/// berikutnya kembali ke jalur lama masing-masing provider. Kalau request
/// gagal / tidak ada titipan, provider langsung pakai jalur lama.
class ScreenSeed {
  ScreenSeed._();

  /// Titipan cuma berlaku sebentar setelah datang. Bagian yang tidak sempat
  /// dipakai (mis. provider-nya sudah punya data dari layar lain) kedaluwarsa,
  /// supaya refresh nanti (mis. habis edit profil) tidak memakai data lama.
  static const Duration _ttl = Duration(seconds: 15);

  static final Map<String, Completer<void>> _pending = {};
  static final Map<String, Object?> _seeds = {};
  static final Map<String, int> _seedCount = {};
  static final Map<String, DateTime> _seedAt = {};

  static void _clear(String id) {
    _seeds.removeWhere((k, _) => k.endsWith('|$id'));
    _seedCount.remove(id);
    _seedAt.remove(id);
  }

  static bool _expired(String id) {
    final at = _seedAt[id];
    if (at == null || DateTime.now().difference(at) <= _ttl) return false;
    _clear(id);
    return true;
  }

  /// Ada layar yang sedang/baru menitipkan data untuk [id]?
  static bool active(String id) {
    if (_pending.containsKey(id)) return true;
    if (_expired(id)) return false;
    return (_seedCount[id] ?? 0) > 0;
  }

  static void begin(String id) {
    _clear(id);
    _pending[id] ??= Completer<void>();
  }

  static void finish(String id, Map<String, Object?> fields) {
    fields.forEach((field, value) => _seeds['$field|$id'] = value);
    if (fields.isNotEmpty) {
      _seedCount[id] = fields.length;
      _seedAt[id] = DateTime.now();
    }
    final c = _pending.remove(id);
    if (c != null && !c.isCompleted) c.complete();
  }

  /// (true, nilai) kalau ada titipan untuk [field]; (false, null) kalau tidak.
  static Future<(bool, Object?)> take(String field, String id) async {
    final c = _pending[id];
    if (c != null) {
      await c.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    if (_expired(id)) return (false, null);
    final key = '$field|$id';
    if (!_seeds.containsKey(key)) return (false, null);
    final v = _seeds.remove(key);
    final left = (_seedCount[id] ?? 1) - 1;
    if (left <= 0) {
      _seedCount.remove(id);
    } else {
      _seedCount[id] = left;
    }
    return (true, v);
  }
}

/// Pakai titipan [field] untuk [id] kalau ada; kalau tidak ada layar yang
/// menitipkan, jalankan [normal] (jalur biasa, dipanggil sinkron); kalau ada
/// layar tapi bagian ini kosong/gagal, jalankan [plain] (jalur lama).
Future<T> viaScreenSeed<T>(
  String field,
  String id,
  Future<T> Function() normal,
  Future<T> Function() plain,
) async {
  if (!ScreenSeed.active(id)) return normal();
  final (hit, value) = await ScreenSeed.take(field, id);
  if (hit) return value as T;
  return plain();
}
