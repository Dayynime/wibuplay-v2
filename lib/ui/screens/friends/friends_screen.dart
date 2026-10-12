import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';
import '../../components/friend_avatar.dart';
import '../../components/game_badges.dart';
import '../../components/shimmer.dart';
import '../profile/public_profile_screen.dart';

/// Layar Teman: permintaan masuk (terima/tolak), daftar teman (tap buka
/// profil, menu ⋮ buat salin ID / hapus), dan permintaan terkirim (batalkan).
/// Tiap baris menampilkan badge level + ID #user_number.
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
  final TextEditingController _search = TextEditingController();
  String _query = '';

  String get _myUid => ref.read(authRepositoryProvider).currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      _loading = _lists.friends.isEmpty && _lists.incoming.isEmpty && _lists.outgoing.isEmpty;
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
    if (err != null) _toast(err);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  bool _match(FriendDisplay f) {
    final q = _query.trim().toLowerCase().replaceFirst('#', '');
    if (q.isEmpty) return true;
    return f.username.toLowerCase().contains(q) || (f.userNumber?.toString().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final friends = _lists.friends;
    final pending = _lists.incoming.length;
    final subtitle = _loading
        ? 'Memuat…'
        : pending > 0
            ? '${friends.length} teman · $pending permintaan baru'
            : '${friends.length} teman';

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Teman', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const _SkeletonList();
    if (_error != null) {
      return _CenterMessage(
        icon: Icons.wifi_off_rounded,
        title: 'Gagal memuat',
        message: _error!,
        action: FilledButton(
          onPressed: _load,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentViolet,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Coba lagi'),
        ),
      );
    }
    final empty = _lists.friends.isEmpty && _lists.incoming.isEmpty && _lists.outgoing.isEmpty;
    if (empty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accentViolet,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            _CenterMessage(
              icon: Icons.group_outlined,
              title: 'Belum Ada Teman',
              message: 'Buka profil user lain dari Chat Global, lalu tap Tambah Teman.',
            ),
          ],
        ),
      );
    }

    final repo = ref.read(friendRepositoryProvider);
    final friends = _lists.friends.where(_match).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accentViolet,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_lists.friends.length > 5) ...[
            _SearchField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              onClear: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
            const SizedBox(height: 8),
          ],

          // ── Permintaan masuk ──
          if (_lists.incoming.isNotEmpty) ...[
            _SectionHeader(title: 'Permintaan Masuk', count: _lists.incoming.length, highlight: true),
            _Group(
              children: [
                for (final item in _lists.incoming)
                  _FriendTile(
                    key: ValueKey('in_${item.friendshipId}'),
                    item: item,
                    busy: _busyId == item.friendshipId,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RoundAction(
                          tooltip: 'Tolak',
                          icon: Icons.close_rounded,
                          color: AppColors.textSecondary,
                          background: AppColors.surfaceElevated,
                          onTap: _busyId != null
                              ? null
                              : () => _act(item, () => repo.remove(item.friendshipId)),
                        ),
                        const SizedBox(width: 8),
                        _RoundAction(
                          tooltip: 'Terima',
                          icon: Icons.check_rounded,
                          color: Colors.white,
                          background: AppColors.accentViolet,
                          onTap: _busyId != null
                              ? null
                              : () => _act(item, () => repo.accept(item.friendshipId)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],

          // ── Daftar teman ──
          if (_lists.friends.isNotEmpty) ...[
            _SectionHeader(title: 'Semua Teman', count: _lists.friends.length),
            if (friends.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'Tidak ada teman yang cocok.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              )
            else
              _Group(
                children: [
                  for (final item in friends)
                    _FriendTile(
                      key: ValueKey('fr_${item.friendshipId}'),
                      item: item,
                      busy: _busyId == item.friendshipId,
                      onTap: () => openPublicProfile(context, item.firebaseUid),
                      trailing: _FriendMenu(
                        enabled: _busyId == null,
                        onProfile: () => openPublicProfile(context, item.firebaseUid),
                        onCopyId: item.userNumber == null
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: '${item.userNumber}'));
                                _toast('ID #${item.userNumber} disalin');
                              },
                        onRemove: () => _confirmRemove(item),
                      ),
                    ),
                ],
              ),
          ],

          // ── Permintaan terkirim ──
          if (_lists.outgoing.isNotEmpty) ...[
            _SectionHeader(title: 'Permintaan Terkirim', count: _lists.outgoing.length),
            _Group(
              children: [
                for (final item in _lists.outgoing)
                  _FriendTile(
                    key: ValueKey('out_${item.friendshipId}'),
                    item: item,
                    busy: _busyId == item.friendshipId,
                    onTap: () => openPublicProfile(context, item.firebaseUid),
                    trailing: OutlinedButton(
                      onPressed: _busyId != null
                          ? null
                          : () => _act(item, () => repo.remove(item.friendshipId)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textWhite,
                        side: const BorderSide(color: AppColors.surfaceElevated),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Batalkan'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(FriendDisplay item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Hapus ${item.username}?',
          style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Kalian nggak bisa saling chat private lagi sampai berteman lagi.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _act(item, () => ref.read(friendRepositoryProvider).remove(item.friendshipId));
    }
  }
}

// ───────────────────────── Komponen ─────────────────────────

Color? _parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged, required this.onClear});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
      cursorColor: AppColors.accentViolet,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceDark,
        hintText: 'Cari nama atau ID',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentVioletSubtle),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, this.highlight = false});

  final String title;
  final int count;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: highlight ? AppColors.accentViolet : AppColors.surfaceVariantDark,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: highlight ? Colors.white : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu grup: semua baris dalam satu container dengan garis pemisah tipis.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 76,
                color: Color(0x0FFFFFFF),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({
    super.key,
    required this.item,
    required this.trailing,
    this.onTap,
    this.busy = false,
  });

  final FriendDisplay item;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final nameColor = _parseHex(item.usernameColor) ?? AppColors.textWhite;
    final hasMeta = item.level != null || item.userNumber != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: busy ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
                  ),
                  child: FriendAvatar(
                    url: item.avatarUrl,
                    seed: item.firebaseUid,
                    label: item.username,
                    size: 44,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      if (hasMeta) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            if (item.level != null) LevelBadge(level: item.level!, height: 16),
                            if (item.level != null && item.userNumber != null)
                              const SizedBox(width: 6),
                            if (item.userNumber != null) _IdChip(number: item.userNumber!),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentViolet,
                      ),
                    ),
                  )
                else
                  trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdChip extends StatelessWidget {
  const _IdChip({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantDark,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'ID #$number',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          height: 1.1,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 36, height: 36, child: Icon(icon, color: color, size: 20)),
        ),
      ),
    );
  }
}

enum _MenuAction { profile, copyId, remove }

class _FriendMenu extends StatelessWidget {
  const _FriendMenu({
    required this.enabled,
    required this.onProfile,
    required this.onCopyId,
    required this.onRemove,
  });

  final bool enabled;
  final VoidCallback onProfile;
  final VoidCallback? onCopyId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<_MenuAction> item(_MenuAction v, IconData icon, String label, {Color? color}) {
      final c = color ?? AppColors.textWhite;
      return PopupMenuItem(
        value: v,
        height: 44,
        child: Row(
          children: [
            Icon(icon, size: 19, color: c),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return PopupMenuButton<_MenuAction>(
      enabled: enabled,
      tooltip: 'Opsi',
      color: AppColors.surfaceVariantDark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
      onSelected: (a) {
        switch (a) {
          case _MenuAction.profile:
            onProfile();
          case _MenuAction.copyId:
            onCopyId?.call();
          case _MenuAction.remove:
            onRemove();
        }
      },
      itemBuilder: (_) => [
        item(_MenuAction.profile, Icons.person_outline_rounded, 'Lihat Profil'),
        if (onCopyId != null) item(_MenuAction.copyId, Icons.copy_rounded, 'Salin ID'),
        const PopupMenuDivider(height: 8),
        item(_MenuAction.remove, Icons.person_remove_outlined, 'Hapus Teman', color: AppColors.errorRed),
      ],
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.accentVioletSubtle,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.accentViolet, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      children: [
        const ShimmerBox(width: 110, height: 12, borderRadius: BorderRadius.all(Radius.circular(6))),
        const SizedBox(height: 12),
        _Group(
          children: [
            for (var i = 0; i < 8; i++)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    ShimmerBox(width: 46, height: 46, borderRadius: BorderRadius.all(Radius.circular(23))),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerBox(width: 140, height: 13, borderRadius: BorderRadius.all(Radius.circular(6))),
                          SizedBox(height: 8),
                          ShimmerBox(width: 90, height: 11, borderRadius: BorderRadius.all(Radius.circular(6))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
