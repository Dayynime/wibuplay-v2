import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../providers.dart';
import '../../app_routes.dart';
import '../library/library_screens.dart';
import '../profile/profile_controller.dart';
import '../store/coin_screen.dart';
import '../store/premium_screen.dart';
import '../games/zenime_games_screen.dart';
import '../../glass/glass.dart';

// Poster sama dengan slide onboarding (CDN publik MyAnimeList, tidak di-bundle).
const String _kDonghuaPoster = 'https://cdn.myanimelist.net/images/anime/1438/101531l.jpg';
const String _kComicPoster = 'https://cdn.myanimelist.net/images/manga/4/221353l.jpg';

/// Tab "Menu" di bottom bar (menggantikan tab Komik): pintu masuk ke
/// Donghua, Komik, Zenime Games (Gacha, Pohon ZCoin, Border, Efek), ZCoin, dan Premium.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid;
    final coins = uid == null ? null : ref.watch(coinBalanceProvider(uid)).valueOrNull;
    final premium = uid == null ? null : ref.watch(premiumProvider(uid)).valueOrNull;
    final historyCount = ref.watch(profileHistoryProvider).length;
    final favoriteCount = ref.watch(profileFavoritesProvider).length;

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: ListView(
          // ruang untuk bottom bar melayang
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 2),
              child: Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
              child: Text(
                'Konten lain selain anime',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _ShopTile(
                    title: 'ZCoin',
                    value: coins == null ? 'Top up' : formatZCoin(coins),
                    caption: 'Top up ZCoin',
                    accent: const Color(0xFF8B5CF6),
                    leading: Image.asset('assets/images/ic_zcoin_badge.png', width: 26, height: 26),
                    // di-await supaya saldo di-refresh setelah kembali dari top up
                    onTap: () => Navigator.of(context).push<void>(fadeRoute(const CoinScreen())),
                    onReturn: uid == null ? null : () => ref.invalidate(coinBalanceProvider(uid)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShopTile(
                    title: 'Premium',
                    value: premium == true ? 'Aktif' : 'Beli',
                    caption: premium == true ? 'Kelola Premium' : 'Bebas iklan & 1080p',
                    accent: const Color(0xFF3B82F6),
                    leading: const Icon(Icons.verified, color: Color(0xFF3B9BFF), size: 26),
                    onTap: () => Navigator.of(context).push<void>(fadeRoute(const PremiumScreen())),
                    onReturn: uid == null ? null : () => ref.invalidate(premiumStatusProvider(uid)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ShopTile(
                    title: 'Riwayat',
                    value: historyCount == 0 ? 'Kosong' : '$historyCount',
                    caption: historyCount == 0 ? 'Belum ada tontonan' : 'Lanjut nonton',
                    accent: const Color(0xFFF59E0B),
                    leading: const Icon(Icons.history, color: Color(0xFFF59E0B), size: 26),
                    onTap: () => Navigator.of(context).push<void>(fadeRoute(const HistoryScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShopTile(
                    title: 'Favorit',
                    value: favoriteCount == 0 ? 'Kosong' : '$favoriteCount',
                    caption: favoriteCount == 0 ? 'Belum ada favorit' : 'Anime favoritmu',
                    accent: const Color(0xFFEC4899),
                    leading: const Icon(Icons.favorite, color: Color(0xFFEC4899), size: 26),
                    onTap: () => Navigator.of(context).push<void>(fadeRoute(const FavoritesScreen())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _MenuCard(
              title: 'Donghua',
              subtitle: 'Animasi China terbaru & ongoing',
              icon: Icons.movie_filter_outlined,
              accent: const Color(0xFFEF4444),
              imageUrl: _kDonghuaPoster,
              onTap: () => openDonghua(context),
            ),
            const SizedBox(height: 14),
            _MenuCard(
              title: 'Komik',
              subtitle: 'Manga, manhwa, dan manhua',
              icon: Icons.menu_book_outlined,
              accent: const Color(0xFF3B82F6),
              imageUrl: _kComicPoster,
              onTap: () => openComic(context),
            ),
            const SizedBox(height: 14),
            _MenuCard(
              title: 'Zenime Games',
              subtitle: 'Gacha, Pohon ZCoin, Border Avatar & Efek Profil',
              icon: Icons.sports_esports_rounded,
              accent: const Color(0xFFA855F7),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3B1A6B), Color(0xFF8B3DFF), Color(0xFF22D3EE)],
              ),
              onTap: () => Navigator.of(context).push<void>(fadeRoute(const ZenimeGamesScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.imageUrl,
    this.gradient,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final String? imageUrl;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 132,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 170,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                if (imageUrl != null)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [AppColors.surfaceDark, AppColors.surfaceDark, Color(0x330F131B)],
                        stops: [0, 0.5, 1],
                      ),
                    ),
                  ),
                if (imageUrl == null)
                  Positioned(
                    right: -14,
                    bottom: -18,
                    child: Icon(icon, size: 130, color: Colors.white.withValues(alpha: 0.12)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: imageUrl == null ? 0.35 : 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: accent.withValues(alpha: 0.6)),
                        ),
                        child: Icon(icon, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 60),
                    ],
                  ),
                ),
                const Positioned(
                  right: 14,
                  bottom: 14,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Color(0x99000000),
                    child: Icon(Icons.chevron_right, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartu kecil ZCoin / Premium di bagian atas Menu.
class _ShopTile extends StatelessWidget {
  const _ShopTile({
    required this.title,
    required this.value,
    required this.caption,
    required this.accent,
    required this.leading,
    required this.onTap,
    this.onReturn,
  });

  final String title;
  final String value;
  final String caption;
  final Color accent;
  final Widget leading;
  final Future<void> Function() onTap;

  /// Dipanggil setelah kembali dari halaman toko (refresh saldo/status).
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await onTap();
          onReturn?.call();
        },
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  leading,
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
