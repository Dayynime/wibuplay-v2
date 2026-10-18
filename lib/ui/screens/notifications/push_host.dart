import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_config.dart';
import '../../../core/push_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/repository/auth_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import 'notification_router.dart';

/// Penghubung push notif dengan app (dipasang di atas AppShell, main.dart):
///  - daftarkan token HP saat login, hapus saat logout;
///  - push masuk saat app TERBUKA -> banner kecil di atas + badge lonceng naik
///    (Android tidak menampilkan notif sistem kalau app sedang dibuka);
///  - push di-tap (app di background / tertutup) -> buka halaman tujuannya.
class PushHost extends ConsumerStatefulWidget {
  const PushHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushHost> createState() => _PushHostState();
}

class _PushHostState extends ConsumerState<PushHost> {
  final List<StreamSubscription<dynamic>> _subs = [];
  OverlayEntry? _banner;
  Timer? _syncTimer;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    AuthRepository.beforeSignOut = PushService.instance.unregister;

    // Push didaftarkan BELAKANGAN (5 detik setelah app siap) supaya tidak
    // rebutan jaringan dengan data akun (profil, ZCoin, premium) saat app
    // baru dibuka. Logout tetap diproses langsung.
    ref.listenManual(authUserProvider, (_, next) {
      final uid = next.valueOrNull?.uid;
      _syncTimer?.cancel();
      if (uid == null || uid.isEmpty) {
        PushService.instance.syncForUser(ref.read(notificationRepositoryProvider), null);
        return;
      }
      _syncTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        if (ref.read(authUserProvider).valueOrNull?.uid != uid) return;
        PushService.instance.syncForUser(ref.read(notificationRepositoryProvider), uid);
      });
    }, fireImmediately: true);

    if (!FirebaseConfig.ready) return;
    _subs.add(FirebaseMessaging.onMessage.listen(_onForeground));
    _subs.add(FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data)));
    // App dibuka dari keadaan tertutup lewat tap notif.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final m = await FirebaseMessaging.instance.getInitialMessage();
        if (m != null && mounted) _open(m.data);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _hideBanner();
    if (AuthRepository.beforeSignOut == PushService.instance.unregister) {
      AuthRepository.beforeSignOut = null;
    }
    super.dispose();
  }

  void _refreshBadges(String type) {
    ref.invalidate(unreadNotificationsProvider);
    if (type.startsWith('friend_')) ref.invalidate(incomingFriendRequestsProvider);
  }

  void _onForeground(RemoteMessage m) {
    final type = m.data['type']?.toString() ?? '';
    _refreshBadges(type);
    final title = m.notification?.title ?? '';
    final body = m.notification?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;
    _showBanner(type, title, body, () => _open(m.data));
  }

  Future<void> _open(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';
    final id = int.tryParse(data['notification_id']?.toString() ?? '');
    if (id != null) {
      ref.read(notificationRepositoryProvider).markRead([id]).then(
            (_) => ref.invalidate(unreadNotificationsProvider),
            onError: (_) {},
          );
    }
    await openNotificationTarget(ref, type, data);
    if (mounted) _refreshBadges(type);
  }

  // ---------------------------------------------------------------- banner

  void _hideBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _banner?.remove();
    _banner = null;
  }

  void _showBanner(String type, String title, String body, VoidCallback onTap) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _hideBanner();
    final entry = OverlayEntry(
      builder: (context) => _PushBanner(
        icon: notificationIcon(type),
        title: title,
        body: body,
        onTap: () {
          _hideBanner();
          onTap();
        },
        onDismiss: _hideBanner,
      ),
    );
    _banner = entry;
    overlay.insert(entry);
    _bannerTimer = Timer(const Duration(seconds: 4), _hideBanner);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PushBanner extends StatefulWidget {
  const _PushBanner({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_PushBanner> createState() => _PushBannerState();
}

class _PushBannerState extends State<_PushBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
        child: Dismissible(
          key: const ValueKey('push_banner'),
          direction: DismissDirection.up,
          onDismissed: (_) => widget.onDismiss(),
          child: Material(
            color: AppColors.surfaceElevated,
            elevation: 10,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: AppColors.accentVioletSubtle,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, color: AppColors.accentViolet, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textWhite,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (widget.body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
