import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/repository/profile_image_uploader.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/game_badges.dart';
import '../../components/role_badges.dart';
import '../../components/swipe_to_reply.dart';
import '../friends/friends_screen.dart';
import '../friends/user_profile_sheet.dart';
import 'private_chat_controller.dart';
import 'private_chat_pane.dart';
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

  /// 0 = Chat Global, 1 = Chat Teman (tab Teman ala Zenime).
  int _tab = 0;

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

    // Dipantau terus supaya state tab Teman (chat yang sedang dibuka) tidak
    // hilang saat pindah tab. Belum ada request ke server sampai tab dibuka.
    final inConversation =
        ref.watch(privateChatControllerProvider.select((x) => x.selected != null));

    return PopScope(
      // Back saat membuka chat teman = kembali ke daftar chat, bukan keluar.
      canPop: !(_tab == 1 && inConversation),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(privateChatControllerProvider.notifier).closeChat();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundDark,
          elevation: 0,
          title: Text(_tab == 0 ? 'Chat Global' : 'Chat Teman'),
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
            _buildChatTabs(),
            Expanded(
              child: _tab == 0
                  ? Column(
                      children: [
                        Expanded(child: _buildList(s)),
                        if (s.replyTarget != null) _buildReplyBar(s.replyTarget!),
                        _buildInput(s),
                      ],
                    )
                  : PrivateChatPane(
                      myUid: s.myUid,
                      onFriendProfileClick: (uid) => showUserProfileSheet(context, uid),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab Global / Teman di bawah app bar (indikator pendek, gaya Zenime).
  Widget _buildChatTabs() {
    const labels = ['Global', 'Teman'];
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = i),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Column(
                      children: [
                        Text(
                          labels[i],
                          style: TextStyle(
                            color: _tab == i ? AppColors.textWhite : const Color(0x80FFFFFF),
                            fontSize: 14,
                            fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 3,
                          width: _tab == i ? 28 : 0,
                          decoration: BoxDecoration(
                            color: AppColors.accentViolet,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        Container(height: 1, color: const Color(0x14FFFFFF)),
      ],
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
          onProfileTap: m.firebaseUid == s.myUid
              ? null
              : () => showUserProfileSheet(context, m.firebaseUid),
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
    this.onProfileTap,
  });

  final ChatMessage message;

  /// Tap avatar / nama = buka profil user (Tambah Teman). null untuk pesan sendiri.
  final VoidCallback? onProfileTap;
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
                  child: GestureDetector(
                    onTap: onProfileTap,
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
      child: SwipeToReply(
        onReply: onReply,
        child: Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: mine
              ? [bubble]
              : [
                  GestureDetector(onTap: onProfileTap, child: avatar),
                  const SizedBox(width: 8),
                  Flexible(child: bubble),
                ],
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
                                    imageUrl: _avatarUrl!,
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
                          color: _parseHex(hex),
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
