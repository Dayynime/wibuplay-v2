import 'dart:async';

import '../../../data/local/page_cache.dart';
import '../../../data/models/chat_models.dart';

/// Cache Chat Global, biar layar chat LANGSUNG nampilin pesan + badge terakhir
/// tanpa nunggu spinner. Data terbaru tetap di-fetch di belakang layar dan
/// nimpa cache ini pas udah datang. Port ChatSessionCache.kt.
///
/// Selain di memori (selama app jalan), salinan pesan terakhir juga disimpan
/// ke HP, jadi setelah app ditutup dan dibuka lagi chat tetap langsung tampil.
class ChatSessionCache {
  ChatSessionCache._();

  static List<ChatMessage> messages = const [];
  static Set<String> premiumUids = const {};
  static Map<String, String> clanTags = const {};
  static Map<String, int> levels = const {};
  static Map<String, String> usernameColors = const {};
  static Map<String, int> userNumbers = const {};
  static Map<String, String> avatarUrls = const {};

  static const String _diskKey = 'chat_global';

  /// Jumlah pesan terakhir yang disimpan ke HP.
  static const int _diskLimit = 60;

  static Timer? _persistTimer;

  static void save({
    required List<ChatMessage> messages,
    required Set<String> premiumUids,
    required Map<String, String> clanTags,
    required Map<String, int> levels,
    required Map<String, String> usernameColors,
    required Map<String, int> userNumbers,
    required Map<String, String> avatarUrls,
  }) {
    // Jangan timpa cache yang udah isi pakai state kosong (misal pas awal).
    if (messages.isEmpty) return;
    ChatSessionCache.messages = messages;
    ChatSessionCache.premiumUids = premiumUids;
    ChatSessionCache.clanTags = clanTags;
    ChatSessionCache.levels = levels;
    ChatSessionCache.usernameColors = usernameColors;
    ChatSessionCache.userNumbers = userNumbers;
    ChatSessionCache.avatarUrls = avatarUrls;
    // Tulis ke HP paling cepat 3 detik sekali (chat bisa ramai).
    _persistTimer ??= Timer(const Duration(seconds: 3), _persist);
  }

  static void _persist() {
    _persistTimer = null;
    final all = messages.where((m) => m.id > 0).toList();
    final last = all.length > _diskLimit ? all.sublist(all.length - _diskLimit) : all;
    if (last.isEmpty) return;
    // Badge/warna cukup untuk pengirim pesan yang disimpan.
    final uids = {for (final m in last) m.firebaseUid};
    Map<String, V> only<V>(Map<String, V> map) =>
        {for (final e in map.entries) if (uids.contains(e.key)) e.key: e.value};
    unawaited(DiskCache.write(_diskKey, {
      'messages': [for (final m in last) PageCodec.chatToJson(m)],
      'premium_uids': [for (final u in premiumUids) if (uids.contains(u)) u],
      'clan_tags': only(clanTags),
      'levels': only(levels),
      'username_colors': only(usernameColors),
      'user_numbers': only(userNumbers),
      'avatar_urls': only(avatarUrls),
    }));
  }

  /// Muat salinan dari HP ke memori. Dipanggil sekali saat app start (tanpa
  /// ditunggu). Tidak menimpa kalau memori sudah berisi data yang lebih baru.
  static Future<void> restore() async {
    try {
      final j = await DiskCache.read(_diskKey);
      if (j is! Map || messages.isNotEmpty) return;
      final list = PageCodec.chats(j['messages']);
      if (list.isEmpty) return;
      Map<String, String> strings(Object? v) => v is Map
          ? {for (final e in v.entries) if (e.value != null) e.key.toString(): e.value.toString()}
          : <String, String>{};
      Map<String, int> ints(Object? v) => v is Map
          ? {for (final e in v.entries) if (e.value is num) e.key.toString(): (e.value as num).toInt()}
          : <String, int>{};
      final premium = j['premium_uids'];
      messages = list;
      premiumUids = premium is List ? {for (final u in premium) u.toString()} : <String>{};
      clanTags = strings(j['clan_tags']);
      levels = ints(j['levels']);
      usernameColors = strings(j['username_colors']);
      userNumbers = ints(j['user_numbers']);
      avatarUrls = strings(j['avatar_urls']);
    } catch (_) {}
  }
}
