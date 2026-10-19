/// Satu pesan di chat clan (dari Edge Function `clan-chat`).
class ClanMessage {
  const ClanMessage({
    required this.id,
    required this.firebaseUid,
    required this.message,
    required this.createdAt,
    this.replyToId,
  });

  final int id;
  final String firebaseUid;
  final String message;
  final int? replyToId;
  final DateTime createdAt;

  static ClanMessage? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final uid = raw['firebase_uid'];
    final msg = raw['message'];
    if (id is! num || uid is! String || msg is! String) return null;
    final t = DateTime.tryParse((raw['created_at'] as String?) ?? '')?.toLocal();
    return ClanMessage(
      id: id.toInt(),
      firebaseUid: uid,
      message: msg,
      replyToId: (raw['reply_to_id'] as num?)?.toInt(),
      createdAt: t ?? DateTime.now(),
    );
  }
}

class ClanChatPage {
  const ClanChatPage({required this.messages, required this.deletedIds});

  final List<ClanMessage> messages;
  final Set<int> deletedIds;
}
