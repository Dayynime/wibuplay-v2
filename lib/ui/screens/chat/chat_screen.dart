import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/image_cache.dart';
import '../../../core/lite_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../data/repository/safety_repository.dart' show ReportChannel;
import '../safety/safety_actions.dart';
import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/repository/profile_image_uploader.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../gift/gift_premium_sheet.dart';
import '../gift/giveaway.dart';
import '../../components/activity_status.dart';
import '../../components/game_badges.dart';
import '../../components/role_badges.dart';
import '../../components/top_giver_badge.dart';
import '../../components/swipe_to_reply.dart';
import '../friends/friends_screen.dart';
import '../profile/public_profile_screen.dart';
import 'private_chat_controller.dart';
import 'clan_chat_tab.dart';
import 'wp_event_chat_card.dart';
import '../chess/chess_invite.dart';
import '../../../data/models/sticker_models.dart';
import '../../../data/repository/chat_unread_repository.dart';
import '../sticker/sticker_widgets.dart';
import 'private_chat_pane.dart';
import 'chat_controller.dart';
import 'chat_mute.dart';
import 'chat_pin.dart';
import 'chat_reactions.dart';
import 'chat_mention.dart';
import '../../components/avatar_frame.dart';
import '../../glass/glass.dart';
import '../../components/clan_tag_badge.dart';
import '../../components/user_level_badge.dart';
import '../../redesign/chat_kit.dart';
import '../../redesign/z_kit.dart';

Color? parseChatHex(String? hex) {
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
  const ChatScreen({super.key, this.initialTab = 0, this.openPeerUid});

  /// 0 = Global, 1 = Teman, 2 = Clan.
  final int initialTab;

  /// Langsung buka chat dengan teman ini (dari notifikasi pesan pribadi).
  final String? openPeerUid;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  late final MentionTracker _mention = MentionTracker(_input);

  /// 0 = Chat Global, 1 = Chat Teman (tab Teman ala Zenime), 2 = Chat Clan.
  late int _tab = widget.initialTab.clamp(0, 2);

  /// Teman yang chat-nya dibuka otomatis begitu daftar chat termuat.
  late String? _pendingPeer = widget.openPeerUid;

  /// Jumlah belum dibaca dari server (badge tab). Disegarkan berkala selama
  /// layar Chat terbuka; tab Clan yang sedang dilihat otomatis ditandai dibaca.
  ChatUnread _unread = const ChatUnread();
  Timer? _unreadTimer;
  late final ChatUnreadRepository _unreadRepo;

  @override
  void initState() {
    super.initState();
    _unreadRepo = ref.read(chatUnreadRepositoryProvider);
    _refreshUnread();
    _unreadTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshUnread());
  }

  Future<void> _refreshUnread() async {
    if (ref.read(authUserProvider).valueOrNull == null) return;
    try {
      final u = _tab == 2 ? await _unreadRepo.markClanRead() : await _unreadRepo.counts();
      if (mounted) setState(() => _unread = u);
    } catch (_) {
      // Badge cuma pemanis: gagal muat tidak mengganggu chat.
    }
  }

  void _setTab(int i) {
    if (_tab == i) return;
    final leavingClan = _tab == 2;
    setState(() => _tab = i);
    // Masuk tab Clan -> tandai dibaca. Keluar dari Clan -> tandai lagi supaya
    // pesan yang sempat dibaca di sana tidak dihitung.
    if (i == 2 || leavingClan) {
      if (leavingClan && i != 2) {
        _unreadRepo.markClanRead().then((u) {
          if (mounted) setState(() => _unread = u);
        }).catchError((Object _) {});
      } else {
        _refreshUnread();
      }
    }
  }

  /// Id pesan yang masuk SETELAH layar selesai memuat (kena animasi masuk).
  final Set<int> _live = {};

  /// Id yang animasinya sudah diputar, supaya tidak mengulang saat item
  /// di-scroll keluar lalu masuk lagi.
  final Set<int> _played = {};

  /// Untuk lompat ke pesan yang dibalas (tap kutipan reply).
  final ItemScrollController _itemScroll = ItemScrollController();

  /// Pesan yang sedang disorot sesudah lompat dari kutipan reply.
  int? _highlightId;

  Future<void> _jumpToMessage(ChatUiState s, int? id) async {
    if (id == null) return;
    final msgs = s.messages;
    final j = msgs.indexWhere((m) => m.id == id);
    if (j < 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Pesan yang dibalas sudah tidak dimuat')));
      return;
    }
    // List dibalik (reverse): index 0 = pesan terbaru.
    final index = msgs.length - 1 - j;
    if (_itemScroll.isAttached) {
      await _itemScroll.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    }
    if (!mounted) return;
    setState(() => _highlightId = id);
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted && _highlightId == id) setState(() => _highlightId = null);
    });
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    if (_tab == 2) {
      _unreadRepo.markClanRead().catchError((Object _) => const ChatUnread());
    }
    _input.dispose();
    super.dispose();
  }

  ChatController get _controller => ref.read(chatControllerProvider.notifier);

  void _openProfileDialog() {
    final s = ref.read(chatControllerProvider);
    if (s.myUid.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => _ChatProfileDialog(
        uid: s.myUid,
        username: s.myUsername,
        avatarUrl: s.avatarUrls[s.myUid] ?? s.myAvatarUrl,
        usernameColor: s.usernameColors[s.myUid],
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text;
    final ok = await _controller.send(text, mentionUids: _mention.uidsFor(text));
    if (ok) {
      _input.clear();
      _mention.clear();
    }
  }

  Future<void> _confirmDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Hapus pesan?', style: TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Pesan ini akan dihapus untuk semua orang di Chat Global.',
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
    if (ok == true) await _controller.deleteMessage(m);
  }

  void _showActions(ChatMessage m, ChatUiState s) {
    showGlassSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.myUid.isNotEmpty)
              ChatReactionPicker(
                channel: 'global',
                id: m.id,
                onPicked: (e) {
                  Navigator.pop(ctx);
                  reactToMessage(context, ref, 'global', m.id, e);
                },
              ),
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
            // Hapus pindah dari bawah gelembung ke menu ini (aturan izin sama).
            if ((m.firebaseUid == s.myUid || s.canDeleteOthers) && !m.isGift && !m.isGiveaway)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.errorRed),
                title: const Text('Hapus pesan', style: TextStyle(color: AppColors.errorRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(m);
                },
              ),
            if (m.firebaseUid != s.myUid && s.myUid.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.card_giftcard, color: Color(0xFFF5B73B)),
                title: Text(
                  'Gift Premium ke ${m.username}',
                  style: const TextStyle(color: AppColors.textWhite),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  // Bubble gift masuk lewat realtime chat global.
                  showGiftPremiumSheet(
                    context,
                    recipientUid: m.firebaseUid,
                    recipientName: m.username,
                    channel: 'global',
                  );
                },
              ),
            if (m.firebaseUid != s.myUid && s.myUid.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.errorRed),
                title: const Text('Laporkan pesan', style: TextStyle(color: AppColors.textWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  showReportSheet(
                    context,
                    ref,
                    targetUid: m.firebaseUid,
                    targetName: m.username,
                    channel: ReportChannel.global,
                    messageId: m.id,
                    messageText: m.message,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: AppColors.errorRed),
                title: Text(
                  'Blokir ${m.username}',
                  style: const TextStyle(color: AppColors.textWhite),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  confirmBlockUser(context, ref, uid: m.firebaseUid, name: m.username);
                },
              ),
              if (ref.read(canChatMuteProvider).valueOrNull == true)
                ListTile(
                  leading: const Icon(Icons.volume_off_rounded, color: AppColors.errorRed),
                  title: Text('Mute ${m.username}', style: const TextStyle(color: AppColors.textWhite)),
                  onTap: () {
                    Navigator.pop(ctx);
                    showChatMuteSheet(context, ref, uid: m.firebaseUid, name: m.username);
                  },
                ),
            ],
            // Sematkan pesan (developer/admin/moderator), termasuk pesan sendiri.
            if (ref.read(canChatMuteProvider).valueOrNull == true)
              ListTile(
                leading: const Icon(Icons.push_pin_outlined, color: AppColors.accentViolet),
                title: Text(
                  ref.read(chatPinsProvider).any((p) => p.id == m.id) ? 'Lepas sematan' : 'Sematkan pesan',
                  style: const TextStyle(color: AppColors.textWhite),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  toggleChatPin(context, ref, m.id);
                },
              ),
            // Pesan gift/giveaway permanen (tidak bisa dihapus siapa pun).
            if ((m.firebaseUid == s.myUid || s.canDeleteOthers) && !m.isGift && !m.isGiveaway)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.errorRed),
                title: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  // Pesan orang lain wajib konfirmasi dulu (aksi moderasi).
                  if (m.firebaseUid == s.myUid) {
                    _controller.deleteMessage(m);
                  } else {
                    _confirmDelete(m);
                  }
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
    ref.watch(canChatMuteProvider); // muat role lebih awal untuk menu Mute

    ref.listen<ChatUiState>(chatControllerProvider, (prev, next) {
      // Muatan awal (isLoading true -> false) tidak dianimasikan.
      if (prev == null || prev.isLoading) return;
      final maxPrev = prev.messages.fold<int>(0, (a, m) => m.id > a ? m.id : a);
      for (final m in next.messages) {
        if (m.id > maxPrev) _live.add(m.id);
      }
    });

    ref.listen<String?>(chatControllerProvider.select((x) => x.errorMessage), (prev, next) {
      if (next == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next)));
      _controller.clearError();
    });

    // Dipantau terus supaya state tab Teman (chat yang sedang dibuka) tidak
    // hilang saat pindah tab. Belum ada request ke server sampai tab dibuka.
    final inConversation =
        ref.watch(privateChatControllerProvider.select((x) => x.selected != null));

    // Dari notifikasi: buka chat teman itu begitu daftar percakapan siap.
    ref.listen<PrivateChatState>(privateChatControllerProvider, (prev, next) {
      final peer = _pendingPeer;
      if (peer == null || next.isLoading) return;
      for (final c in next.conversations) {
        if (c.friend.firebaseUid == peer) {
          _pendingPeer = null;
          ref.read(privateChatControllerProvider.notifier).openChat(c.friend);
          return;
        }
      }
      _pendingPeer = null; // bukan teman lagi / tidak ada di daftar
    });

    // Badge Teman: kalau daftar chat sudah dimuat (realtime) pakai hitungan
    // lokal, kalau belum pakai angka dari server.
    final localPrivate = ref.watch(privateChatControllerProvider.select(
      (x) => x.isLoading ? null : x.conversations.fold<int>(0, (a, c) => a + c.unread),
    ));
    final privateBadge = localPrivate ?? _unread.private;
    final clanBadge = _tab == 2 ? 0 : _unread.clan;

    return PopScope(
      // Back saat membuka chat teman = kembali ke daftar chat, bukan keluar.
      canPop: !(_tab == 1 && inConversation),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(privateChatControllerProvider.notifier).closeChat();
      },
      child: GlassScaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: GlassAppBar(
          backgroundColor: AppColors.backgroundDark,
          elevation: 0,
          title: _tab == 0
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text('Chat Global', style: ZFont.display(size: 17, height: 1.15)), const OnlineCountLabel()],
                )
              : Text(_tab == 1 ? 'Chat Teman' : 'Chat Clan', style: ZFont.display(size: 18)),
          actions: [
            if (_tab == 1)
              IconButton(
                tooltip: 'Teman',
                onPressed: () =>
                    Navigator.of(context).push<void>(fadeRoute(const FriendsScreen())),
                icon: const Icon(Icons.people_alt_outlined, color: Colors.white),
              ),
            // Pengaturan di pojok kanan atas -> Edit Profil Chat (sama dengan
            // ikon Settings di Chat Global Zenime).
            IconButton(
              tooltip: 'Edit Profil',
              onPressed: _openProfileDialog,
              icon: const Icon(Icons.settings, color: Colors.white),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildChatTabs(privateBadge, clanBadge),
            Expanded(
              child: _tab == 0
                  ? Column(
                      children: [
                        ChatPinBanner(
                          onJump: (id) {
                            if (!s.messages.any((m) => m.id == id)) return false;
                            _jumpToMessage(s, id);
                            return true;
                          },
                        ),
                        Expanded(child: _buildList(s)),
                        if (s.replyTarget != null) _buildReplyBar(s.replyTarget!),
                        ChatMuteGate(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [MentionSuggestions(tracker: _mention), _buildInput(s)],
                          ),
                        ),
                      ],
                    )
                  : _tab == 2
                      ? const ClanChatTab()
                      : PrivateChatPane(
                      myUid: s.myUid,
                      myUsername: s.myUsername.isEmpty ? 'Kamu' : s.myUsername,
                      myAvatarUrl: s.avatarUrls[s.myUid] ?? s.myAvatarUrl,
                      onFriendProfileClick: (uid) => openPublicProfile(context, uid),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab Global / Teman / Clan: segmented dengan indikator biru yang meluncur.
  Widget _buildChatTabs(int privateBadge, int clanBadge) {
    const labels = ['Global', 'Teman', 'Clan'];
    final badges = [0, privateBadge, clanBadge];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.backgroundDarkSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x12FFFFFF)),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth / labels.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutQuint,
                  left: _tab * w,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.accentViolet,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentViolet.withValues(alpha: 0.4),
                          blurRadius: 14,
                          spreadRadius: -6,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _setTab(i),
                          // Center: label & angka tepat di tengah pil (vertikal).
                          child: Center(
                            child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: TextStyle(
                                  color: _tab == i ? Colors.white : AppColors.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                                child: Text(labels[i]),
                              ),
                              _TabBadge(count: badges[i]),
                            ],
                          ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(ChatUiState s) {
    if (s.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      );
    }
    // Pesan dari pengguna yang diblokir disembunyikan.
    final blocked = ref.watch(blockedUsersProvider);
    final msgs = blocked.isEmpty
        ? s.messages
        : s.messages.where((m) => !blocked.contains(m.firebaseUid)).toList();
    if (msgs.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada pesan. Jadi yang pertama!',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    // Daftarkan pesan yang dimuat supaya reaksinya ikut diambil.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(chatReactionsProvider('global').notifier).track(msgs.map((m) => m.id));
    });
    // reverse: true -> pesan terbaru menempel di bawah dan list tetap di sana.
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: msgs.length,
      itemBuilder: (context, i) {
        final idx = msgs.length - 1 - i;
        final m = msgs[idx];
        if (m.isWpEvent) return WpEventChatCard(key: ValueKey(m.id), message: m);
        // Rombongan: pesan beruntun dari orang yang sama (<= 3 menit).
        bool same(int j) =>
            j >= 0 && j < msgs.length && !msgs[j].isWpEvent && zSameGroup(m.firebaseUid, m.time, msgs[j].firebaseUid, msgs[j].time);
        final bubble = ChatMessageBubble(
          key: ValueKey(m.id),
          groupPos: zGroupPos(olderSame: same(idx - 1), newerSame: same(idx + 1)),
          message: m,
          reactions: ChatReactionChips(channel: 'global', id: m.id),
          mine: m.firebaseUid == s.myUid,
          nameColor: parseChatHex(s.usernameColors[m.firebaseUid]),
          userNumber: s.userNumbers[m.firebaseUid],
          level: s.levels[m.firebaseUid],
          clanTag: s.clanTags[m.firebaseUid],
          isPremium: s.premiumUids.contains(m.firebaseUid),
          avatarUrl: m.firebaseUid == s.myUid
              ? (s.avatarUrls[s.myUid] ?? s.myAvatarUrl ?? m.avatarUrl)
              : (s.avatarUrls[m.firebaseUid] ?? m.avatarUrl),
          onOwnAvatarTap: _openProfileDialog,
          onLongPress: () => _showActions(m, s),
          onReply: () => _controller.setReplyTarget(m),
          onReplyTap: m.replyToId == null ? null : () => _jumpToMessage(s, m.replyToId),
          highlighted: _highlightId == m.id,
          onDelete: (m.firebaseUid == s.myUid || s.canDeleteOthers) && !m.isGift && !m.isGiveaway
              ? () => _confirmDelete(m)
              : null,
          onProfileTap: m.firebaseUid == s.myUid
              ? null
              : () => openPublicProfile(context, m.firebaseUid),
        );
        if (!_live.contains(m.id)) return bubble;
        return ChatEntryAnimation(
          key: ValueKey('entry_${m.id}'),
          animate: !_played.contains(m.id),
          fromRight: m.firebaseUid == s.myUid,
          onPlayed: () => _played.add(m.id),
          child: bubble,
        );
      },
    );
  }

  Widget _buildReplyBar(ChatMessage target) {
    return ZChatReplyBar(
      name: target.username,
      text: stickerPreviewText(target.message),
      onClose: _controller.clearReplyTarget,
    );
  }

  Widget _buildInput(ChatUiState s) {
    final blocked = s.cooldownSeconds > 0 || s.isSending;
    return ZChatComposer(
      children: [
        StickerButton(
          enabled: !blocked && s.myUid.isNotEmpty,
          onPicked: (t) => _controller.send(t),
        ),
        Expanded(
          child: TextField(
            controller: _input,
            maxLines: 4,
            minLines: 1,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
            cursorColor: AppColors.accentViolet,
            decoration: zChatInputDecoration('Tulis pesan...'),
          ),
        ),
        // Giveaway Premium (mahkota)
        ZChatRoundButton(
          tooltip: 'Buat Giveaway',
          color: const Color(0xFFF6BE4F),
          glow: false,
          onPressed: s.myUid.isEmpty ? null : () => showCreateGiveawaySheet(context),
          child: const Icon(Icons.workspace_premium, size: 22, color: Color(0xFF2B1800)),
        ),
        ZChatRoundButton(
          onPressed: blocked ? null : _send,
          child: s.isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textWhite),
                )
              : s.cooldownSeconds > 0
                  ? Text(
                      '${s.cooldownSeconds}',
                      style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                    )
                  : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
        ),
      ],
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.onLongPress,
    required this.onReply,
    this.onReplyTap,
    this.highlighted = false,
    this.onDelete,
    this.nameColor,
    this.userNumber,
    this.level,
    this.clanTag,
    this.isPremium = false,
    this.avatarUrl,
    this.onProfileTap,
    this.onOwnAvatarTap,
    this.reactions,
    this.groupPos = ZGroupPos.single,
  });

  final ChatMessage message;

  /// Posisi dalam rombongan pesan beruntun (avatar & kepala hanya di awal).
  final ZGroupPos groupPos;

  /// Chip reaksi emoji di bawah isi pesan (null = tidak ada).
  final Widget? reactions;

  /// Tap avatar / nama = buka profil user (Tambah Teman). null untuk pesan sendiri.
  final VoidCallback? onProfileTap;

  /// Tap avatar sendiri (kanan bubble) = buka dialog profil/ganti foto, seperti Zenime.
  final VoidCallback? onOwnAvatarTap;
  final bool mine;
  final VoidCallback onLongPress;
  final VoidCallback onReply;

  /// Tap kutipan reply = lompat ke pesan aslinya.
  final VoidCallback? onReplyTap;

  /// Disorot sebentar setelah dilompati dari kutipan reply.
  final bool highlighted;

  /// null = tombol Hapus tidak ditampilkan (bukan pesan sendiri dan bukan admin/developer).
  final VoidCallback? onDelete;
  final Color? nameColor;
  final int? userNumber;
  final int? level;
  final String? clanTag;
  final bool isPremium;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final hasReply = (m.replyToUsername ?? '').isNotEmpty;
    // Kartu (stiker / hadiah / giveaway / undangan catur) tampil tanpa gelembung.
    final sticker = stickerCodeOf(m.message);
    final chess = chessInviteCode(m.message) != null;
    final bare = !hasReply && (m.isGiveaway || m.isGift || chess || sticker != null);
    final textColor = mine ? Colors.white : AppColors.textWhite;

    // Kepala: baris nama (nama > centang > #ID) lalu SATU baris badge
    // (clan > level > Top Giver). Pesanku juga lengkap, dicerminkan ke kanan.
    final header = ZChatHeader(
      mine: mine,
      nameRow: [
        Flexible(
          child: GestureDetector(
            onTap: mine ? onOwnAvatarTap : onProfileTap,
            child: Text(
              m.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: nameColor ?? AppColors.accentVioletLight,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Centang: warna role (developer, admin, moderator) menang atas
        // Premium biru; hilang kalau bukan keduanya.
        UserCheckBadge(firebaseUid: m.firebaseUid, isPremium: isPremium, size: 14),
        if (userNumber != null) ...[
          const SizedBox(width: 4),
          Text('#$userNumber', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ],
      ],
      badges: [
        if (clanTag != null) ClanTagBadge(text: clanTag!),
        if (level != null) UserLevelBadge(uid: m.firebaseUid, level: level!),
        TopGiverBadge(firebaseUid: m.firebaseUid, height: 16),
      ],
    );

    final Widget content;
    if (m.isGiveaway) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.message.trim().isNotEmpty && !m.message.startsWith('🎁 Giveaway Premium'))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(m.message, style: TextStyle(color: textColor, fontSize: 14, height: 1.35)),
            ),
          GiveawayCard(giveawayId: m.giveawayId!, days: m.giftDays ?? 1),
        ],
      );
    } else if (m.isGift) {
      content = GiftBubbleCard(
        days: m.giftDays!,
        title: 'memberi Premium ke ${m.giftRecipientUsername ?? 'pengguna'}',
      );
    } else if (chess) {
      content = ChessInviteCard(message: m.message, mine: mine);
    } else if (sticker != null) {
      content = StickerView(code: sticker);
    } else {
      content = MentionText(
        m.message,
        style: TextStyle(color: textColor, fontSize: 14, height: 1.35),
      );
    }

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: ZChatBubble(
        mine: mine,
        bare: bare,
        highlighted: highlighted,
        pos: groupPos,
        time: _timeLabel(m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasReply)
              ZChatQuote(
                author: m.replyToUsername!,
                text: stickerPreviewText(m.replyToMessage ?? ''),
                mine: mine,
                onTap: onReplyTap,
              ),
            content,
            if (m.isVoice)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Pesan suara (belum bisa diputar di versi ini)',
                  style: TextStyle(color: mine ? const Color(0xB3FFFFFF) : AppColors.textMuted, fontSize: 10.5),
                ),
              ),
          ],
        ),
      ),
    );

    final avatar = GestureDetector(
      onTap: mine ? onOwnAvatarTap : onProfileTap,
      child: FramedAvatar(
        uid: m.firebaseUid,
        size: 36,
        child: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.surfaceVariantDark,
          backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
              ? ResizeImage.resizeIfNeeded(
                  LiteMode.px(context, 36), null, CachedNetworkImageProvider(avatarUrl!, cacheManager: AppImageCache.images))
              : null,
          child: (avatarUrl == null || avatarUrl!.isEmpty)
              ? Text(
                  m.username.isEmpty ? '?' : m.username.characters.first.toUpperCase(),
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w700),
                )
              : null,
        ),
      ),
    );

    return SwipeToReply(
      onReply: onReply,
      // Balas & Hapus lewat tahan pesan (menu) atau geser untuk balas.
      child: ZChatRow(
        mine: mine,
        pos: groupPos,
        avatar: avatar,
        header: header,
        bubble: bubble,
        below: reactions,
      ),
    );
  }
}

/// Animasi pesan baru masuk: geser dari samping (kanan untuk pesan sendiri,
/// kiri untuk pesan orang lain) + muncul perlahan + tinggi membuka dari
/// bawah, jadi pesan lama naik dengan halus, tidak melompat.
class ChatEntryAnimation extends StatefulWidget {
  const ChatEntryAnimation({
    super.key,
    required this.child,
    required this.animate,
    required this.fromRight,
    required this.onPlayed,
  });

  final Widget child;
  final bool animate;
  final bool fromRight;
  final VoidCallback onPlayed;

  @override
  State<ChatEntryAnimation> createState() => _ChatEntryAnimationState();
}

class _ChatEntryAnimationState extends State<ChatEntryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: widget.animate ? 0 : 1,
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    if (widget.animate) {
      widget.onPlayed();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: Offset(widget.fromRight ? 0.22 : -0.22, 0.0),
      end: Offset.zero,
    ).animate(_curve);
    return SizeTransition(
      sizeFactor: _curve,
      axisAlignment: 1.0,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(position: slide, child: widget.child),
      ),
    );
  }
}

/// Palet warna preset buat warna username sendiri (sama dengan Zenime).
const List<String> _usernameColorPresets = [
  '#E4344A', // merah default Zenime
  '#3897F0', // biru
  '#22C55E', // hijau
  '#F59E0B', // oranye
  '#A855F7', // ungu
  '#EC4899', // pink
  '#14B8A6', // teal
  '#EAB308', // kuning
  '#6366F1', // indigo
  '#FFFFFF', // putih
  '#FCA5A5', // merah muda
  '#93C5FD', // biru muda
  '#86EFAC', // hijau muda
  '#FCD34D', // kuning muda
  '#D8B4FE', // ungu muda
  '#F9A8D4', // pink muda
  '#5EEAD4', // teal muda
  '#FDBA74', // oranye muda
];

/// Dialog Edit Profil Chat (port EditProfileDialog di ChatScreen.kt): foto
/// profil, username, dan warna username. Semua user boleh, tidak perlu
/// Premium. Menyimpan ke `chat_profiles`, yang sama dengan Zenime. Banner dan
/// toggle privasi dibawa apa adanya karena upsert menimpa semua kolom.
class _ChatProfileDialog extends ConsumerStatefulWidget {
  const _ChatProfileDialog({
    required this.uid,
    required this.username,
    required this.avatarUrl,
    required this.usernameColor,
  });

  final String uid;
  final String username;
  final String? avatarUrl;
  final String? usernameColor;

  @override
  ConsumerState<_ChatProfileDialog> createState() => _ChatProfileDialogState();
}

class _ChatProfileDialogState extends ConsumerState<_ChatProfileDialog> {
  static const int _maxUsername = 24;

  final _picker = ImagePicker();
  late final TextEditingController _nameCtrl;

  // Nilai yang SUDAH tersimpan di server (dipakai saat upload foto, supaya
  // ketikan username yang belum disimpan tidak ikut tersimpan).
  late String _savedName;
  late String? _savedColor;
  String? _avatarUrl;

  // Pilihan warna di dialog (belum tentu tersimpan).
  String? _color;

  ChatProfile? _profile;
  bool _loaded = false;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _savedName = widget.username;
    _savedColor = widget.usernameColor;
    _color = widget.usernameColor;
    _avatarUrl = widget.avatarUrl;
    _nameCtrl = TextEditingController(text: widget.username);
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Ambil profil lengkap dulu (banner + toggle privasi) supaya upsert tidak
  /// menimpanya dengan nilai default.
  Future<void> _loadProfile() async {
    try {
      final p = await ref.read(chatRepositoryProvider).getProfile(widget.uid);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e, 'Gagal memuat profil. Tutup lalu buka lagi.'));
    }
  }

  Future<void> _persist({required String username, String? avatar, String? color}) async {
    await ref.read(chatRepositoryProvider).saveProfile(
          firebaseUid: widget.uid,
          username: username,
          avatarUrl: avatar,
          bannerUrl: _profile?.bannerUrl,
          usernameColor: color,
          favoritesPublic: _profile?.favoritesPublic ?? false,
          historyPublic: _profile?.historyPublic ?? false,
        );
    ref.read(chatControllerProvider.notifier).applyMyProfile(
          username: username,
          avatarUrl: avatar,
          usernameColor: color,
        );
    ref.invalidate(chatProfileProvider(widget.uid));
  }

  Future<void> _pickAvatar() async {
    if (!_loaded || _uploading || _saving) return;
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 82,
    );
    if (x == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await ProfileImageUploader.uploadAvatar(x.path, widget.uid);
      await _persist(username: _savedName, avatar: url, color: _savedColor);
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = errorMessage(e, 'Gagal upload foto profil');
      });
    }
  }

  Future<void> _save() async {
    final trimmed = _nameCtrl.text.trim();
    final name = trimmed.length > _maxUsername ? trimmed.substring(0, _maxUsername) : trimmed;
    if (name.isEmpty) {
      setState(() => _error = 'Username gak boleh kosong');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _persist(username: name, avatar: _avatarUrl, color: _color);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessage(e, 'Gagal menyimpan username');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = _avatarUrl != null && _avatarUrl!.isNotEmpty;
    return Dialog(
      backgroundColor: AppColors.surfaceDark,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x14FFFFFF)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Edit Profil Chat',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipOval(
                          child: ColoredBox(
                            color: AppColors.backgroundDark,
                            child: hasAvatar
                                ? CachedNetworkImage(
                                    cacheManager: AppImageCache.images,
                                    imageUrl: _avatarUrl!,
                                    memCacheWidth: LiteMode.px(context, 84),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => GeneratedAvatar(
                                      seed: widget.uid,
                                      label: _savedName,
                                      size: 84,
                                    ),
                                  )
                                : GeneratedAvatar(
                                    seed: widget.uid,
                                    label: _savedName,
                                    size: 84,
                                  ),
                          ),
                        ),
                      ),
                      if (_uploading)
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Color(0x8C000000),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      else
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: AppColors.accentViolet,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.photo_camera, color: Colors.white, size: 14),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              maxLength: _maxUsername,
              maxLines: 1,
              style: const TextStyle(color: AppColors.textWhite),
              cursorColor: AppColors.accentViolet,
              decoration: InputDecoration(
                labelText: 'Username',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                counterStyle: const TextStyle(color: AppColors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accentViolet),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Warna Username',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final hex in _usernameColorPresets) ...[
                    GestureDetector(
                      onTap: () => setState(() => _color = hex),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: parseChatHex(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == hex ? Colors.white : const Color(0x33FFFFFF),
                            width: _color == hex ? 2 : 1,
                          ),
                        ),
                        child: _color == hex
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: hex == '#FFFFFF' ? Colors.black : Colors.white,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.errorRed, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                    ),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: (_saving || _uploading || !_loaded) ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Simpan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// Badge angka di tab chat (muncul/hilang dengan animasi).
class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: count <= 0
          ? const SizedBox.shrink(key: ValueKey(0))
          : Container(
              key: ValueKey(count > 99 ? 100 : count),
              margin: const EdgeInsets.only(left: 6),
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentViolet,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [BoxShadow(color: AppColors.accentViolet.withValues(alpha: 0.45), blurRadius: 8)],
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1),
              ),
            ),
    );
  }
}
