import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/account_models.dart';
import '../../providers.dart';
import 'game_badges.dart';

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
    required this.onProfileClick,
    required this.onPremiumClick,
    required this.onCoinClick,
    required this.onShieldClick,
  });

  final User user;
  final VoidCallback onSearchClick;
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

    final chatName = chat?.username ?? '';
    final authName = user.displayName ?? '';
    final username = chatName.trim().isNotEmpty
        ? chatName
        : (authName.trim().isNotEmpty ? authName : 'Pengguna Zenime');
    final chatAvatar = chat?.avatarUrl ?? '';
    final avatarUrl = chatAvatar.isNotEmpty ? chatAvatar : user.photoURL;

    final userNumber = identity?.userNumber ?? chat?.userNumber;
    final code = identity?.zenimeCode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _ProfileCard(
            username: username,
            avatarUrl: avatarUrl,
            level: level,
            userNumber: userNumber,
            zenimeCode: code,
            premium: premium,
            coins: coins,
            onSearchClick: onSearchClick,
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
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.username,
    required this.avatarUrl,
    required this.level,
    required this.userNumber,
    required this.zenimeCode,
    required this.premium,
    required this.coins,
    required this.onSearchClick,
    required this.onProfileClick,
    required this.onPremiumClick,
    required this.onCoinClick,
  });

  final String username;
  final String? avatarUrl;
  final int level;
  final int? userNumber;
  final String? zenimeCode;
  final PremiumStatus premium;
  final int coins;
  final VoidCallback onSearchClick;
  final VoidCallback onProfileClick;
  final VoidCallback onPremiumClick;
  final VoidCallback onCoinClick;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    final divider = Colors.white.withValues(alpha: 0.08);
    final days = premium.daysLeft;
    final premiumLabel = premium.isPremium
        ? (days != null ? 'Sisa $days hari' : 'Premium aktif')
        : 'Aktifkan Premium';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surfaceCard,
            AppColors.surfaceCard.withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(color: AppColors.accentViolet.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentViolet.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onProfileClick,
                  child: Row(
                    children: [
                      _RingAvatar(username: username, url: avatarUrl),
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
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
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
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                              ),
                            ],
                            if (zenimeCode != null && zenimeCode!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '#$zenimeCode',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
              _CircleIconButton(icon: Icons.search, tooltip: 'Cari Anime', onTap: onSearchClick),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: divider),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Chip(
                  onTap: onPremiumClick,
                  outlined: true,
                  child: Row(
                    children: [
                      const PremiumCheckBadge(size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          premiumLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: premium.isPremium ? Colors.white : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Chip(
                onTap: onCoinClick,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/ic_zcoin_badge.png',
                      width: 16,
                      height: 16,
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatZCoin(coins),
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Text(
                      'ZCoin',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onShieldClick,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariantDark,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield, size: 20, color: AppColors.accentViolet),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onPremiumClick,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kPremiumBlue,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  isPremium ? 'KELOLA PREMIUM' : 'BELI PREMIUM DI SINI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar 56dp dengan cincin gradien (Zenime: sweepGradient merah-kuning).
class _RingAvatar extends StatelessWidget {
  const _RingAvatar({required this.username, required this.url});

  final String username;
  final String? url;

  @override
  Widget build(BuildContext context) {
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
  const _CircleIconButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariantDark.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.child, required this.onTap, this.outlined = false});

  final Widget child;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : AppColors.surfaceVariantDark,
          borderRadius: BorderRadius.circular(50),
          border: outlined ? Border.all(color: Colors.white.withValues(alpha: 0.12)) : null,
        ),
        child: child,
      ),
    );
  }
}
