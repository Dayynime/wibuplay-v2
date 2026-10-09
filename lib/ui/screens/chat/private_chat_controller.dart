import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';

const int _maxDmLength = 1000;
const int _maxReplySnapshotLength = 200;

class ConversationItem {
  const ConversationItem({required this.friend, this.lastMessage, this.unread = 0});

  final FriendDisplay friend;
  final PrivateMessage? lastMessage;
  final int unread;
}

/// State tab "Teman" di layar Chat (port PrivateChatUiState).
class PrivateChatState {
  const PrivateChatState({
    this.isLoading = true,
    this.error,
    this.conversations = const [],
    this.selected,
    this.messages = const [],
    this.isLoadingMessages = false,
    this.isSending = false,
    this.sendError,
    this.replyTarget,
  });

  final bool isLoading;
  final String? error;
  final List<ConversationItem> conversations;

  /// Teman yang sedang dibuka chat-nya (null = belum memilih chat).
  final FriendDisplay? selected;
  final List<PrivateMessage> messages;
  final bool isLoadingMessages;
  final bool isSending;
  final String? sendError;
  final PrivateMessage? replyTarget;

  /// Parameter berupa fungsi supaya bisa mengisi null secara eksplisit.
  PrivateChatState copyWith({
    bool? isLoading,
    String? Function()? error,
    List<ConversationItem>? conversations,
    FriendDisplay? Function()? selected,
    List<PrivateMessage>? messages,
    bool? isLoadingMessages,
    bool? isSending,
    String? Function()? sendError,
    PrivateMessage? Function()? replyTarget,
  }) {
    return PrivateChatState(
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      conversations: conversations ?? this.conversations,
      selected: selected != null ? selected() : this.selected,
      messages: messages ?? this.messages,
      isLoadingMessages: isLoadingMessages ?? this.isLoadingMessages,
      isSending: isSending ?? this.isSending,
      sendError: sendError != null ? sendError() : this.sendError,
      replyTarget: replyTarget != null ? replyTarget() : this.replyTarget,
    );
  }
}

/// Controller tab "Teman". Daftar percakapan = semua teman (status accepted)
/// diurutkan dari pesan terakhir; pesan masuk datang lewat Realtime. Baru
/// nyambung ke server saat tab pertama kali dibuka ([ensureStarted]).
class PrivateChatController extends AutoDisposeNotifier<PrivateChatState> {
  bool _alive = true;
  bool _started = false;
  List<FriendDisplay> _friends = const [];
  List<PrivateMessage> _recent = const [];
  Timer? _poll;
  bool _polling = false;

  String get _myUid => ref.read(authRepositoryProvider).currentUser?.uid ?? '';

  @override
  PrivateChatState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _poll?.cancel();
    });
    return const PrivateChatState();
  }

  void _update(PrivateChatState Function(PrivateChatState s) f) {
    if (!_alive) return;
    state = f(state);
  }

  void ensureStarted() {
    if (_started) return;
    final uid = _myUid;
    if (uid.isEmpty) {
      _update((s) => s.copyWith(
            isLoading: false,
            error: () => 'Kamu harus login dulu.',
          ));
      return;
    }
    _started = true;
    loadConversations();
    // Realtime DM dimatikan di server (privasi), jadi cek pesan baru tiap beberapa detik.
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _pollTick());
  }

  Future<void> _pollTick() async {
    if (!_alive || _polling) return;
    final uid = _myUid;
    if (uid.isEmpty) return;
    _polling = true;
    try {
      final repo = ref.read(privateChatRepositoryProvider);
      final open = state.selected;
      final msgs = open != null
          ? await repo.getConversation(uid, open.firebaseUid)
          : await repo.getRecent(uid);
      if (!_alive) return;
      final fresh = msgs.where((m) => m.recipientUid == uid).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final m in fresh) {
        _applyIncoming(m);
      }
    } catch (_) {
      // Polling senyap: gagal sesekali tidak perlu mengganggu pengguna.
    } finally {
      _polling = false;
    }
  }

  Future<void> loadConversations({bool showLoading = true}) async {
    final uid = _myUid;
    if (uid.isEmpty) return;
    if (showLoading) _update((s) => s.copyWith(isLoading: true, error: () => null));
    try {
      final listsF = ref.read(friendRepositoryProvider).getLists(uid);
      final recentF = ref
          .read(privateChatRepositoryProvider)
          .getRecent(uid)
          .then<List<PrivateMessage>?>((v) => v)
          .catchError((_) => null);
      final lists = await listsF;
      final recent = await recentF;
      if (!_alive) return;
      _friends = lists.friends;
      if (recent != null) _recent = recent;
      _update((s) => s.copyWith(isLoading: false, error: () => null));
      _rebuildConversations();
    } catch (e) {
      if (!_alive) return;
      // Refresh senyap yang gagal tidak menimpa daftar yang sudah tampil.
      if (showLoading || state.conversations.isEmpty) {
        _update((s) => s.copyWith(
              isLoading: false,
              error: () => errorMessage(e, 'Gagal memuat daftar chat'),
            ));
      }
    }
  }

  void _rebuildConversations() {
    final uid = _myUid;
    final byOther = <String, List<PrivateMessage>>{};
    for (final m in _recent) {
      final other = m.senderUid == uid ? m.recipientUid : m.senderUid;
      byOther.putIfAbsent(other, () => []).add(m);
    }
    final items = _friends.map((f) {
      final msgs = byOther[f.firebaseUid] ?? const <PrivateMessage>[];
      PrivateMessage? last;
      for (final m in msgs) {
        if (last == null || m.id > last.id) last = m;
      }
      final unread = msgs.where((m) => m.recipientUid == uid && m.readAt == null).length;
      return ConversationItem(friend: f, lastMessage: last, unread: unread);
    }).toList()
      ..sort((a, b) {
        final c = (b.lastMessage?.id ?? -1).compareTo(a.lastMessage?.id ?? -1);
        if (c != 0) return c;
        return a.friend.username.toLowerCase().compareTo(b.friend.username.toLowerCase());
      });
    _update((s) => s.copyWith(conversations: items));
  }

  Future<void> openChat(FriendDisplay friend) async {
    final uid = _myUid;
    _update((s) => s.copyWith(
          selected: () => friend,
          messages: const [],
          isLoadingMessages: true,
          sendError: () => null,
          replyTarget: () => null,
        ));
    try {
      final msgs = await ref.read(privateChatRepositoryProvider).getConversation(uid, friend.firebaseUid);
      if (!_alive || state.selected?.firebaseUid != friend.firebaseUid) return;
      final hadUnread = msgs.any((m) => m.recipientUid == uid && m.readAt == null);
      final now = DateTime.now().toUtc().toIso8601String();
      final shown = msgs
          .map((m) => (m.recipientUid == uid && m.readAt == null) ? m.withReadAt(now) : m)
          .toList();
      _recent = [
        ..._recent.where((m) => !m.involves(uid, friend.firebaseUid)),
        ...shown,
      ];
      _update((s) => s.copyWith(messages: shown, isLoadingMessages: false));
      _rebuildConversations();
      if (hadUnread) {
        unawaited(ref
            .read(privateChatRepositoryProvider)
            .markRead(uid, friend.firebaseUid)
            .catchError((_) {}));
      }
    } catch (e) {
      if (!_alive) return;
      _update((s) => s.copyWith(
            isLoadingMessages: false,
            sendError: () => errorMessage(e, 'Gagal memuat pesan'),
          ));
    }
  }

  void closeChat() {
    _update((s) => s.copyWith(
          selected: () => null,
          messages: const [],
          sendError: () => null,
          replyTarget: () => null,
        ));
    loadConversations(showLoading: false);
  }

  void setReplyTarget(PrivateMessage m) => _update((s) => s.copyWith(replyTarget: () => m));

  void clearReplyTarget() => _update((s) => s.copyWith(replyTarget: () => null));

  void clearSendError() => _update((s) => s.copyWith(sendError: () => null));

  /// true kalau terkirim (layar boleh mengosongkan input).
  Future<bool> sendMessage(String text) async {
    final friend = state.selected;
    final trimmed = text.trim();
    if (friend == null || trimmed.isEmpty || state.isSending) return false;
    if (trimmed.length > _maxDmLength) {
      _update((s) => s.copyWith(sendError: () => 'Pesan maksimal $_maxDmLength karakter'));
      return false;
    }
    final uid = _myUid;
    final target = state.replyTarget;
    _update((s) => s.copyWith(isSending: true, sendError: () => null));
    try {
      final reply = target?.message;
      final msg = await ref.read(privateChatRepositoryProvider).send(
            myUid: uid,
            otherUid: friend.firebaseUid,
            text: trimmed,
            replyToId: target?.id,
            replyToSenderUid: target?.senderUid,
            replyToMessage: reply == null
                ? null
                : (reply.length > _maxReplySnapshotLength
                    ? reply.substring(0, _maxReplySnapshotLength)
                    : reply),
          );
      if (!_alive) return true;
      _recent = [..._recent, msg];
      final stillOpen = state.selected?.firebaseUid == friend.firebaseUid;
      _update((s) => s.copyWith(
            isSending: false,
            replyTarget: stillOpen ? () => null : null,
            messages: (stillOpen && s.messages.every((m) => m.id != msg.id))
                ? [...s.messages, msg]
                : s.messages,
          ));
      _rebuildConversations();
      return true;
    } catch (e) {
      if (!_alive) return false;
      final code = e is DioException ? e.response?.statusCode : null;
      final message = (code == 401 || code == 403)
          ? 'Gagal kirim. Kalian mungkin udah nggak berteman.'
          : errorMessage(e, 'Gagal mengirim pesan');
      _update((s) => s.copyWith(isSending: false, sendError: () => message));
      return false;
    }
  }

  void _applyIncoming(PrivateMessage msg) {
    final uid = _myUid;
    if (msg.recipientUid != uid) return;
    if (_recent.any((m) => m.id == msg.id)) return;

    final isOpen = state.selected?.firebaseUid == msg.senderUid;
    final stored = isOpen ? msg.withReadAt(DateTime.now().toUtc().toIso8601String()) : msg;
    _recent = [..._recent, stored];

    // Pengirim belum ada di daftar teman lokal (baru diterima) -> muat ulang.
    if (_friends.every((f) => f.firebaseUid != msg.senderUid)) {
      loadConversations(showLoading: false);
      return;
    }
    if (isOpen) {
      _update((s) => s.copyWith(messages: [...s.messages, stored]));
      unawaited(ref
          .read(privateChatRepositoryProvider)
          .markRead(uid, msg.senderUid)
          .catchError((_) {}));
    }
    _rebuildConversations();
  }
}

final privateChatControllerProvider =
    NotifierProvider.autoDispose<PrivateChatController, PrivateChatState>(
  PrivateChatController.new,
);
