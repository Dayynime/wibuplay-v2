import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/account_models.dart';
import '../../data/models/avatar_frame_models.dart';
import '../../providers.dart';
import 'game_badges.dart';
import 'avatar_frame.dart';
import 'net_image.dart';

/// Warna tombol pill Premium, sama dengan ZenimeInfoBlue di Zenime.
const Color _kPremiumBlue = Color(0xFF3B82F6);

/// Header Beranda ala Zenime (port HomeProfileHeader + HomePremiumBanner di
/// HomeScreen.kt): kartu profil (avatar, username, level, ID, kode akun,
/// chip sisa hari Premium, chip saldo ZCoin) dan banner tombol Premium.
/// Hanya dipakai saat user sudah login.
class HomeProfileHeader extends ConsumerWidget {
  const HomeProfileHeader({
    super.key,
    required this.user,
    required this.onSearchClick,
    required this.onNotificationClick,
    required this.onProfileClick,
    required this.onPremiumClick,
    required this.onCoinClick,
    required this.onShieldClick,
  });

  final User user;
  final VoidCallback onSearchClick;

  /// Ikon lonceng, membuka layar Notifikasi (pertemanan & clan).
  final VoidCallback onNotificationClick;
  final VoidCallback onProfileClick;
  final VoidCallback onPremiumClick;
  final VoidCallback onCoinClick;

  /// Tombol perisai di kiri banner Premium (di Zenime membuka halaman Clan).
  final VoidCallback onShieldClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = user.uid;
    final chat = ref.watch(chatProfileProvider(uid)).valueOrNull;
    final identity = ref.watch(profileIdentityProvider(uid)).valueOrNull;
    final premium = ref.watch(premiumStatusProvider(uid)).valueOrNull ?? const PremiumStatus();
    final coins = ref.watch(coinBalanceProvider(uid)).valueOrNull ?? 0;
    final level = ref.watch(myXpProvider(uid)).valueOrNull?.level ?? 1;
    // Badge lonceng: notif belum dibaca, atau minimal jumlah request teman yang
    // masih menunggu (request lama sebelum ada fitur notif tetap kelihatan).
    final unreadNotifs = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;
    final pendingFriends = ref.watch(incomingFriendRequestsProvider).valueOrNull ?? 0;
    final friendRequests = unreadNotifs > pendingFriends ? unreadNotifs : pendingFriends;

    final chatName = chat?.username ?? '';
    final authName = user.displayName ?? '';
    final username = chatName.trim().isNotEmpty
        ? chatName
        : (authName.trim().isNotEmpty ? authName : 'Pengguna Zenime');
    final chatAvatar = chat?.avatarUrl ?? '';
    final avatarUrl = chatAvatar.isNotEmpty ? chatAvatar : user.photoURL;

    final userNumber = identity?.userNumber ?? chat?.userNumber;
    final code = identity?.zenimeCode;

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _ProfileCard(
            uid: uid,
            username: username,
            avatarUrl: avatarUrl,
            bannerUrl: premium.isPremium ? chat?.bannerUrl : null,
            level: level,
            userNumber: userNumber,
            zenimeCode: code,
            premium: premium,
            coins: coins,
            friendRequests: friendRequests,
            onSearchClick: onSearchClick,
            onNotificationClick: onNotificationClick,
            onProfileClick: onProfileClick,
            onPremiumClick: onPremiumClick,
            onCoinClick: onCoinClick,
          ),
          const SizedBox(height: 10),
          _PremiumBanner(
            isPremium: premium.isPremium,
            onPremiumClick: onPremiumClick,
            onShieldClick: onShieldClick,
          ),
        ],
      ),
    );

    // Masuk sekali saat pertama tampil: fade + geser naik sedikit.
    if (MediaQuery.of(context).disableAnimations) return header;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: header,
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.uid,
    required this.username,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.level,
    required this.userNumber,
    required this.zenimeCode,
    required this.premium,
    required this.coins,
    required this.friendRequests,
    required this.onSearchClick,
    required this.onNotificationClick,
    required this.onProfileClick,
    required this.onPremiumClick,
    required this.onCoinClick,
  });

  final String uid;
  final String username;
  final String? avatarUrl;

  /// Banner custom (khusus Premium). null = latar cahaya crimson.
  final String? bannerUrl;
  final int level;
  final int? userNumber;
  final String? zenimeCode;
  final PremiumStatus premium;
  final int coins;
  final int friendRequests;
  final VoidCallback onSearchClick;
  final VoidCallback onNotificationClick;
  final VoidCallback onProfileClick;
  final VoidCallback onPremiumClick;
  final VoidCallback onCoinClick;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(26);
    final days = premium.daysLeft;
    final hasBanner = bannerUrl != null && bannerUrl!.isNotEmpty;

    final premiumValue = premium.isPremium
        ? (days != null ? 'Sisa $days hari' : 'Premium aktif')
        : 'Aktifkan Premium';
    final premiumHint = premium.isPremium ? 'Premium' : 'Buka semua fitur';

    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1520), AppColors.surfaceCard, AppColors.surfaceDark],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            // Latar: banner Premium, atau cahaya crimson lembut.
            if (hasBanner)
              Positioned.fill(
                child: Opacity(opacity: 0.55, child: NetImage(bannerUrl!)),
              )
            else ...[
              const Positioned(top: -60, right: -40, child: _GlowOrb(size: 180, alpha: 0.30)),
              const Positioned(bottom: -70, left: -50, child: _GlowOrb(size: 160, alpha: 0.12)),
            ],
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.backgroundDark.withValues(alpha: hasBanner ? 0.25 : 0),
                      AppColors.backgroundDark.withValues(alpha: hasBanner ? 0.92 : 0.35),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Pressable(
                          onTap: onProfileClick,
                          scale: 0.98,
                          child: Row(
                            children: [
                              _RingAvatar(uid: uid, username: username, url: avatarUrl),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            username,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.textWhite,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        LevelBadge(level: level),
                                      ],
                                    ),
                                    if (userNumber != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'ID #$userNumber',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.textWhite.withValues(alpha: 0.6),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    if (zenimeCode != null && zenimeCode!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '#$zenimeCode',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.textWhite.withValues(alpha: 0.45),
                                          fontSize: 11,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CircleIconButton(
                        icon: Icons.notifications_rounded,
                        tooltip: 'Notifikasi',
                        onTap: onNotificationClick,
                        badgeCount: friendRequests,
                      ),
                      const SizedBox(width: 8),
                      _CircleIconButton(
                        icon: Icons.search_rounded,
                        tooltip: 'Cari Anime',
                        onTap: onSearchClick,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          onTap: onPremiumClick,
                          highlight: premium.isPremium,
                          icon: const PremiumCheckBadge(size: 16),
                          value: Text(
                            premiumValue,
                            key: ValueKey(premiumValue),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _StatTile.valueStyle.copyWith(
                              color: premium.isPremium
                                  ? AppColors.textWhite
                                  : AppColors.textSecondary,
                            ),
                          ),
                          hint: premiumHint,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          onTap: onCoinClick,
                          icon: Image.asset(
                            'assets/images/ic_zcoin_badge.png',
                            width: 16,
                            height: 16,
                            filterQuality: FilterQuality.medium,
                          ),
                          value: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: coins.toDouble()),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => Text(
                              formatZCoin(v.round()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _StatTile.valueStyle,
                            ),
                          ),
                          hint: 'ZCoin',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.accentViolet.withValues(alpha: alpha),
                AppColors.accentViolet.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      );
}

/// Kotak stat (sama dengan kartu akun di Pengaturan): ikon kecil di atas,
/// nilai tebal, lalu keterangan kecil.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.onTap,
    required this.icon,
    required this.value,
    required this.hint,
    this.highlight = false,
  });

  static const TextStyle valueStyle = TextStyle(
    color: AppColors.textWhite,
    fontSize: 14.5,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
  );

  final VoidCallback onTap;
  final Widget icon;
  final Widget value;
  final String hint;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlight
                ? const Color(0xFF3B82F6).withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                icon,
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textWhite.withValues(alpha: 0.35),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: value,
            ),
            const SizedBox(height: 1),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textWhite.withValues(alpha: 0.5),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  const _PremiumBanner({
    required this.isPremium,
    required this.onPremiumClick,
    required this.onShieldClick,
  });

  final bool isPremium;
  final VoidCallback onPremiumClick;
  final VoidCallback onShieldClick;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          _Pressable(
            onTap: onShieldClick,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.accentViolet.withValues(alpha: 0.22),
                    AppColors.accentViolet.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(color: AppColors.accentViolet.withValues(alpha: 0.28)),
              ),
              child: const Icon(Icons.shield_rounded, size: 21, color: AppColors.accentVioletLight),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Pressable(
              onTap: onPremiumClick,
              scale: 0.97,
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [_kPremiumBlue, Color(0xFF60A5FA)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kPremiumBlue.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isPremium ? 'Kelola Premium' : 'Beli Premium di Sini',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Efek tekan: mengecil sedikit lalu membal balik.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap, this.scale = 0.95});

  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Avatar 56dp dengan cincin gradien (Zenime: sweepGradient merah-kuning).
/// Kalau user memasang border avatar, cincin diganti border itu.
class _RingAvatar extends ConsumerWidget {
  const _RingAvatar({required this.uid, required this.username, required this.url});

  final String uid;
  final String username;
  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid.isNotEmpty) {
      ref.read(avatarFrameCacheProvider.notifier).request(uid);
      final frame = ref.watch(avatarFrameCacheProvider.select((m) => m[uid]));
      if (frame != null) {
        // Border (kanvas) dimuatkan ke kotak 56dp yang sama dengan versi
        // cincin, jadi foto mengecil dan border tidak meluber ke luar kartu.
        final size = 56 / avatarFrameScale(frame);
        return SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: UserAvatar(username: username, url: url, size: size, frameUid: uid),
          ),
        );
      }
    }
    return Container(
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [AppColors.accentViolet, AppColors.warningAmber, AppColors.accentViolet],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: AppColors.surfaceCard,
          shape: BoxShape.circle,
        ),
        child: UserAvatar(username: username, url: url, size: 48),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// > 0 menampilkan badge angka (9+ kalau lebih dari 9) di pojok ikon.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Badge(
            isLabelVisible: badgeCount > 0,
            backgroundColor: AppColors.errorRed,
            textColor: Colors.white,
            label: Text(badgeCount > 9 ? '9+' : '$badgeCount'),
            child: Icon(icon, size: 19, color: AppColors.textWhite),
          ),
        ),
      ),
    );
  }
}
