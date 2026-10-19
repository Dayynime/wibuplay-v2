import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';
import '../../components/friend_avatar.dart';
import '../../components/game_badges.dart';
import '../../components/shimmer.dart';
import '../profile/public_profile_screen.dart';
import '../../glass/glass.dart';

/// Layar Cari Teman: menampilkan semua user, bisa dicari lewat username atau
/// ID (angka di "ID #123"), dan langsung bisa Tambah / Batalkan / Terima.
/// Tap baris = buka profil publik.
class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  static const int _pageSize = 30;

  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  int _token = 0; // hasil request lama (sebelum query berubah) dibuang

  List<FriendSearchItem> _items = const [];
  int _nextOffset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  String _query = '';
  final Set<String> _busy = <String>{};

  String get _myUid => ref.read(authRepositoryProvider).currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) _loadMore();
  }

  void _onChanged(String value) {
    setState(() {}); // refresh ikon hapus di kolom cari
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _applyQuery(value));
  }

  void _applyQuery(String value) {
    final q = value.trim();
    if (q == _query) return;
    _query = q;
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final uid = _myUid;
    final token = ++_token;
    if (uid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Kamu harus login dulu.';
      });
      return;
    }
    setState(() {
      if (!silent) _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final page = await ref
          .read(friendRepositoryProvider)
          .searchUsers(uid, _query, limit: _pageSize);
      if (!mounted || token != _token) return;
      setState(() {
        _items = page.items;
        _hasMore = page.hasMore;
        _nextOffset = page.nextOffset;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = errorMessage(e, 'Gagal memuat daftar user');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final uid = _myUid;
    if (uid.isEmpty) return;
    final token = _token;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(friendRepositoryProvider)
          .searchUsers(uid, _query, offset: _nextOffset, limit: _pageSize);
      if (!mounted || token != _token) return;
      final seen = _items.map((e) => e.firebaseUid).toSet();
      setState(() {
        _items = [..._items, ...page.items.where((e) => !seen.contains(e.firebaseUid))];
        _hasMore = page.hasMore;
        _nextOffset = page.nextOffset;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() => _loadingMore = false);
      _toast(errorMessage(e, 'Gagal memuat lebih banyak'));
    }
  }

  Future<void> _refreshRelation(String uid) async {
    try {
      final r = await ref.read(friendRepositoryProvider).getRelation(_myUid, uid);
      if (!mounted) return;
      setState(() {
        _items = [for (final e in _items) e.firebaseUid == uid ? e.withRelation(r) : e];
      });
    } catch (_) {
      // Tombol tetap di status lama; refresh manual bisa memperbaikinya.
    }
  }

  Future<void> _run(FriendSearchItem item, Future<void> Function() action, String fallback) async {
    if (_busy.contains(item.firebaseUid)) return;
    setState(() => _busy.add(item.firebaseUid));
    String? err;
    try {
      await action();
    } catch (e) {
      err = errorMessage(e, fallback);
    }
    await _refreshRelation(item.firebaseUid);
    if (!mounted) return;
    ref.invalidate(incomingFriendRequestsProvider);
    setState(() => _busy.remove(item.firebaseUid));
    if (err != null) _toast(err);
  }

  Future<void> _openProfile(FriendSearchItem item) async {
    await openPublicProfile(context, item.firebaseUid);
    if (!mounted) return;
    await _refreshRelation(item.firebaseUid);
    if (!mounted) return;
    ref.invalidate(incomingFriendRequestsProvider);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: const Text('Cari Teman', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _SearchField(
              controller: _search,
              onChanged: _onChanged,
              onSubmitted: (v) {
                _debounce?.cancel();
                _applyQuery(v);
              },
              onClear: () {
                _debounce?.cancel();
                _search.clear();
                setState(() {});
                _applyQuery('');
              },
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
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
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(silent: true),
        color: AppColors.accentViolet,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            _CenterMessage(
              icon: Icons.person_search_rounded,
              title: 'User Tidak Ditemukan',
              message: _query.isEmpty
                  ? 'Belum ada user lain yang bisa ditambahkan.'
                  : 'Tidak ada user dengan username atau ID "$_query".',
            ),
          ],
        ),
      );
    }

    final footer = (_hasMore || _loadingMore) ? 1 : 0;
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      color: AppColors.accentViolet,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: _items.length + 1 + footer,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
              child: Text(
                (_query.isEmpty ? 'Semua User' : 'Hasil Pencarian').toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
            );
          }
          final idx = i - 1;
          if (idx >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentViolet),
                ),
              ),
            );
          }
          final item = _items[idx];
          final busy = _busy.contains(item.firebaseUid);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _UserTile(
              key: ValueKey('u_${item.firebaseUid}'),
              item: item,
              busy: busy,
              onTap: () => _openProfile(item),
              trailing: _trailing(item, busy),
            ),
          );
        },
      ),
    );
  }

  Widget _trailing(FriendSearchItem item, bool busy) {
    final repo = ref.read(friendRepositoryProvider);
    final uid = item.firebaseUid;
    switch (item.relation) {
      case FriendRelationNone():
        return _PillButton(
          label: 'Tambah',
          icon: Icons.person_add_alt_1_rounded,
          filled: true,
          onTap: busy
              ? null
              : () => _run(item, () => repo.sendRequest(_myUid, uid), 'Gagal mengirim permintaan'),
        );
      case FriendRelationOutgoing(:final friendshipId):
        return _PillButton(
          label: 'Batalkan',
          filled: false,
          onTap: busy
              ? null
              : () => _run(item, () => repo.remove(friendshipId), 'Gagal membatalkan permintaan'),
        );
      case FriendRelationIncoming(:final friendshipId):
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundAction(
              tooltip: 'Tolak',
              icon: Icons.close_rounded,
              color: AppColors.textSecondary,
              background: AppColors.surfaceElevated,
              onTap: busy ? null : () => _run(item, () => repo.remove(friendshipId), 'Gagal menolak permintaan'),
            ),
            const SizedBox(width: 8),
            _RoundAction(
              tooltip: 'Terima',
              icon: Icons.check_rounded,
              color: Colors.white,
              background: AppColors.accentViolet,
              onTap: busy ? null : () => _run(item, () => repo.accept(friendshipId), 'Gagal menerima permintaan'),
            ),
          ],
        );
      case FriendRelationFriends():
        return const _FriendsChip();
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
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
      cursorColor: AppColors.accentViolet,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceDark,
        hintText: 'Cari username atau ID',
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

class _UserTile extends StatelessWidget {
  const _UserTile({
    super.key,
    required this.item,
    required this.trailing,
    required this.onTap,
    this.busy = false,
  });

  final FriendSearchItem item;
  final Widget trailing;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final nameColor = _parseHex(item.usernameColor) ?? AppColors.textWhite;
    final hasMeta = item.level != null || item.userNumber != null;
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
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
                          if (item.level != null && item.userNumber != null) const SizedBox(width: 6),
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
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentViolet),
                  ),
                )
              else
                trailing,
            ],
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
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.filled, required this.onTap, this.icon});

  final String label;
  final bool filled;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const textStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700);
    const padding = EdgeInsets.symmetric(horizontal: 14);
    const minSize = Size(0, 34);
    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon ?? Icons.add_rounded, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentViolet,
          foregroundColor: Colors.white,
          padding: padding,
          minimumSize: minSize,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: shape,
          textStyle: textStyle,
        ),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textWhite,
        side: const BorderSide(color: AppColors.surfaceElevated),
        padding: padding,
        minimumSize: minSize,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: shape,
        textStyle: textStyle,
      ),
      child: Text(label),
    );
  }
}

class _FriendsChip extends StatelessWidget {
  const _FriendsChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantDark,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 16, color: AppColors.textSecondary),
          SizedBox(width: 5),
          Text(
            'Teman',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      children: [
        for (var i = 0; i < 8; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
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
    );
  }
}
