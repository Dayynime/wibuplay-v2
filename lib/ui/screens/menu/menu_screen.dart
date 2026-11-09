import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/image_cache.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../providers.dart';
import '../../app_routes.dart';
import '../library/library_screens.dart';
import '../store/coin_screen.dart';
import '../store/premium_screen.dart';
import '../games/zenime_games_screen.dart';
import '../nobar/nobar_lobby_screen.dart';
import '../feed/feed_screen.dart';
import '../../glass/glass.dart';
import '../../components/net_image.dart' show netImageHeaders;

// Poster sama dengan slide onboarding (CDN publik MyAnimeList, tidak di-bundle).
const String _kDonghuaPoster = 'https://cdn.myanimelist.net/images/anime/1438/101531l.jpg';
const String _kComicPoster = 'https://cdn.myanimelist.net/images/manga/4/221353l.jpg';

/// Tab "Menu" di bottom bar (menggantikan tab Komik): pintu masuk ke
/// Cuplix, Donghua, Komik, Zenime Games (Gacha, Pohon ZCoin, Border, Efek), ZCoin, dan Premium.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid;
    final coins = uid == null ? null : ref.watch(coinBalanceProvider(uid)).valueOrNull;
    final premium = uid == null ? null : ref.watch(premiumProvider(uid)).valueOrNull;
    // Thumbnail klip teratas jadi gambar kartu Cuplix (gagal -> pakai ikon).
    final cuplixThumb = ref
        .watch(homeCuplixProvider)
        .valueOrNull
        ?.map((c) => c.thumbnailUrl)
        .firstWhere((u) => u.isNotEmpty, orElse: () => '');

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: ListView(
          // ruang untuk bottom bar melayang
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 6, 2, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'メニュー',
                    style: TextStyle(
                      color: AppColors.accentVioletLight,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'Menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            // Dompet: ZCoin & Premium.
            Row(
              children: [
                Expanded(
                  child: _ShopTile(
                    title: 'ZCoin',
                    value: coins == null ? 'Top up' : formatZCoin(coins),
                    caption: 'Top up ZCoin',
                    accent: const Color(0xFFF6BE4F),
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
            const SizedBox(height: 20),
            // Grid fitur 4 kolom (gaya preview): satu ketukan ke semua fitur.
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 6,
              childAspectRatio: 0.82,
              children: [
                _MenuIcon(
                  label: 'Nobar',
                  icon: Icons.groups_rounded,
                  accent: const Color(0xFF22C55E),
                  onTap: () => Navigator.of(context).push<void>(fadeRoute(const NobarLobbyScreen())),
                ),
                _MenuIcon(
                  label: 'Feed',
                  icon: Icons.dynamic_feed_rounded,
                  accent: const Color(0xFF8B5CF6),
                  onTap: () => Navigator.of(context).push<void>(fadeRoute(const FeedScreen())),
                ),
                _MenuIcon(
                  label: 'Cuplix',
                  icon: Icons.slow_motion_video_rounded,
                  accent: const Color(0xFFF97316),
                  onTap: () => openCuplix(context),
                ),
                _MenuIcon(
                  label: 'Games',
                  icon: Icons.sports_esports_rounded,
                  accent: const Color(0xFFA855F7),
                  onTap: () => Navigator.of(context).push<void>(fadeRoute(const ZenimeGamesScreen())),
                ),
                _MenuIcon(
                  label: 'Donghua',
                  icon: Icons.movie_filter_outlined,
                  accent: const Color(0xFFEF4444),
                  onTap: () => openDonghua(context),
                ),
                _MenuIcon(
                  label: 'Komik',
                  icon: Icons.menu_book_outlined,
                  accent: const Color(0xFF3B82F6),
                  onTap: () => openComic(context),
                ),
                _MenuIcon(
                  label: 'Riwayat',
                  icon: Icons.history_rounded,
                  accent: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).push<void>(fadeRoute(const HistoryScreen())),
                ),
                _MenuIcon(
                  label: 'Favorit',
                  icon: Icons.favorite_rounded,
                  accent: const Color(0xFFEC4899),
                  onTap: () => Navigator.of(context).push<void>(fadeRoute(const FavoritesScreen())),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                'Sorotan',
                style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            _MenuCard(
              title: 'Cuplix',
              subtitle: 'Klip pendek momen anime terbaik',
              icon: Icons.slow_motion_video_rounded,
              accent: const Color(0xFFF97316),
              imageUrl: (cuplixThumb == null || cuplixThumb.isEmpty) ? null : cuplixThumb,
              // CDN klip butuh Referer/User-Agent yang sama dengan API.
              useApiHeaders: true,
              onTap: () => openCuplix(context),
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
    this.useApiHeaders = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final String? imageUrl;
  final Gradient? gradient;
  final bool useApiHeaders;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 112,
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
                      cacheManager: AppImageCache.images,
                      imageUrl: imageUrl!,
                      httpHeaders: useApiHeaders ? netImageHeaders : null,
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
                    child: Icon(icon, size: 130, color: accent.withValues(alpha: 0.10)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.18),
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

/// Ikon fitur di grid Menu: kotak warna lembut + label.
class _MenuIcon extends StatelessWidget {
  const _MenuIcon({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: Color.lerp(accent, Colors.white, 0.25), size: 26),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
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
