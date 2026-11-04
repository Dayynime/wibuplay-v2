import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/chess_models.dart';
import '../../../data/models/friend_models.dart';
import '../../../data/repository/chess_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../../components/friend_search_field.dart';
import 'chess_game_screen.dart';

// Undangan catur dikirim sebagai pesan teks biasa di chat (global, clan,
// pribadi), jadi server chat tidak perlu diubah. App mengenali baris
// "Kode room catur: XXXXXX" lalu menampilkan kartu dengan tombol Gabung.
// App versi lama tetap melihat teksnya (berisi kode) seperti pesan biasa.

final RegExp _inviteRe = RegExp(r'Kode room catur:\s*([A-Za-z0-9]{6})\b');

/// Kode room kalau [message] adalah undangan catur, selain itu null.
String? chessInviteCode(String message) {
  final m = _inviteRe.firstMatch(message);
  return m?.group(1)?.toUpperCase();
}

String _timeLabel(ChessGame g) {
  final m = g.baseMs ~/ 60000;
  final i = g.incMs ~/ 1000;
  return i > 0 ? '$m + $i' : '$m menit';
}

String chessInviteText(ChessGame g) =>
    '♟️ Ayo main catur sama aku! (${_timeLabel(g)})\nKode room catur: ${g.code}';

// ============================================================================
// Kartu undangan di bubble chat
// ============================================================================

/// Kartu undangan catur di dalam bubble chat. [mine] = pesan milik sendiri.
class ChessInviteCard extends ConsumerStatefulWidget {
  const ChessInviteCard({super.key, required this.message, required this.mine});

  final String message;
  final bool mine;

  @override
  ConsumerState<ChessInviteCard> createState() => _ChessInviteCardState();
}

class _ChessInviteCardState extends ConsumerState<ChessInviteCard> {
  bool _busy = false;

  Future<void> _join(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final g = await ref.read(chessRepositoryProvider).join(code);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await nav.push<void>(fadeRoute(ChessGameScreen(gameId: g.id, initial: g)));
    } on ChessException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = chessInviteCode(widget.message) ?? '';
    final firstLine = widget.message.split('\n').first.trim();
    final time = RegExp(r'\(([^)]+)\)').firstMatch(firstLine)?.group(1);

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minWidth: 210),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E2638), Color(0xFF141B2B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentViolet.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('♞', style: TextStyle(fontSize: 22, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tantangan Catur',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    Text(
                      [if (time != null) time, 'Room $code'].join(' · '),
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
            child: widget.mine
                ? const Text(
                    'Menunggu lawan bergabung…',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentViolet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _busy || code.isEmpty ? null : () => _join(code),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sports_esports_rounded, size: 18),
                    label: const Text('Gabung', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Lembar bagikan room
// ============================================================================

/// Bagikan room catur [g] (yang punya kode) ke Chat Global, Clan, Teman,
/// atau aplikasi lain.
Future<void> showChessShareSheet(BuildContext context, ChessGame g) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ShareSheet(game: g),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.game});

  final ChessGame game;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  String? _sending; // id tujuan yang sedang dikirim
  final Set<String> _sent = <String>{};
  List<FriendDisplay>? _friends;
  bool _showFriends = false;
  String _query = '';
  String? _friendError;

  String get _text => chessInviteText(widget.game);
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
                'Bagikan room catur',
                style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Temanmu tinggal tekan Gabung di chat, tanpa ketik kode.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (!_showFriends) ...[
                _option(Icons.public_rounded, 'Chat Global', 'global', _sendGlobal),
                if (clan != null) _option(Icons.shield_rounded, 'Chat Clan', 'clan', _sendClan),
                _option(Icons.people_alt_rounded, 'Teman', null, _loadFriends, chevron: true),
                _option(Icons.ios_share_rounded, 'Aplikasi lain', null, () async {
                  await Share.share('$_text\n\nBuka Zenime → Zenime Games → Catur → Masuk pakai kode.');
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
