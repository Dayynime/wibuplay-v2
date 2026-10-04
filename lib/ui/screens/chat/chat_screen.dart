import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import 'chat_controller.dart';

Color? _parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _timeLabel(ChatMessage m) {
  final t = m.time;
  return t == null ? '' : '${_two(t.hour)}:${_two(t.minute)}';
}

/// Chat Global yang sama dengan Zenime (tabel + realtime yang sama).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  ChatController get _controller => ref.read(chatControllerProvider.notifier);

  Future<void> _send() async {
    final ok = await _controller.send(_input.text);
    if (ok) _input.clear();
  }

  void _showActions(ChatMessage m, ChatUiState s) {
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
            if (m.firebaseUid == s.myUid)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.errorRed),
                title: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  _controller.deleteMessage(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(chatControllerProvider);

    ref.listen<String?>(chatControllerProvider.select((x) => x.errorMessage), (prev, next) {
      if (next == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next)));
      _controller.clearError();
    });

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        title: const Text('Chat Global'),
      ),
      body: Column(
        children: [
          Expanded(child: _buildList(s)),
          if (s.replyTarget != null) _buildReplyBar(s.replyTarget!),
          _buildInput(s),
        ],
      ),
    );
  }

  Widget _buildList(ChatUiState s) {
    if (s.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      );
    }
    if (s.messages.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada pesan. Jadi yang pertama!',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    final msgs = s.messages;
    // reverse: true -> pesan terbaru menempel di bawah dan list tetap di sana.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: msgs.length,
      itemBuilder: (context, i) {
        final m = msgs[msgs.length - 1 - i];
        return _MessageBubble(
          key: ValueKey(m.id),
          message: m,
          mine: m.firebaseUid == s.myUid,
          nameColor: _parseHex(s.usernameColors[m.firebaseUid]),
          userNumber: s.userNumbers[m.firebaseUid],
          avatarUrl: s.avatarUrls[m.firebaseUid] ?? m.avatarUrl,
          onLongPress: () => _showActions(m, s),
        );
      },
    );
  }

  Widget _buildReplyBar(ChatMessage target) {
    return Container(
      color: AppColors.surfaceDark,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: AppColors.accentViolet),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Membalas ${target.username}',
                  style: const TextStyle(
                    color: AppColors.accentVioletLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  target.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
            onPressed: _controller.clearReplyTarget,
          ),
        ],
      ),
    );
  }

  Widget _buildInput(ChatUiState s) {
    final blocked = s.cooldownSeconds > 0 || s.isSending;
    return Container(
      color: AppColors.backgroundDarkSecondary,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLines: 4,
                minLines: 1,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
                cursorColor: AppColors.accentViolet,
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surfaceDark,
                  hintText: 'Tulis pesan...',
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
              child: IconButton.filled(
                onPressed: blocked ? null : _send,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accentViolet,
                  disabledBackgroundColor: AppColors.surfaceElevated,
                ),
                icon: s.isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textWhite,
                        ),
                      )
                    : s.cooldownSeconds > 0
                        ? Text(
                            '${s.cooldownSeconds}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 20, color: AppColors.textWhite),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.onLongPress,
    this.nameColor,
    this.userNumber,
    this.avatarUrl,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback onLongPress;
  final Color? nameColor;
  final int? userNumber;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final hasReply = (m.replyToUsername ?? '').isNotEmpty;
    final bubbleColor = mine ? AppColors.accentVioletDark : AppColors.surfaceCard;

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bubbleColor, borderRadius: AppShapes.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    m.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: nameColor ?? AppColors.accentVioletLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (userNumber != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '#$userNumber',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                ],
              ],
            ),
            if (hasReply) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                    left: BorderSide(color: AppColors.accentViolet, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.replyToUsername!,
                      style: const TextStyle(
                        color: AppColors.accentVioletLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      m.replyToMessage ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              m.message,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 14, height: 1.3),
            ),
            if (m.isVoice)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  'Pesan suara (belum bisa diputar di Wibuplay)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _timeLabel(m),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );

    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.surfaceVariantDark,
      backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? CachedNetworkImageProvider(avatarUrl!)
          : null,
      child: (avatarUrl == null || avatarUrl!.isEmpty)
          ? Text(
              m.username.isEmpty ? '?' : m.username.characters.first.toUpperCase(),
              style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
            )
          : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: mine
            ? [bubble]
            : [avatar, const SizedBox(width: 8), Flexible(child: bubble)],
      ),
    );
  }
}
