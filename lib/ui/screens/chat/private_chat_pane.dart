import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/friend_models.dart';
import '../../components/friend_avatar.dart';
import '../../components/swipe_to_reply.dart';
import 'private_chat_controller.dart';

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
  });

  final String myUid;
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
    showModalBottomSheet<void>(
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
            message: s.replyTarget!.message,
            onCancel: _controller.clearReplyTarget,
          ),
        _DmInputBar(
          controller: _input,
          enabled: s.selected != null,
          isSending: s.isSending,
          onSend: _send,
        ),
      ],
    );
  }

  Widget _buildContent(PrivateChatState s) {
    final selected = s.selected;
    if (selected != null) return _buildConversation(s, selected);
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
    if (s.conversations.isEmpty) return const _EmptyConversations();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: s.conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = s.conversations[i];
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
          color: AppColors.surfaceDark,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Kembali ke daftar chat',
                onPressed: _controller.closeChat,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => widget.onFriendProfileClick(friend.firebaseUid),
                  child: Row(
                    children: [
                      FriendAvatar(
                        url: friend.avatarUrl,
                        seed: friend.firebaseUid,
                        label: friend.username,
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          friend.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                        final m = msgs[msgs.length - 1 - i];
                        return _DmBubble(
                          key: ValueKey(m.id),
                          message: m,
                          isOwn: m.senderUid == widget.myUid,
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
    required this.replyAuthor,
    required this.onReply,
    required this.onLongPress,
  });

  final PrivateMessage message;
  final bool isOwn;
  final String? replyAuthor;
  final VoidCallback onReply;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final quoteAccent = isOwn ? Colors.white : const Color(0xFFFFB3BB);
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isOwn ? AppColors.accentViolet : AppColors.surfaceDark,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOwn ? 16 : 4),
            bottomRight: Radius.circular(isOwn ? 4 : 16),
          ),
        ),
        // IntrinsicWidth: lebar bubble mengikuti isi (pendek = sempit), baru
        // mentok di 280, seperti bubble DM di Zenime. Tanpa ini Align jam
        // memenuhi lebar maksimum sehingga semua bubble jadi lebar.
        child: IntrinsicWidth(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (replyAuthor != null) ...[
              // Kutipan reply: bar aksen di kiri + background gelap.
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: const Color(0x8C0B0B12),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 3, color: quoteAccent),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  replyAuthor!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: quoteAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  m.replyToMessage ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xD9FFFFFF),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              m.message,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _dmTime(m),
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 10),
              ),
            ),
          ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SwipeToReply(
        onReply: onReply,
        child: Row(
          mainAxisAlignment: isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [Flexible(child: bubble)],
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
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceDark,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(width: 3, height: 30, color: AppColors.accentViolet),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Membalas $username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.accentVioletLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _DmInputBar extends StatelessWidget {
  const _DmInputBar({
    required this.controller,
    required this.enabled,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundDarkSecondary,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
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
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surfaceDark,
                  hintText: enabled ? 'Tulis pesan...' : 'Pilih chat untuk lanjut percakapan',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 46,
              height: 46,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final canSend = enabled && value.text.trim().isNotEmpty && !isSending;
                  return IconButton.filled(
                    onPressed: canSend ? onSend : null,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.accentViolet,
                      disabledBackgroundColor: AppColors.surfaceElevated,
                    ),
                    icon: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textWhite,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 20, color: AppColors.textWhite),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
