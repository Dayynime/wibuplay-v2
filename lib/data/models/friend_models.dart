/// Status baris tabel `friendships`.
class FriendStatus {
  FriendStatus._();
  static const String pending = 'pending';
  static const String accepted = 'accepted';
}

/// Baris tabel `friendships` (sama dengan Zenime).
class Friendship {
  const Friendship({
    required this.id,
    required this.requesterUid,
    required this.addresseeUid,
    required this.status,
  });

  final String id;
  final String requesterUid;
  final String addresseeUid;
  final String status;

  factory Friendship.fromJson(Map<String, dynamic> j) => Friendship(
        id: (j['id'] ?? '').toString(),
        requesterUid: (j['requester_uid'] as String?) ?? '',
        addresseeUid: (j['addressee_uid'] as String?) ?? '',
        status: (j['status'] as String?) ?? FriendStatus.pending,
      );

  String otherUid(String myUid) => requesterUid == myUid ? addresseeUid : requesterUid;
}

/// Hubungan user yang login terhadap user lain (port FriendRelation).
sealed class FriendRelation {
  const FriendRelation();
}

class FriendRelationNone extends FriendRelation {
  const FriendRelationNone();
}

/// Aku yang kirim permintaan, menunggu dia terima.
class FriendRelationOutgoing extends FriendRelation {
  const FriendRelationOutgoing(this.friendshipId);
  final String friendshipId;
}

/// Dia yang kirim permintaan ke aku, menunggu aku terima/tolak.
class FriendRelationIncoming extends FriendRelation {
  const FriendRelationIncoming(this.friendshipId);
  final String friendshipId;
}

class FriendRelationFriends extends FriendRelation {
  const FriendRelationFriends(this.friendshipId);
  final String friendshipId;
}

/// Item di layar Teman: friendship digabung dengan username/avatar lawan.
class FriendDisplay {
  const FriendDisplay({
    required this.friendshipId,
    required this.firebaseUid,
    required this.username,
    this.avatarUrl,
  });

  final String friendshipId;
  final String firebaseUid;
  final String username;
  final String? avatarUrl;
}

class FriendLists {
  const FriendLists({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
  });

  final List<FriendDisplay> friends;
  final List<FriendDisplay> incoming;
  final List<FriendDisplay> outgoing;
}

/// Baris tabel `private_messages` (chat teman / DM).
class PrivateMessage {
  const PrivateMessage({
    required this.id,
    required this.senderUid,
    required this.recipientUid,
    required this.message,
    required this.createdAt,
    this.readAt,
    this.replyToId,
    this.replyToSenderUid,
    this.replyToMessage,
  });

  final int id;
  final String senderUid;
  final String recipientUid;
  final String message;
  final String createdAt;
  final String? readAt;
  final int? replyToId;
  final String? replyToSenderUid;
  final String? replyToMessage;

  DateTime? get time => DateTime.tryParse(createdAt)?.toLocal();

  factory PrivateMessage.fromJson(Map<String, dynamic> j) => PrivateMessage(
        id: (j['id'] as num?)?.toInt() ?? 0,
        senderUid: (j['sender_uid'] as String?) ?? '',
        recipientUid: (j['recipient_uid'] as String?) ?? '',
        message: (j['message'] as String?) ?? '',
        createdAt: (j['created_at'] as String?) ?? '',
        readAt: j['read_at'] as String?,
        replyToId: (j['reply_to_id'] as num?)?.toInt(),
        replyToSenderUid: j['reply_to_sender_uid'] as String?,
        replyToMessage: j['reply_to_message'] as String?,
      );

  PrivateMessage withReadAt(String readAt) => PrivateMessage(
        id: id,
        senderUid: senderUid,
        recipientUid: recipientUid,
        message: message,
        createdAt: createdAt,
        readAt: readAt,
        replyToId: replyToId,
        replyToSenderUid: replyToSenderUid,
        replyToMessage: replyToMessage,
      );

  bool involves(String myUid, String otherUid) =>
      (senderUid == myUid && recipientUid == otherUid) ||
      (senderUid == otherUid && recipientUid == myUid);
}
