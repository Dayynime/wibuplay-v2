import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/friend_models.dart';
import '../../../data/models/nobar_models.dart';
import '../../../data/repository/nobar_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../../components/friend_search_field.dart';
import '../../components/net_image.dart';
import 'nobar_screen.dart';

// ============================================================================
// Lembar undang teman (dari layar room)
// ============================================================================

/// Undang teman ke [room]. Teman dapat notif + push "X ngajak kamu nobar".
/// [onShareCode] = bagikan kode lewat aplikasi lain.
Future<void> showNobarInviteSheet(BuildContext context, NobarRoom room, {required VoidCallback onShareCode}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _InviteSheet(room: room, onShareCode: onShareCode),
  );
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.room, required this.onShareCode});

  final NobarRoom room;
  final VoidCallback onShareCode;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  List<FriendDisplay>? _friends;
  String? _error;
  String? _sending;
  String _query = '';
  final Set<String> _sent = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _error = 'Kamu harus login dulu');
      return;
    }
    try {
      final lists = await ref.read(friendRepositoryProvider).getLists(uid);
      if (mounted) setState(() => _friends = lists.friends);
    } catch (_) {
      if (mounted) setState(() => _error = 'Daftar teman gagal dimuat');
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _invite(FriendDisplay f) async {
    if (_sending != null) return;
    setState(() => _sending = f.firebaseUid);
    try {
      await ref.read(nobarRepositoryProvider).invite(widget.room.id, f.firebaseUid);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _sent.add(f.firebaseUid));
    } on NobarException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final inRoom = widget.room.members.map((m) => m.uid).toSet();
    final full = widget.room.members.length >= widget.room.maxMembers;
    final all = _friends;
    final friends = all == null ? null : filterFriends(all, _query);

    Widget list;
    if (_error != null) {
      list = Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
      );
    } else if (friends == null) {
      list = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
      );
    } else if (friends.isEmpty && all!.isNotEmpty) {
      list = const FriendSearchEmpty();
    } else if (friends.isEmpty) {
      list = const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Kamu belum punya teman di Zenime. Bagikan kodenya saja.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    } else {
      list = ListView.builder(
        shrinkWrap: true,
        itemCount: friends.length,
        itemBuilder: (_, i) {
          final f = friends[i];
          final here = inRoom.contains(f.firebaseUid);
          final sent = _sent.contains(f.firebaseUid);
          final sending = _sending == f.firebaseUid;
          Widget trailing;
          if (here) {
            trailing = const Text('Di room', style: TextStyle(color: AppColors.textMuted, fontSize: 12));
          } else if (sending) {
            trailing = const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
          } else if (sent) {
            trailing = const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.successGreen, size: 18),
                SizedBox(width: 4),
                Text('Terkirim', style: TextStyle(color: AppColors.successGreen, fontSize: 12)),
              ],
            );
          } else {
            trailing = FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentViolet,
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
              onPressed: full ? null : () => _invite(f),
              child: const Text('Undang', style: TextStyle(fontWeight: FontWeight.w700)),
            );
          }
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: FriendAvatar(url: f.avatarUrl, seed: f.firebaseUid, label: f.username, size: 40, framed: false),
            title: Text(
              f.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textWhite),
            ),
            trailing: trailing,
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Undang teman nobar',
                style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                full
                    ? 'Room sudah penuh (${widget.room.maxMembers} orang).'
                    : 'Temanmu dapat notifikasi dan tinggal tekan Gabung.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
              if ((all?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 10),
                FriendSearchField(onChanged: (v) => setState(() => _query = v)),
              ],
              const SizedBox(height: 8),
              Flexible(child: list),
              const Divider(color: Colors.white12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const CircleAvatar(
                  backgroundColor: AppColors.surfaceElevated,
                  child: Icon(Icons.ios_share_rounded, color: AppColors.textWhite, size: 20),
                ),
                title: const Text('Bagikan kode room', style: TextStyle(color: AppColors.textWhite)),
                subtitle: Text(
                  'Kode ${widget.room.code}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onShareCode();
                },
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ============================================================================
// Undangan masuk (dari notif / push)
// ============================================================================

/// Dipanggil saat notif `nobar_invite` di-tap: tampilkan pilihan Gabung / Tolak.
Future<void> handleNobarInviteNotification(WidgetRef ref, Map<String, dynamic> data) async {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  final ctx = nav.context;
  void snack(String text) {
    ScaffoldMessenger.maybeOf(ctx)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  if (data['expired'] == true) {
    snack('Undangan nobar ini sudah tidak berlaku');
    return;
  }

  var invite = NobarInvite.fromData(data);
  if (invite == null) {
    // Data push tidak lengkap: ambil undangan yang masih menunggu dari server.
    try {
      final list = await ref.read(nobarRepositoryProvider).myInvites();
      final roomId = data['room_id']?.toString();
      invite = list.where((i) => i.roomId == roomId).firstOrNull ?? list.firstOrNull;
    } catch (_) {}
  }
  if (invite == null) {
    snack('Undangan nobar ini sudah tidak berlaku');
    return;
  }

  final room = await showDialog<NobarRoom>(
    context: ctx,
    builder: (_) => _InviteDialog(invite: invite!),
  );
  if (room != null) {
    await nav.push<void>(fadeRoute(NobarScreen(initial: room)));
  }
}

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.invite});

  final NobarInvite invite;

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  bool? _busy; // true = gabung, false = tolak
  String? _error;

  Future<void> _answer(bool accept) async {
    if (_busy != null) return;
    setState(() {
      _busy = accept;
      _error = null;
    });
    try {
      final room = await ref.read(nobarRepositoryProvider).respondInvite(widget.invite.inviteId, accept: accept);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, room);
      ref.invalidate(unreadNotificationsProvider);
    } on NobarException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invite;
    return Dialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (inv.posterUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 96, height: 136, child: NetImage(inv.posterUrl, fit: BoxFit.cover)),
              )
            else
              const Icon(Icons.groups_rounded, color: AppColors.accentViolet, size: 48),
            const SizedBox(height: 14),
            Text(
              '${inv.fromName} ngajak kamu nobar',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (inv.movieTitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                inv.movieTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'Nonton bareng + voice chat',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.warningAmber, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textWhite,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _busy != null ? null : () => _answer(false),
                    child: _busy == false
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Tolak'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentViolet,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _busy != null ? null : () => _answer(true),
                    child: _busy == true
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Gabung', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
            if (_error != null)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
          ],
        ),
      ),
    );
  }
}
