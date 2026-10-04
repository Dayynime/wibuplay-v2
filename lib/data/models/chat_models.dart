/// Baris tabel `global_chat_messages` (sama dengan ChatMessage di Zenime).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.firebaseUid,
    required this.username,
    this.avatarUrl,
    required this.message,
    required this.createdAt,
    this.replyToId,
    this.replyToUsername,
    this.replyToMessage,
    this.messageType = 'text',
    this.audioUrl,
    this.durationSeconds,
  });

  final int id;
  final String firebaseUid;
  final String username;
  final String? avatarUrl;
  final String message;
  final String createdAt;
  final int? replyToId;
  final String? replyToUsername;
  final String? replyToMessage;

  /// "text" atau "voice". Pesan suara belum bisa diputar di Wibuplay,
  /// tampil sebagai teks placeholder dari kolom [message].
  final String messageType;
  final String? audioUrl;
  final int? durationSeconds;

  bool get isVoice => messageType == 'voice';

  DateTime? get time => DateTime.tryParse(createdAt)?.toLocal();

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    return ChatMessage(
      id: (j['id'] as num?)?.toInt() ?? 0,
      firebaseUid: (j['firebase_uid'] as String?) ?? '',
      username: (j['username'] as String?) ?? 'Pengguna',
      avatarUrl: j['avatar_url'] as String?,
      message: (j['message'] as String?) ?? '',
      createdAt: (j['created_at'] as String?) ?? '',
      replyToId: (j['reply_to_id'] as num?)?.toInt(),
      replyToUsername: j['reply_to_username'] as String?,
      replyToMessage: j['reply_to_message'] as String?,
      messageType: (j['message_type'] as String?) ?? 'text',
      audioUrl: j['audio_url'] as String?,
      durationSeconds: (j['duration_seconds'] as num?)?.toInt(),
    );
  }
}

/// Baris tabel `chat_profiles` (username/avatar/warna yang dipakai bersama Zenime).
class ChatProfile {
  const ChatProfile({
    required this.firebaseUid,
    required this.username,
    this.avatarUrl,
    this.bannerUrl,
    this.usernameColor,
    this.userNumber,
    this.favoritesPublic = false,
    this.historyPublic = false,
  });

  final String firebaseUid;
  final String username;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? usernameColor;
  final int? userNumber;
  final bool favoritesPublic;
  final bool historyPublic;

  factory ChatProfile.fromJson(Map<String, dynamic> j) {
    return ChatProfile(
      firebaseUid: (j['firebase_uid'] as String?) ?? '',
      username: (j['username'] as String?) ?? '',
      avatarUrl: j['avatar_url'] as String?,
      bannerUrl: j['banner_url'] as String?,
      usernameColor: j['username_color'] as String?,
      userNumber: (j['user_number'] as num?)?.toInt(),
      favoritesPublic: (j['favorites_public'] as bool?) ?? false,
      historyPublic: (j['history_public'] as bool?) ?? false,
    );
  }
}

/// Warna username, ID urut, dan avatar TERKINI per uid (buat bubble chat).
class ChatBadgeData {
  const ChatBadgeData({
    this.usernameColors = const {},
    this.userNumbers = const {},
    this.avatarUrls = const {},
  });

  final Map<String, String> usernameColors;
  final Map<String, int> userNumbers;
  final Map<String, String> avatarUrls;
}

/// Balasan Edge Function `zenime-check-ban`.
class BanStatus {
  const BanStatus({this.banned = false, this.scope, this.reason});

  final bool banned;
  final String? scope;
  final String? reason;

  factory BanStatus.fromJson(Map<String, dynamic> j) => BanStatus(
        banned: (j['banned'] as bool?) ?? false,
        scope: j['scope'] as String?,
        reason: j['reason'] as String?,
      );
}
