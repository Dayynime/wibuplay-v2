import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_chat_models.dart';
import '../../../data/models/clan_models.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';
import '../profile/public_profile_screen.dart';
import 'clan_chat_controller.dart';

/// Chat internal clan. Hanya member clan yang bisa buka (server yang
/// memverifikasi, bukan sekadar tombol disembunyikan).
class ClanChatScreen extends ConsumerStatefulWidget {
  const ClanChatScreen({super.key, required this.clanName, required this.myRole});

  final String clanName;
  final String myRole;

  @override
  ConsumerState<ClanChatScreen> createState() => _ClanChatScreenState();
}

class _ClanChatScreenState extends ConsumerState<ClanChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _focus = FocusNode();

  bool get _canModerate => ClanRoles.rank(widget.myRole) >= 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(clanChatControllerProvider.notifier)
        .setActive(state == AppLifecycleState.resumed);
  }

  Future<void> _send() async {
    final ok = await ref.read(clanChatControllerProvider.notifier).send(_input.text);
    if (ok) _input.clear();
  }

  void _openActions(ClanMessage m, bool own) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.backgroundDarkSecondary,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply, color: AppColors.textWhite),
              title: const Text('Balas', style: TextStyle(color: AppColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(clanChatControllerProvider.notifier).setReplyTarget(m);
                _focus.requestFocus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: AppColors.textWhite),
              title: const Text('Salin', style: TextStyle(color: AppColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: m.message));
              },
            ),
            if (own || _canModerate)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFFF8A98)),
                title: const Text('Hapus', style: TextStyle(color: Color(0xFFFF8A98))),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(clanChatControllerProvider.notifier).delete(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(clanChatControllerProvider);
    final myUid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid)) ?? '';
    final byId = {for (final m in s.messages) m.id: m};
    final reversed = s.messages.reversed.toList();

    Widget body;
    if (s.isLoading && s.messages.isEmpty) {
      body = const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      );
    } else if (s.error != null && s.messages.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(clanChatControllerProvider.notifier).retry(),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    } else if (s.messages.isEmpty) {
      body = const Center(
        child: Text(
          'Belum ada pesan. Sapa clan kamu duluan!',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    } else {
      body = ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        itemCount: reversed.length,
        itemBuilder: (context, i) {
          final m = reversed[i];
          final own = m.firebaseUid == myUid;
          // reversed: elemen sebelumnya di layar = index i + 1
          final older = i + 1 < reversed.length ? reversed[i + 1] : null;
          final showHeader = older == null || older.firebaseUid != m.firebaseUid;
          final p = s.profiles[m.firebaseUid];
          final replied = m.replyToId == null ? null : byId[m.replyToId];
          return _Bubble(
            key: ValueKey('cm-${m.id}'),
            message: m,
            own: own,
            showHeader: showHeader,
            username: (p?.username ?? '').isEmpty ? 'Pengguna' : p!.username,
            avatarUrl: p?.avatarUrl,
            replied: replied,
            repliedName: replied == null
                ? null
                : ((s.profiles[replied.firebaseUid]?.username ?? '').isEmpty
                    ? 'Pengguna'
                    : s.profiles[replied.firebaseUid]!.username),
            onLongPress: () => _openActions(m, own),
            onAvatarTap: () => openPublicProfile(context, m.firebaseUid),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat Clan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(
              widget.clanName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: body),
          if (s.replyTarget != null)
            Container(
              color: AppColors.backgroundDarkSecondary,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Container(width: 3, height: 30, color: AppColors.accentViolet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Membalas: ${s.replyTarget!.message}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        ref.read(clanChatControllerProvider.notifier).setReplyTarget(null),
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          if (s.sendError != null)
            Container(
              width: double.infinity,
              color: AppColors.backgroundDarkSecondary,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                s.sendError!,
                style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11.5),
              ),
            ),
          Container(
            color: AppColors.backgroundDarkSecondary,
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              8 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: kClanChatMaxLength,
                    inputFormatters: [LengthLimitingTextInputFormatter(kClanChatMaxLength)],
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Tulis pesan...',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.surfaceDark,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: AppColors.accentViolet),
                    onPressed: s.isSending ? null : _send,
                    icon: s.isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.own,
    required this.showHeader,
    required this.username,
    required this.avatarUrl,
    required this.replied,
    required this.repliedName,
    required this.onLongPress,
    required this.onAvatarTap,
  });

  final ClanMessage message;
  final bool own;
  final bool showHeader;
  final String username;
  final String? avatarUrl;
  final ClanMessage? replied;
  final String? repliedName;
  final VoidCallback onLongPress;
  final VoidCallback onAvatarTap;

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.74;
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: own ? AppColors.accentViolet : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!own && showHeader)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: GestureDetector(
                  onTap: onAvatarTap,
                  child: Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.accentVioletLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (message.replyToId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                decoration: const BoxDecoration(
                  color: Color(0x26000000),
                  border: Border(left: BorderSide(color: Colors.white54, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      replied == null ? 'Pesan' : (repliedName ?? 'Pengguna'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      replied?.message ?? 'Pesan tidak tersedia',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            Text(
              message.message,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 14, height: 1.3),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _hm(message.createdAt),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );

    if (own) {
      return Padding(
        padding: EdgeInsets.only(top: showHeader ? 10 : 2),
        child: Align(alignment: Alignment.centerRight, child: bubble),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: showHeader ? 10 : 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 34,
            child: showHeader
                ? GestureDetector(
                    onTap: onAvatarTap,
                    child: UserAvatar(username: username, url: avatarUrl, size: 30),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}
