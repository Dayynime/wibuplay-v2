import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';
import '../../components/friend_avatar.dart';
import 'user_profile_sheet.dart';

/// Layar Teman: permintaan masuk (terima/tolak), daftar teman (tap buat buka
/// profil, tombol X buat hapus), dan permintaan terkirim (batalkan).
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  bool _loading = true;
  String? _error;
  FriendLists _lists = const FriendLists();
  String? _busyId;

  String get _myUid => ref.read(authRepositoryProvider).currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _myUid;
    if (uid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Kamu harus login dulu.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lists = await ref.read(friendRepositoryProvider).getLists(uid);
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorMessage(e, 'Gagal memuat daftar teman');
      });
    }
  }

  Future<void> _act(FriendDisplay item, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() => _busyId = item.friendshipId);
    String? err;
    try {
      await action();
    } catch (e) {
      err = errorMessage(e, 'Aksi gagal, coba lagi');
    }
    FriendLists? lists;
    try {
      lists = await ref.read(friendRepositoryProvider).getLists(_myUid);
    } catch (_) {}
    ref.invalidate(incomingFriendRequestsProvider);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (lists != null) _lists = lists;
    });
    if (err != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(friendRepositoryProvider);
    final empty = _lists.friends.isEmpty && _lists.incoming.isEmpty && _lists.outgoing.isEmpty;
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Teman', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Coba lagi', style: TextStyle(color: AppColors.accentViolet)),
                        ),
                      ],
                    ),
                  ),
                )
              : empty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Belum Ada Teman',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Buka profil user lain dari Chat Global, lalu tap Tambah Teman.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.accentViolet,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          if (_lists.incoming.isNotEmpty) ...[
                            _SectionLabel('Permintaan Masuk (${_lists.incoming.length})'),
                            for (final item in _lists.incoming)
                              _FriendRow(
                                key: ValueKey('in_${item.friendshipId}'),
                                item: item,
                                actions: [
                                  IconButton(
                                    tooltip: 'Tolak',
                                    onPressed: _busyId == item.friendshipId
                                        ? null
                                        : () => _act(item, () => repo.remove(item.friendshipId)),
                                    icon: const Icon(Icons.close, color: Color(0xFFE53935)),
                                  ),
                                  IconButton(
                                    tooltip: 'Terima',
                                    onPressed: _busyId == item.friendshipId
                                        ? null
                                        : () => _act(item, () => repo.accept(item.friendshipId)),
                                    icon: const Icon(Icons.check, color: AppColors.accentViolet),
                                  ),
                                ],
                              ),
                          ],
                          if (_lists.friends.isNotEmpty) ...[
                            _SectionLabel('Teman (${_lists.friends.length})'),
                            for (final item in _lists.friends)
                              _FriendRow(
                                key: ValueKey('fr_${item.friendshipId}'),
                                item: item,
                                actions: [
                                  IconButton(
                                    tooltip: 'Hapus teman',
                                    onPressed: _busyId == item.friendshipId
                                        ? null
                                        : () => _confirmRemove(item),
                                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                          ],
                          if (_lists.outgoing.isNotEmpty) ...[
                            _SectionLabel('Permintaan Terkirim (${_lists.outgoing.length})'),
                            for (final item in _lists.outgoing)
                              _FriendRow(
                                key: ValueKey('out_${item.friendshipId}'),
                                item: item,
                                actions: [
                                  TextButton(
                                    onPressed: _busyId == item.friendshipId
                                        ? null
                                        : () => _act(item, () => repo.remove(item.friendshipId)),
                                    child: const Text(
                                      'Batalkan',
                                      style: TextStyle(color: AppColors.accentViolet),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Future<void> _confirmRemove(FriendDisplay item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Hapus ${item.username}?', style: const TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Kalian nggak bisa saling chat private lagi sampai berteman lagi.',
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
    if (ok == true) {
      await _act(item, () => ref.read(friendRepositoryProvider).remove(item.friendshipId));
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({super.key, required this.item, required this.actions});

  final FriendDisplay item;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showUserProfileSheet(context, item.firebaseUid),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FriendAvatar(
                  url: item.avatarUrl,
                  seed: item.firebaseUid,
                  label: item.username,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
