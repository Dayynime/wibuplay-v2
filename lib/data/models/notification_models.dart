/// Satu item lonceng (tabel `notifications`, dibaca lewat Edge Function
/// `zenime-notify`). Jenis ([type]) yang dikenal:
///  - friend_request    : ada yang ngajak temenan
///  - friend_accepted   : request pertemananmu diterima
///  - clan_join_request : ada yang mau join clan (dikirim ke Officer ke atas)
///  - clan_joined       : request join clanmu diterima
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.actorUid,
    this.actorUsername,
    this.actorAvatarUrl,
    this.createdAt = '',
    this.read = false,
  });

  final int id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String? actorUid;
  final String? actorUsername;
  final String? actorAvatarUrl;
  final String createdAt;
  final bool read;

  /// Request pertemanan yang sudah dibatalkan/ditolak.
  bool get expired => data['expired'] == true;

  String? get clanId => data['clan_id']?.toString();

  bool get isClan => type.startsWith('clan_');

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        data: data,
        actorUid: actorUid,
        actorUsername: actorUsername,
        actorAvatarUrl: actorAvatarUrl,
        createdAt: createdAt,
        read: read ?? this.read,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final raw = j['data'];
    return AppNotification(
      id: (j['id'] as num?)?.toInt() ?? 0,
      type: (j['type'] as String?) ?? '',
      title: (j['title'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
      data: raw is Map ? Map<String, dynamic>.from(raw) : const {},
      actorUid: j['actor_uid'] as String?,
      actorUsername: j['actor_username'] as String?,
      actorAvatarUrl: j['actor_avatar_url'] as String?,
      createdAt: (j['created_at'] as String?) ?? '',
      read: j['read_at'] != null,
    );
  }
}

class NotificationPage {
  const NotificationPage({this.items = const [], this.unread = 0});

  final List<AppNotification> items;
  final int unread;
}
