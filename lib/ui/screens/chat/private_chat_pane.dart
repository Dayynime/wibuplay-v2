import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repository/safety_repository.dart' show ReportChannel;
import '../../../providers.dart';
import '../safety/safety_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../gift/gift_premium_sheet.dart';
import '../../../data/models/friend_models.dart';
import '../../components/friend_avatar.dart';
import '../../components/swipe_to_reply.dart';
import 'private_chat_controller.dart';
import '../chess/chess_invite.dart';
import '../../../data/models/sticker_models.dart';
import '../sticker/sticker_widgets.dart';
import '../../glass/glass.dart';
import '../../components/game_badges.dart';
import '../../redesign/chat_kit.dart';
import '../../redesign/z_kit.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _dmTime(PrivateMessage m) {
  final t = m.time;
  return t == null ? '' : '${_two(t.hour)}:${_two(t.minute)}';
}

/// Isi tab "Teman": daftar percakapan (kalau belum memilih chat) atau ruang
/// chat 1-lawan-1. Input bar selalu tampil di bawah, nonaktif dengan
/// placeholder "Pilih chat untuk lanjut percakapan" sampai user memilih teman
/// (port PrivateChatPane.kt).
class PrivateChatPane extends ConsumerStatefulWidget {
  const PrivateChatPane({
    super.key,
    required this.myUid,
    required this.onFriendProfileClick,
    this.myUsername = 'Kamu',
    this.myAvatarUrl,
  });

  final String myUid;

  /// Nama & foto sendiri (pesanku tampil lengkap seperti Chat Global).
  final String myUsername;
  final String? myAvatarUrl;
  final ValueChanged<String> onFriendProfileClick;

  @override
  ConsumerState<PrivateChatPane> createState() => _PrivateChatPaneState();
}

class _PrivateChatPaneState extends ConsumerState<PrivateChatPane> {
  final TextEditingController _input = TextEditingController();

  PrivateChatController get _controller => ref.read(privateChatControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _controller.ensureStarted();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    final ok = await _controller.sendMessage(text);
    if (ok) _input.clear();
  }

  /// Nama di kutipan reply: "Kamu" untuk pesan sendiri.
  String _author(String? senderUid, FriendDisplay friend) =>
      senderUid == widget.myUid ? 'Kamu' : friend.username;

  void _showActions(PrivateMessage m) {
    showGlassSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply, color: AppColors.accentViolet),
              title: const Text('Balas', style: TextStyle(color: AppColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                _controller.setReplyTarget(m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: AppColors.accentViolet),
              title: const Text('Salin', style: TextStyle(color: AppColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: m.message));
              },
            ),
            if (m.senderUid != widget.myUid)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.errorRed),
                title: const Text('Laporkan pesan', style: TextStyle(color: AppColors.textWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  final friend = ref.read(privateChatControllerProvider).selected;
                  showReportSheet(
                    context,
                    ref,
                    targetUid: m.senderUid,
                    targetName: friend?.username ?? 'Pengguna',
                    channel: ReportChannel.private,
                    messageId: m.id,
                    messageText: m.message,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(privateChatControllerProvider);

    ref.listen<String?>(privateChatControllerProvider.select((x) => x.sendError), (prev, next) {
      if (next == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next)));
      _controller.clearSendError();
    });

    return Column(
      children: [
        Expanded(child: _buildContent(s)),
        if (s.replyTarget != null && s.selected != null)
          _ReplyPreviewBar(
            username: _author(s.replyTarget!.senderUid, s.selected!),
            message: stickerPreviewText(s.replyTarget!.message),
            onCancel: _controller.clearReplyTarget,
          ),
        _DmInputBar(
          controller: _input,
          enabled: s.selected != null &&
              !ref.watch(blockedUsersProvider).contains(s.selected!.firebaseUid),
          isSending: s.isSending,
          onSend: _send,
          onSticker: (t) => _controller.sendMessage(t),
        ),
      ],
    );
  }

  Widget _buildContent(PrivateChatState s) {
    final blocked = ref.watch(blockedUsersProvider);
    final selected = s.selected;
    if (selected != null && !blocked.contains(selected.firebaseUid)) {
      return _buildConversation(s, selected);
    }
    if (s.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      );
    }
    if (s.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              TextButton(
                onPressed: _controller.loadConversations,
                child: const Text('Coba lagi', style: TextStyle(color: AppColors.accentViolet)),
              ),
            ],
          ),
        ),
      );
    }
    final conversations = blocked.isEmpty
        ? s.conversations
        : s.conversations.where((c) => !blocked.contains(c.friend.firebaseUid)).toList();
    if (conversations.isEmpty) return const _EmptyConversations();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = conversations[i];
        return _ConversationRow(
          key: ValueKey(item.friend.friendshipId),
          item: item,
          onTap: () => _controller.openChat(item.friend),
        );
      },
    );
  }

  Widget _buildConversation(PrivateChatState s, FriendDisplay friend) {
    final msgs = s.messages;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Kembali ke daftar chat',
                onPressed: _controller.closeChat,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.onFriendProfileClick(friend.firebaseUid),
                  child: Row(
                    children: [
                      UserAvatar(
                        username: friend.username,
                        url: friend.avatarUrl,
                        size: 36,
                        frameUid: friend.firebaseUid,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              friend.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZFont.display(size: 15.5),
                            ),
                            const Text(
                              'Chat pribadi · ketuk untuk lihat profil',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Gift Premium',
                onPressed: () async {
                  final row = await showGiftPremiumSheet(
                    context,
                    recipientUid: friend.firebaseUid,
                    recipientName: friend.username,
                    channel: 'private',
                  );
                  if (row != null && mounted) {
                    _controller.addOwnMessage(PrivateMessage.fromJson(row));
                  }
                },
                icon: const Icon(Icons.card_giftcard, color: Color(0xFFF5B73B)),
              ),
              PopupMenuButton<String>(
                tooltip: 'Lainnya',
                color: AppColors.surfaceDark,
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (v) async {
                  if (v == 'report') {
                    showReportSheet(
                      context,
                      ref,
                      targetUid: friend.firebaseUid,
                      targetName: friend.username,
                      channel: ReportChannel.private,
                    );
                  } else if (v == 'block') {
                    final done = await confirmBlockUser(
                      context,
                      ref,
                      uid: friend.firebaseUid,
                      name: friend.username,
                    );
                    if (done && mounted) _controller.closeChat();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'report',
                    child: Text('Laporkan', style: TextStyle(color: AppColors.textWhite)),
                  ),
                  PopupMenuItem(
                    value: 'block',
                    child: Text('Blokir', style: TextStyle(color: AppColors.errorRed)),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: s.isLoadingMessages
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.accentViolet,
                    strokeWidth: 3,
                  ),
                )
              : msgs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Belum ada pesan. Sapa ${friend.username}, yuk!',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      // reverse: pesan terbaru menempel di bawah.
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final idx = msgs.length - 1 - i;
                        final m = msgs[idx];
                        final own = m.senderUid == widget.myUid;
                        // Rombongan: pesan beruntun dari orang yang sama (<= 3 menit).
                        bool same(int j) =>
                            j >= 0 &&
                            j < msgs.length &&
                            zSameGroup(m.senderUid, DateTime.tryParse(m.createdAt), msgs[j].senderUid,
                                DateTime.tryParse(msgs[j].createdAt));
                        return _DmBubble(
                          key: ValueKey(m.id),
                          message: m,
                          isOwn: own,
                          pos: zGroupPos(olderSame: same(idx - 1), newerSame: same(idx + 1)),
                          name: own ? widget.myUsername : friend.username,
                          uid: own ? widget.myUid : friend.firebaseUid,
                          avatarUrl: own ? widget.myAvatarUrl : friend.avatarUrl,
                          onAvatarTap: own ? null : () => widget.onFriendProfileClick(friend.firebaseUid),
                          replyAuthor: (m.replyToMessage == null)
                              ? null
                              : _author(m.replyToSenderUid, friend),
                          onReply: () => _controller.setReplyTarget(m),
                          onLongPress: () => _showActions(m),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Belum Ada Chat',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Tambah teman dari profil user lain, nanti kalian bisa chat private di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({super.key, required this.item, required this.onTap});

  final ConversationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = item.unread;
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              FriendAvatar(
                url: item.friend.avatarUrl,
                seed: item.friend.firebaseUid,
                label: item.friend.username,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.friend.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.lastMessage?.message ?? 'Belum ada pesan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: unread > 0 ? 0.9 : 0.55),
                        fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentViolet,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DmBubble extends StatelessWidget {
  const _DmBubble({
    super.key,
    required this.message,
    required this.isOwn,
    required this.name,
    required this.uid,
    required this.avatarUrl,
    required this.replyAuthor,
    required this.onReply,
    required this.onLongPress,
    this.onAvatarTap,
    this.pos = ZGroupPos.single,
  });

  final PrivateMessage message;
  final ZGroupPos pos;
  final bool isOwn;
  final String name;
  final String uid;
  final String? avatarUrl;
  final String? replyAuthor;
  final VoidCallback onReply;
  final VoidCallback onLongPress;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    // Gaya sama dengan Chat Global & Clan (chat_kit): avatar + nama di
    // kedua sisi, gelembung biru untuk pesanku.
    final sticker = stickerCodeOf(m.message);
    final chess = chessInviteCode(m.message) != null;
    final bare = replyAuthor == null && (m.isGift || chess || sticker != null);

    final Widget content;
    if (m.isGift) {
      content = GiftBubbleCard(
        days: m.giftDays!,
        title: isOwn ? 'Kamu memberi Premium' : 'Kamu menerima Premium!',
      );
    } else if (chess) {
      content = ChessInviteCard(message: m.message, mine: isOwn);
    } else if (sticker != null) {
      content = StickerView(code: sticker);
    } else {
      content = Text(
        m.message,
        style: TextStyle(color: isOwn ? Colors.white : AppColors.textWhite, fontSize: 14, height: 1.35),
      );
    }

    return SwipeToReply(
      onReply: onReply,
      child: ZChatRow(
        mine: isOwn,
        avatar: GestureDetector(
          onTap: onAvatarTap,
          child: UserAvatar(username: name, url: avatarUrl, size: 36, frameUid: uid),
        ),
        pos: pos,
        header: ZChatHeader(
          mine: isOwn,
          nameRow: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.accentVioletLight,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        bubble: GestureDetector(
          onLongPress: onLongPress,
          child: ZChatBubble(
            mine: isOwn,
            bare: bare,
            pos: pos,
            time: _dmTime(m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyAuthor != null)
                  ZChatQuote(
                    author: replyAuthor!,
                    text: stickerPreviewText(m.replyToMessage ?? ''),
                    mine: isOwn,
                  ),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyPreviewBar extends StatelessWidget {
  const _ReplyPreviewBar({
    required this.username,
    required this.message,
    required this.onCancel,
  });

  final String username;
  final String message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) =>
      ZChatReplyBar(name: username, text: message, onClose: onCancel);
}

class _DmInputBar extends StatelessWidget {
  const _DmInputBar({
    required this.controller,
    required this.enabled,
    required this.isSending,
    required this.onSend,
    required this.onSticker,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;
  final ValueChanged<String> onSticker;

  @override
  Widget build(BuildContext context) {
    return ZChatComposer(
      children: [
        StickerButton(enabled: enabled && !isSending, onPicked: onSticker),
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            maxLines: 4,
            minLines: 1,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
            cursorColor: AppColors.accentViolet,
            decoration: zChatInputDecoration(enabled ? 'Tulis pesan...' : 'Pilih chat untuk lanjut percakapan'),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final canSend = enabled && value.text.trim().isNotEmpty && !isSending;
            return ZChatRoundButton(
              onPressed: canSend ? onSend : null,
              child: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textWhite),
                    )
                  : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
            );
          },
        ),
      ],
    );
  }
}
