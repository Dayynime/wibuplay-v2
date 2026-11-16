import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../../components/friend_search_field.dart';
import 'ludo_webview_screen.dart';

// Undangan Ludo dikirim sebagai pesan teks biasa di chat (global, clan,
// pribadi), sama seperti catur, jadi server chat tidak perlu diubah. App
// mengenali baris "Kode room ludo: XXXXXX" lalu menampilkan kartu dengan
// tombol Gabung. App versi lama tetap melihat teksnya seperti pesan biasa.

final RegExp _inviteRe = RegExp(r'Kode room ludo:\s*([A-Z2-9]{6})\b', caseSensitive: false);
final RegExp _playersRe = RegExp(r'\((\d) pemain\)');

/// Kode room kalau [message] adalah undangan Ludo, selain itu null.
String? ludoInviteCode(String message) => _inviteRe.firstMatch(message)?.group(1)?.toUpperCase();

String ludoInviteText(String code, int? players) =>
    '🎲 Ayo main Ludo bareng aku!${players != null ? ' ($players pemain)' : ''}\nKode room ludo: $code';

const List<Color> _ludoColors = [Color(0xFFFF6B81), Color(0xFF2FD59A), Color(0xFFFFC53D), Color(0xFF4D9DFF)];

// ============================================================================
// Kartu undangan di bubble chat
// ============================================================================

/// Kartu undangan Ludo di dalam bubble chat. [mine] = pesan milik sendiri.
class LudoInviteCard extends StatelessWidget {
  const LudoInviteCard({super.key, required this.message, required this.mine});

  final String message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final code = ludoInviteCode(message) ?? '';
    final players = _playersRe.firstMatch(message)?.group(1);

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minWidth: 220),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF173A63), Color(0xFF10233F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4D9DFF).withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MiniBoard(),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ajakan Ludo',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    Text(
                      [if (players != null) '$players pemain', 'Room $code'].join(' · '),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: mine ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFFFB52B),
                foregroundColor: mine ? Colors.white : const Color(0xFF3B2A06),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: code.isEmpty
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).push<void>(fadeRoute(LudoWebViewScreen(code: code)));
                    },
              icon: Icon(mine ? Icons.open_in_new_rounded : Icons.sports_esports_rounded, size: 18),
              label: Text(mine ? 'Buka room' : 'Gabung', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ikon papan Ludo mini (4 warna).
class _MiniBoard extends StatelessWidget {
  const _MiniBoard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (final c in [_ludoColors[0], _ludoColors[1], _ludoColors[3], _ludoColors[2]])
            DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
        ],
      ),
    );
  }
}

// ============================================================================
// Lembar undang teman
// ============================================================================

/// Undang ke room Ludo [code] lewat Chat Global, Clan, Teman, atau aplikasi lain.
Future<void> showLudoShareSheet(BuildContext context, String code, int? players) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _LudoShareSheet(code: code, players: players),
  );
}

class _LudoShareSheet extends ConsumerStatefulWidget {
  const _LudoShareSheet({required this.code, required this.players});

  final String code;
  final int? players;

  @override
  ConsumerState<_LudoShareSheet> createState() => _LudoShareSheetState();
}

class _LudoShareSheetState extends ConsumerState<_LudoShareSheet> {
  String? _sending; // id tujuan yang sedang dikirim
  final Set<String> _sent = <String>{};
  List<FriendDisplay>? _friends;
  bool _showFriends = false;
  String _query = '';
  String? _friendError;

  String get _text => ludoInviteText(widget.code, widget.players);
  String? get _uid => ref.read(authUserProvider).valueOrNull?.uid;

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send(String key, String label, Future<void> Function() action) async {
    if (_sending != null || _sent.contains(key)) return;
    setState(() => _sending = key);
    try {
      await action();
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _sent.add(key));
      _snack('Undangan terkirim ke $label');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      _snack(msg.isEmpty || msg.length > 150 ? 'Gagal mengirim undangan' : msg);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  Future<void> _sendGlobal() async {
    final uid = _uid;
    if (uid == null) {
      _snack('Kamu harus login dulu');
      return;
    }
    await _send('global', 'Chat Global', () async {
      await ref.read(chatRepositoryProvider).sendMessage(firebaseUid: uid, username: '', message: _text);
    });
  }

  Future<void> _sendClan() async {
    await _send('clan', 'Chat Clan', () async {
      await ref.read(clanChatRepositoryProvider).send(_text);
    });
  }

  Future<void> _sendFriend(FriendDisplay f) async {
    final uid = _uid;
    if (uid == null) {
      _snack('Kamu harus login dulu');
      return;
    }
    await _send('f:${f.firebaseUid}', f.username, () async {
      await ref.read(privateChatRepositoryProvider).send(myUid: uid, otherUid: f.firebaseUid, text: _text);
    });
  }

  Future<void> _loadFriends() async {
    setState(() => _showFriends = true);
    if (_friends != null) return;
    final uid = _uid;
    if (uid == null) {
      setState(() => _friendError = 'Kamu harus login dulu');
      return;
    }
    try {
      final lists = await ref.read(friendRepositoryProvider).getLists(uid);
      if (mounted) setState(() => _friends = lists.friends);
    } catch (_) {
      if (mounted) setState(() => _friendError = 'Daftar teman gagal dimuat');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clan = ref.watch(myClanMembershipProvider).valueOrNull;
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ajak main Ludo',
                  style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Room ${widget.code} · temanmu tinggal tekan Gabung di chat.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (!_showFriends) ...[
                  _option(Icons.public_rounded, 'Chat Global', 'global', _sendGlobal),
                  if (clan != null) _option(Icons.shield_rounded, 'Chat Clan', 'clan', _sendClan),
                  _option(Icons.people_alt_rounded, 'Teman', null, _loadFriends, chevron: true),
                  _option(Icons.ios_share_rounded, 'Aplikasi lain', null, () async {
                    await Share.share('$_text\n\nBuka Zenime → Zenime Games → Ludo → masukkan kode.');
                  }),
                ] else
                  Flexible(child: _friendList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(IconData icon, String label, String? key, Future<void> Function() onTap, {bool chevron = false}) {
    final sending = key != null && _sending == key;
    final sent = key != null && _sent.contains(key);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceElevated,
        child: Icon(icon, color: AppColors.textWhite, size: 20),
      ),
      title: Text(label, style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w600)),
      trailing: sending
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : sent
              ? const Icon(Icons.check_circle_rounded, color: AppColors.successGreen)
              : chevron
                  ? const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted)
                  : null,
      onTap: sent ? null : onTap,
    );
  }

  Widget _friendList() {
    final all = _friends;
    final friends = all == null ? null : filterFriends(all, _query);
    Widget body;
    if (_friendError != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_friendError!, style: const TextStyle(color: AppColors.textSecondary)),
      );
    } else if (friends == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
      );
    } else if (friends.isEmpty && all!.isNotEmpty) {
      body = const FriendSearchEmpty();
    } else if (friends.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Kamu belum punya teman di Zenime.', style: TextStyle(color: AppColors.textSecondary)),
      );
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        itemCount: friends.length,
        itemBuilder: (_, i) {
          final f = friends[i];
          final key = 'f:${f.firebaseUid}';
          final sending = _sending == key;
          final sent = _sent.contains(key);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: FriendAvatar(url: f.avatarUrl, seed: f.firebaseUid, label: f.username, size: 40, framed: false),
            title: Text(
              f.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textWhite),
            ),
            trailing: sending
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : sent
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.successGreen)
                    : const Text('Kirim', style: TextStyle(color: AppColors.accentViolet, fontWeight: FontWeight.w700)),
            onTap: sent ? null : () => _sendFriend(f),
          );
        },
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _showFriends = false),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Kembali'),
        ),
        if ((all?.isNotEmpty ?? false)) ...[
          FriendSearchField(onChanged: (v) => setState(() => _query = v)),
          const SizedBox(height: 8),
        ],
        Flexible(child: body),
      ],
    );
  }
}
