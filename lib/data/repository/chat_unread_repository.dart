import 'package:dio/dio.dart';

import 'authed_function.dart';

/// Jumlah chat belum dibaca (maks 99, ditampilkan "99+").
class ChatUnread {
  const ChatUnread({this.private = 0, this.clan = 0});

  final int private;
  final int clan;

  factory ChatUnread.fromJson(Map<String, dynamic> j) => ChatUnread(
        private: (j['private'] as num?)?.toInt() ?? 0,
        clan: (j['clan'] as num?)?.toInt() ?? 0,
      );
}

/// Edge Function `chat-unread`. UID diambil server dari Firebase ID Token.
class ChatUnreadRepository {
  ChatUnreadRepository(this._dio);

  final Dio _dio;

  Future<ChatUnread> _call(String action) async {
    final d = await callAuthedFunction(_dio, 'chat-unread', {'action': action});
    return d is Map ? ChatUnread.fromJson(Map<String, dynamic>.from(d)) : const ChatUnread();
  }

  Future<ChatUnread> counts() => _call('counts');

  /// Tandai chat clan sudah dibaca, lalu kembalikan jumlah terbaru.
  Future<ChatUnread> markClanRead() => _call('clan_read');
}
