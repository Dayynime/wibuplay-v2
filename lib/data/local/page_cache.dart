import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/json_helper.dart';
import '../models/anichin_models.dart';
import '../models/anime_item.dart';
import '../models/chat_models.dart';
import '../models/clan_models.dart';
import '../models/comic_models.dart';
import '../models/support_models.dart';
import '../models/xp_models.dart';

// =============================================================================
// Salinan data halaman di HP ("tampil instan").
//
// Data terakhir yang berhasil dimuat disimpan sebagai file JSON kecil. Saat
// halaman dibuka lagi (termasuk setelah app ditutup), salinan itu langsung
// tampil, lalu data baru diambil di belakang dan menggantikannya. Kalau
// jaringan gagal, salinan tetap tampil daripada layar error.
//
// Hanya data publik (sama untuk semua user) yang disimpan di sini.
// =============================================================================

class DiskCache {
  DiskCache._();

  static Future<Directory?>? _dir;

  /// Salinan di memori. Diisi sekali saat app start lewat [preload], jadi
  /// halaman bisa membaca salinannya SINKRON di frame pertama (tanpa loading).
  static final Map<String, Object?> _mem = {};

  static Future<Directory?> _openDir() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/page_cache_v1');
      await d.create(recursive: true);
      return d;
    } catch (_) {
      return null;
    }
  }

  static String _safe(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static Future<File?> _file(String key) async {
    final d = await (_dir ??= _openDir());
    if (d == null) return null;
    return File('${d.path}/${_safe(key)}.json');
  }

  /// Baca semua salinan dari HP ke memori. Dipanggil sekali di main() sebelum
  /// runApp. File-nya kecil (beberapa KB), jadi cepat.
  static Future<void> preload() async {
    try {
      final d = await (_dir ??= _openDir());
      if (d == null) return;
      final files = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      await Future.wait(files.map((f) async {
        try {
          final name = f.uri.pathSegments.last;
          final key = name.substring(0, name.length - '.json'.length);
          _mem[key] = jsonDecode(await f.readAsString());
        } catch (_) {}
      }));
    } catch (_) {}
  }

  /// Salinan di memori untuk [key] (sinkron); null kalau belum ada.
  static Object? peek(String key) => _mem[_safe(key)];

  /// JSON yang tersimpan untuk [key]; null kalau belum ada atau rusak.
  static Future<Object?> read(String key) async {
    final k = _safe(key);
    if (_mem.containsKey(k)) return _mem[k];
    try {
      final f = await _file(key);
      if (f == null || !await f.exists()) return null;
      final v = jsonDecode(await f.readAsString());
      _mem[k] = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Simpan [value] (harus bisa di-jsonEncode). Gagal = diam saja.
  static Future<void> write(String key, Object? value) async {
    try {
      final body = jsonEncode(value);
      // Simpan bentuk hasil decode (sama persis dengan yang dibaca dari file).
      _mem[_safe(key)] = jsonDecode(body);
      final f = await _file(key);
      if (f == null) return;
      // Tulis ke file sementara lalu rename: file lama tidak pernah setengah jadi.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

// -----------------------------------------------------------------------------
// cacheFirst: untuk FutureProvider.
//
// Kalau ada salinan (di memori, dimuat saat app start), provider langsung
// selesai SINKRON dengan salinan itu, lalu data baru diambil di belakang dan
// provider dibangun ulang dengan hasilnya. Berlaku tiap kali halaman dibuka,
// jadi tidak ada loading/skeleton selama salinan ada.
// -----------------------------------------------------------------------------

class _Fresh {
  _Fresh(this.value, this.at);
  final Object? value;
  final DateTime at;
}

final Map<String, _Fresh> _fresh = {};
final Set<String> _warm = {};

/// Mengembalikan nilai SINKRON kalau salinan ada di memori (lihat
/// [DiskCache.preload]): FutureProvider/AsyncNotifier lalu langsung berstatus
/// data di frame pertama, tanpa loading/skeleton. Kalau tidak ada, berjalan
/// async seperti biasa.
FutureOr<T> cacheFirst<T>(
  Ref<Object?> ref, {
  required String key,
  required Future<T> Function() fetch,
  required Object? Function(T value) encode,
  required T? Function(Object? json) decode,
}) {
  // Hasil refresh di belakang yang baru saja datang: pakai, jangan fetch lagi.
  final ready = _fresh.remove(key);
  if (ready != null && DateTime.now().difference(ready.at) < const Duration(minutes: 2)) {
    return ready.value as T;
  }

  // Salinan terakhir di memori: tampil langsung (juga saat halaman dibuka
  // lagi), data baru diambil di belakang lalu menggantikannya.
  T? cached;
  try {
    cached = decode(DiskCache.peek(key));
  } catch (_) {
    cached = null;
  }
  if (cached != null) {
    _warm.add(key);
    unawaited(_refreshInBackground<T>(ref, key, fetch, encode));
    return cached;
  }

  if (_warm.add(key)) {
    return _readThenFetch<T>(ref, key, fetch, encode, decode);
  }

  return _fetchAndSave<T>(key, fetch, encode);
}

Future<T> _readThenFetch<T>(
  Ref<Object?> ref,
  String key,
  Future<T> Function() fetch,
  Object? Function(T value) encode,
  T? Function(Object? json) decode,
) async {
  T? cached;
  try {
    cached = decode(await DiskCache.read(key));
  } catch (_) {
    cached = null;
  }
  if (cached != null) {
    unawaited(_refreshInBackground<T>(ref, key, fetch, encode));
    return cached;
  }
  return _fetchAndSave<T>(key, fetch, encode);
}

Future<T> _fetchAndSave<T>(
  String key,
  Future<T> Function() fetch,
  Object? Function(T value) encode,
) async {
  final value = await fetch();
  unawaited(_save<T>(key, value, encode));
  return value;
}

/// Seperti `try { return await x; } catch { return fallback; }` tapi tetap
/// sinkron kalau [run] sinkron (supaya provider tidak sempat loading).
FutureOr<R> cacheFirstOr<T, R>(
  FutureOr<T> Function() run,
  R Function(T value) map,
  R fallback,
) {
  try {
    final FutureOr<T> v = run();
    if (v is Future<T>) {
      return v.then<R>(map).catchError((Object _) => fallback);
    }
    return map(v as T);
  } catch (_) {
    return fallback;
  }
}

Future<void> _refreshInBackground<T>(
  Ref<Object?> ref,
  String key,
  Future<T> Function() fetch,
  Object? Function(T value) encode,
) async {
  try {
    final value = await fetch();
    unawaited(_save<T>(key, value, encode));
    _fresh[key] = _Fresh(value, DateTime.now());
    ref.invalidateSelf();
  } catch (_) {
    // Gagal / provider sudah ditutup: salinan yang tampil tetap dipakai.
  }
}

Future<void> _save<T>(String key, T value, Object? Function(T value) encode) async {
  try {
    await DiskCache.write(key, encode(value));
  } catch (_) {}
}

// -----------------------------------------------------------------------------
// Codec model -> JSON. Kunci JSON sama dengan yang dibaca fromJson tiap model,
// jadi baca-ulang memakai parser yang sudah ada.
// -----------------------------------------------------------------------------

List<Map<String, dynamic>> _maps(Object? json) => json is List
    ? [for (final e in json) if (e is Map) Map<String, dynamic>.from(e)]
    : const [];

class PageCodec {
  PageCodec._();

  // ---- Anime (Jadwal) ----

  static Map<String, dynamic> animeToJson(AnimeItem a) => {
        'id': a.id,
        'title': a.title,
        'synopsis': a.synopsis,
        'genre': a.genre,
        'status': a.status,
        'type': a.type,
        'year': a.year,
        'day': a.day,
        'views': a.views,
        'favorites': a.favorites,
        'image_poster': a.imagePoster,
        'image_cover': a.imageCover,
        'studio': a.studio,
        'aired_start': a.airedStart,
        'aired_end': a.airedEnd,
        'time': a.time,
        'key_time': a.keyTime,
      };

  static List<AnimeItem> animeList(Object? json) => JsonHelper.parseAnimeList(json);

  // ---- Donghua ----

  static Map<String, dynamic> cardToJson(AnichinCard c) => {
        'title': c.title,
        'type': c.type,
        'headline': c.headline,
        'eps': c.eps,
        'status': c.status,
        'thumbnail': c.thumbnail,
        'slug': c.slug,
      };

  static List<AnichinCard> cards(Object? json) =>
      [for (final m in _maps(json)) AnichinCard.fromJson(m)];

  static Map<String, dynamic> sectionToJson(AnichinHomeSection s) => {
        'section': s.section,
        'cards': [for (final c in s.cards) cardToJson(c)],
      };

  static List<AnichinHomeSection> sections(Object? json) =>
      [for (final m in _maps(json)) AnichinHomeSection.fromJson(m)];

  // ---- Komik ----

  static Map<String, dynamic> comicToJson(ComicListItem c) => {
        'title': c.title,
        'slug': c.slug,
        'cover': c.cover,
        'chapter': c.chapter,
        'date': c.date,
        'rating': c.rating,
        'type': c.type,
      };

  static List<ComicListItem> comics(Object? json) =>
      [for (final m in _maps(json)) ComicListItem.fromJson(m)];

  // ---- Leaderboard XP ----

  static Map<String, dynamic> xpToJson(UserXpDisplay u) => {
        'firebase_uid': u.firebaseUid,
        'xp': u.xp,
        'level': u.level,
        'username': u.username,
        'avatar_url': u.avatarUrl,
        'clan_tag': u.clanTag,
        'is_premium': u.isPremium,
      };

  static List<UserXpDisplay> xpList(Object? json) => [
        for (final m in _maps(json))
          UserXpDisplay(
            firebaseUid: (m['firebase_uid'] as String?) ?? '',
            xp: (m['xp'] as num?)?.toInt() ?? 0,
            level: (m['level'] as num?)?.toInt() ?? 1,
            username: (m['username'] as String?) ?? 'Pengguna',
            avatarUrl: m['avatar_url'] as String?,
            clanTag: m['clan_tag'] as String?,
            isPremium: m['is_premium'] == true,
          ),
      ];

  // ---- Clan (slide Beranda) ----

  static Map<String, dynamic> clanToJson(ClanSummary c) => {
        'id': c.id,
        'tag': c.tag,
        'photo_url': c.photoUrl,
        'level': c.level,
        'total_xp': c.totalXp,
      };

  static List<ClanSummary> clans(Object? json) =>
      [for (final m in _maps(json)) ClanSummary.fromJson(m)];

  // ---- Top Support ----

  static Map<String, dynamic> supporterToJson(TopSupporter s) => {
        'rank': s.rank,
        'name': s.name,
        'avatar_url': s.avatarUrl,
        'username_color': s.usernameColor,
        'total_amount': s.totalAmount,
        'donation_count': s.donationCount,
        'is_linked': s.isLinked,
        'firebase_uid': s.firebaseUid,
      };

  static List<TopSupporter> supporters(Object? json) =>
      [for (final m in _maps(json)) TopSupporter.fromJson(m)];

  // ---- Top Giver ----

  static Map<String, dynamic> giversToJson(TopGiversData d) => {
        'givers': [
          for (final g in d.givers)
            {
              'rank': g.rank,
              'firebase_uid': g.firebaseUid,
              'username': g.username,
              'days': g.days,
              'avatar_url': g.avatarUrl,
              'user_number': g.userNumber,
              'username_color': g.usernameColor,
            },
        ],
        'clan_tags': d.clanTags,
        'levels': d.levels,
      };

  static TopGiversData? givers(Object? json) {
    if (json is! Map) return null;
    final list = [
      for (final m in _maps(json['givers']))
        TopGiver.fromJson(m, (m['rank'] as num?)?.toInt() ?? 0),
    ];
    final tags = json['clan_tags'];
    final levels = json['levels'];
    return TopGiversData(
      givers: list,
      clanTags: tags is Map
          ? {for (final e in tags.entries) e.key.toString(): e.value.toString()}
          : const {},
      levels: levels is Map
          ? {
              for (final e in levels.entries)
                if (e.value is num) e.key.toString(): (e.value as num).toInt(),
            }
          : const {},
    );
  }

  // ---- Chat Global ----

  static Map<String, dynamic> chatToJson(ChatMessage m) => {
        'id': m.id,
        'firebase_uid': m.firebaseUid,
        'username': m.username,
        'avatar_url': m.avatarUrl,
        'message': m.message,
        'created_at': m.createdAt,
        'reply_to_id': m.replyToId,
        'reply_to_username': m.replyToUsername,
        'reply_to_message': m.replyToMessage,
        'message_type': m.messageType,
        'audio_url': m.audioUrl,
        'duration_seconds': m.durationSeconds,
        'gift_days': m.giftDays,
        'gift_recipient_uid': m.giftRecipientUid,
        'gift_recipient_username': m.giftRecipientUsername,
        'giveaway_id': m.giveawayId,
        'wp_event_id': m.wpEventId,
      };

  static List<ChatMessage> chats(Object? json) =>
      [for (final m in _maps(json)) ChatMessage.fromJson(m)];
}

/// List kosong dianggap "tidak ada salinan" (biar tidak menampilkan halaman
/// kosong lalu loading).
List<T>? nonEmpty<T>(List<T> list) => list.isEmpty ? null : list;
