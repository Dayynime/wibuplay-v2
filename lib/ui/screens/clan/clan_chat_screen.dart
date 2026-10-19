import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/clan_chat_models.dart';
import '../../../data/models/clan_models.dart';
import '../../../data/repository/safety_repository.dart' show ReportChannel;
import '../../../providers.dart';
import '../../glass/glass.dart';
import '../chat/chat_screen.dart' show ChatMessageBubble, ChatEntryAnimation, parseChatHex;
import '../profile/public_profile_screen.dart';
import '../safety/safety_actions.dart';
import 'clan_chat_controller.dart';

/// Chat internal clan sebagai layar penuh (tombol Chat Clan di halaman Clan).
class ClanChatScreen extends StatelessWidget {
  const ClanChatScreen({super.key, required this.clanName, required this.myRole});

  final String clanName;
  final String myRole;

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat Clan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(
              clanName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: ClanChatPane(myRole: myRole),
    );
  }
}

/// Isi chat clan tanpa Scaffold/AppBar, dipakai layar penuh di atas dan tab
/// "Clan" di Chat Global. Hanya member clan yang bisa memakainya (server yang
/// memverifikasi keanggotaan, bukan sekadar tombol disembunyikan).
///
/// Tampilannya memakai komponen yang sama dengan Chat Global (bubble, input,
/// bar balasan, animasi pesan masuk), jadi kalau Chat Global diubah, chat clan
/// ikut berubah.
class ClanChatPane extends ConsumerStatefulWidget {
  const ClanChatPane({super.key, required this.myRole});

  final String myRole;

  @override
  ConsumerState<ClanChatPane> createState() => _ClanChatPaneState();
}

class _ClanChatPaneState extends ConsumerState<ClanChatPane> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _focus = FocusNode();

  /// Pesan yang masuk setelah muatan awal (dianimasikan, seperti Chat Global).
  final Set<int> _live = {};
  final Set<int> _played = {};

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

  String _nameOf(ClanChatState s, String uid) {
    final n = s.profiles[uid]?.username ?? '';
    return n.isEmpty ? 'Pengguna' : n;
  }

  /// Ubah pesan clan ke ChatMessage supaya bisa dirender bubble Chat Global.
  ChatMessage _toChat(ClanChatState s, ClanMessage m, ClanMessage? replied) {
    final p = s.profiles[m.firebaseUid];
    final hasReply = m.replyToId != null;
    return ChatMessage(
      id: m.id,
      firebaseUid: m.firebaseUid,
      username: _nameOf(s, m.firebaseUid),
      avatarUrl: p?.avatarUrl,
      message: m.message,
      createdAt: m.createdAt.toIso8601String(),
      replyToId: m.replyToId,
      replyToUsername:
          hasReply ? (replied == null ? 'Pesan' : _nameOf(s, replied.firebaseUid)) : null,
      replyToMessage: hasReply ? (replied?.message ?? 'Pesan tidak tersedia') : null,
    );
  }

  Future<void> _requestDelete(ClanMessage m, bool own) async {
    if (own) {
      await ref.read(clanChatControllerProvider.notifier).delete(m);
      return;
    }
    // Pesan orang lain wajib konfirmasi dulu (aksi moderasi).
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Hapus pesan?', style: TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Pesan ini akan dihapus untuk semua anggota clan.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(clanChatControllerProvider.notifier).delete(m);
    }
  }

  void _openActions(ClanChatState s, ClanMessage m, bool own, String myUid) {
    HapticFeedback.selectionClick();
    final name = _nameOf(s, m.firebaseUid);
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
                ref.read(clanChatControllerProvider.notifier).setReplyTarget(m);
                _focus.requestFocus();
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
            if (!own && myUid.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.errorRed),
                title: const Text('Laporkan pesan', style: TextStyle(color: AppColors.textWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  showReportSheet(
                    context,
                    ref,
                    targetUid: m.firebaseUid,
                    targetName: name,
                    channel: ReportChannel.clan,
                    messageId: m.id,
                    messageText: m.message,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: AppColors.errorRed),
                title: Text('Blokir $name', style: const TextStyle(color: AppColors.textWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  confirmBlockUser(context, ref, uid: m.firebaseUid, name: name);
                },
              ),
            ],
            if (own || _canModerate)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.errorRed),
                title: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  _requestDelete(m, own);
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

    ref.listen<ClanChatState>(clanChatControllerProvider, (prev, next) {
      // Muatan awal (isLoading true -> false) tidak dianimasikan.
      if (prev == null || prev.isLoading) return;
      final maxPrev = prev.messages.fold<int>(0, (a, m) => m.id > a ? m.id : a);
      for (final m in next.messages) {
        if (m.id > maxPrev) _live.add(m.id);
      }
    });

    return Column(
      children: [
        Expanded(child: _buildList(s, myUid)),
        if (s.replyTarget != null) _buildReplyBar(s),
        if (s.sendError != null)
          Container(
            width: double.infinity,
            color: AppColors.backgroundDarkSecondary,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              s.sendError!,
              style: const TextStyle(color: AppColors.errorRed, fontSize: 11.5),
            ),
          ),
        _buildInput(s),
      ],
    );
  }

  Widget _buildList(ClanChatState s, String myUid) {
    if (s.isLoading && s.messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      );
    }
    if (s.error != null && s.messages.isEmpty) {
      return Center(
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
    }
    // Pesan dari pengguna yang diblokir disembunyikan (sama dengan Chat Global).
    final blocked = ref.watch(blockedUsersProvider);
    final byId = {for (final m in s.messages) m.id: m};
    final msgs = blocked.isEmpty
        ? s.messages
        : s.messages.where((m) => !blocked.contains(m.firebaseUid)).toList();
    if (msgs.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada pesan. Sapa clan kamu duluan!',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    // reverse: true -> pesan terbaru menempel di bawah dan list tetap di sana.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: msgs.length,
      itemBuilder: (context, i) {
        final m = msgs[msgs.length - 1 - i];
        final own = m.firebaseUid == myUid;
        final p = s.profiles[m.firebaseUid];
        final replied = m.replyToId == null ? null : byId[m.replyToId];
        final bubble = ChatMessageBubble(
          key: ValueKey('cm-${m.id}'),
          message: _toChat(s, m, replied),
          mine: own,
          nameColor: parseChatHex(p?.usernameColor),
          userNumber: p?.userNumber,
          avatarUrl: p?.avatarUrl,
          onLongPress: () => _openActions(s, m, own, myUid),
          onReply: () {
            ref.read(clanChatControllerProvider.notifier).setReplyTarget(m);
            _focus.requestFocus();
          },
          onDelete: (own || _canModerate) ? () => _requestDelete(m, own) : null,
          onProfileTap: own ? null : () => openPublicProfile(context, m.firebaseUid),
        );
        if (!_live.contains(m.id)) return bubble;
        return ChatEntryAnimation(
          key: ValueKey('entry_${m.id}'),
          animate: !_played.contains(m.id),
          fromRight: own,
          onPlayed: () => _played.add(m.id),
          child: bubble,
        );
      },
    );
  }

  Widget _buildReplyBar(ClanChatState s) {
    final target = s.replyTarget!;
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
                  'Membalas ${_nameOf(s, target.firebaseUid)}',
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
            onPressed: () =>
                ref.read(clanChatControllerProvider.notifier).setReplyTarget(null),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(ClanChatState s) {
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
                focusNode: _focus,
                maxLines: 4,
                minLines: 1,
                maxLength: kClanChatMaxLength,
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
                onPressed: s.isSending ? null : _send,
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
                    : const Icon(Icons.send_rounded, size: 20, color: AppColors.textWhite),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
