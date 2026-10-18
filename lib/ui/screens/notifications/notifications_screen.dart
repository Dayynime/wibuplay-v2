import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/notification_models.dart';
import '../../../data/repository/notification_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/game_badges.dart';
import '../comments/comments_section.dart' show formatCommentRelativeTime;
import '../friends/friends_screen.dart';
import 'notification_router.dart';

/// Lonceng Beranda: daftar notifikasi (pertemanan & clan). Begitu dibuka,
/// semua ditandai dibaca di server (badge hilang), tapi titik "baru" tetap
/// tampil selama layar ini terbuka supaya user tahu mana yang baru.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  NotificationRepository get _repo => ref.read(notificationRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await _repo.list();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _hasMore = page.items.length >= NotificationRepository.pageSize;
        _loading = false;
      });
      if (page.unread > 0) {
        await _repo.markRead();
        ref.invalidate(unreadNotificationsProvider);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e, 'Gagal memuat notifikasi');
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.list(beforeId: _items.last.id);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _hasMore = page.items.length >= NotificationRepository.pageSize;
      });
    } catch (_) {
      // Diam saja; user bisa scroll lagi untuk coba ulang.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Hapus semua notifikasi?', style: TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Riwayat notifikasi dihapus permanen. Permintaan pertemanan & request clan tetap ada.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.clearAll();
      if (!mounted) return;
      setState(() {
        _items = const [];
        _hasMore = false;
      });
      ref.invalidate(unreadNotificationsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e, 'Gagal menghapus notifikasi'))));
    }
  }

  Future<void> _tap(AppNotification n) async {
    setState(() {
      _items = [for (final x in _items) x.id == n.id ? x.copyWith(read: true) : x];
    });
    await openNotificationTarget(ref, n.type, n.data);
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(incomingFriendRequestsProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: const Text('Notifikasi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Hapus semua',
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accentViolet,
        onRefresh: () async {
          ref.invalidate(incomingFriendRequestsProvider);
          await _load();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (s) {
            if (s.metrics.pixels > s.metrics.maxScrollExtent - 300) _loadMore();
            return false;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              // Pintasan request teman yang masih menunggu (termasuk yang
              // masuk sebelum fitur notifikasi ada).
              if (incoming > 0)
                _FriendRequestShortcut(
                  count: incoming,
                  onTap: () => Navigator.of(context)
                      .push<void>(fadeRoute(const FriendsScreen()))
                      .then((_) => ref.invalidate(incomingFriendRequestsProvider)),
                ),
              ..._content(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content() {
    if (_loading) {
      return const [
        SizedBox(height: 160),
        Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
      ];
    }
    if (_error != null) {
      return [
        const SizedBox(height: 120),
        _Empty(
          icon: Icons.wifi_off_rounded,
          title: 'Gagal memuat',
          message: _error!,
          action: FilledButton(
            onPressed: _load,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
            child: const Text('Coba lagi'),
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return const [
        SizedBox(height: 120),
        _Empty(
          icon: Icons.notifications_none_rounded,
          title: 'Belum ada notifikasi',
          message: 'Permintaan pertemanan dan request join clan bakal muncul di sini.',
        ),
      ];
    }
    return [
      for (final n in _items) _NotificationTile(item: n, onTap: () => _tap(n)),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentViolet),
            ),
          ),
        ),
    ];
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !item.read;
    final dim = item.expired;
    final name = item.actorUsername?.trim() ?? '';

    final Widget avatar = item.actorUid != null
        ? UserAvatar(
            username: name.isEmpty ? '?' : name,
            url: item.actorAvatarUrl,
            size: 46,
            frameUid: item.actorUid,
          )
        : Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(color: AppColors.accentVioletSubtle, shape: BoxShape.circle),
            child: Icon(notificationIcon(item.type), color: AppColors.accentViolet, size: 22),
          );

    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: unread ? AppColors.surfaceVariantDark : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unread ? AppColors.accentViolet.withValues(alpha: 0.35) : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    avatar,
                    if (item.actorUid != null)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: AppColors.accentViolet,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.backgroundDark, width: 2),
                          ),
                          child: Icon(notificationIcon(item.type), size: 11, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dim ? '${item.body} (dibatalkan)' : item.body,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatCommentRelativeTime(item.createdAt),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Container(
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(color: AppColors.accentViolet, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendRequestShortcut extends StatelessWidget {
  const _FriendRequestShortcut({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x40E4344A), Color(0x14E4344A)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: const Icon(Icons.people_alt_rounded, color: AppColors.accentViolet),
        title: const Text(
          'Permintaan pertemanan',
          style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '$count menunggu jawabanmu',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
