import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../components/game_badges.dart';
import '../../components/role_badges.dart';
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

  /// Id pesan yang masuk SETELAH layar selesai memuat (kena animasi masuk).
  final Set<int> _live = {};

  /// Id yang animasinya sudah diputar, supaya tidak mengulang saat item
  /// di-scroll keluar lalu masuk lagi.
  final Set<int> _played = {};

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
        final bubble = _MessageBubble(
          key: ValueKey(m.id),
          message: m,
          mine: m.firebaseUid == s.myUid,
          nameColor: _parseHex(s.usernameColors[m.firebaseUid]),
          userNumber: s.userNumbers[m.firebaseUid],
          level: s.levels[m.firebaseUid],
          clanTag: s.clanTags[m.firebaseUid],
          isPremium: s.premiumUids.contains(m.firebaseUid),
          avatarUrl: s.avatarUrls[m.firebaseUid] ?? m.avatarUrl,
          onLongPress: () => _showActions(m, s),
          onReply: () => _controller.setReplyTarget(m),
          onDelete: m.firebaseUid == s.myUid ? () => _confirmDelete(m) : null,
        );
        if (!_live.contains(m.id)) return bubble;
        return _EntryAnimation(
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

/// Lebar bubble chat TETAP (270dp seperti Zenime) supaya semua bubble
/// seragam, apa pun panjang pesannya. Di layar sempit dikecilkan supaya
/// tidak meluap (sisakan ruang avatar + margin).
const double _kBubbleMaxWidth = 270;

double _bubbleWidth(BuildContext context) {
  final screen = MediaQuery.sizeOf(context).width;
  // 24 padding list + 32 avatar + 8 jarak + 16 ruang kosong di sisi lain.
  final available = screen - 24 - 32 - 8 - 16;
  return available < _kBubbleMaxWidth ? available : _kBubbleMaxWidth;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.onLongPress,
    required this.onReply,
    this.onDelete,
    this.nameColor,
    this.userNumber,
    this.level,
    this.clanTag,
    this.isPremium = false,
    this.avatarUrl,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback onLongPress;
  final VoidCallback onReply;

  /// null = pesan orang lain (tombol Hapus tidak ditampilkan).
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
    // Warna bubble sendiri sama dengan bubble orang lain (seperti Zenime);
    // bedanya cuma posisi (kanan) dan tidak ada avatar.
    const bubbleColor = AppColors.surfaceCard;

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        width: _bubbleWidth(context),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bubbleColor, borderRadius: AppShapes.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Baris 1: username > centang Premium > #ID (urutan sama dengan Zenime).
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
                // Centang: warna role (developer merah, admin hijau, moderator
                // ungu) menang atas Premium biru; hilang kalau bukan keduanya.
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: UserCheckBadge(
                    firebaseUid: m.firebaseUid,
                    isPremium: isPremium,
                    size: 15,
                  ),
                ),
                if (userNumber != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '#$userNumber',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                ],
              ],
            ),
            // Baris 2: badge clan + level, di bawah username.
            if (clanTag != null || level != null) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (clanTag != null) ClanRainbowBadge(text: clanTag!),
                  if (clanTag != null && level != null) const SizedBox(width: 4),
                  if (level != null) LevelBadge(level: level!),
                ],
              ),
            ],
            if (hasReply) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
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
                  'Pesan suara (belum bisa diputar di versi ini)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _timeLabel(m),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
                const SizedBox(width: 10),
                _FooterAction(label: 'Balas', onTap: onReply),
                if (onDelete != null) ...[
                  const SizedBox(width: 10),
                  _FooterAction(label: 'Hapus', onTap: onDelete!),
                ],
              ],
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
      child: _SwipeToReply(
        onReply: onReply,
        child: Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: mine
              ? [bubble]
              : [avatar, const SizedBox(width: 8), Flexible(child: bubble)],
        ),
      ),
    );
  }
}

/// Teks aksi kecil di footer bubble ("Balas" / "Hapus"), sama seperti Zenime.
class _FooterAction extends StatelessWidget {
  const _FooterAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
      ),
    );
  }
}

/// Geser ke kanan untuk membalas: bubble ikut bergeser, ikon + tulisan
/// "Reply" muncul di kiri, lepas jari setelah melewati batas = reply terpicu.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});

  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const double _trigger = 64;
  static const double _max = 96;

  double _dx = 0;
  bool _dragging = false;
  bool _buzzed = false;

  void _onUpdate(DragUpdateDetails d) {
    final next = (_dx + d.delta.dx).clamp(0.0, _max);
    if (!_buzzed && next >= _trigger) {
      _buzzed = true;
      HapticFeedback.selectionClick();
    }
    if (next < _trigger) _buzzed = false;
    setState(() => _dx = next);
  }

  void _onEnd([DragEndDetails? _]) {
    final fire = _dx >= _trigger;
    setState(() {
      _dragging = false;
      _dx = 0;
      _buzzed = false;
    });
    if (fire) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onEnd,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: progress,
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.reply, size: 18, color: AppColors.accentVioletLight),
                  SizedBox(width: 4),
                  Text(
                    'Reply',
                    style: TextStyle(color: AppColors.accentVioletLight, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Animasi pesan baru masuk: geser dari samping (kanan untuk pesan sendiri,
/// kiri untuk pesan orang lain) + muncul perlahan + tinggi membuka dari
/// bawah, jadi pesan lama naik dengan halus, tidak melompat.
class _EntryAnimation extends StatefulWidget {
  const _EntryAnimation({
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
  State<_EntryAnimation> createState() => _EntryAnimationState();
}

class _EntryAnimationState extends State<_EntryAnimation>
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
