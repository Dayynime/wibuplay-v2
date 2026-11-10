import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../redesign/z_kit.dart';

/// Tab "Menu" di bottom bar: pintu masuk ke Nobar, Feed, Cuplix, Games
/// (Gacha, Pohon ZCoin, Border, Efek), Donghua, Komik, Riwayat, Favorit, lalu
/// dompet ZCoin & Premium. Tata letak sama dengan sheet Menu di preview:
/// judul, grid ikon 4 kolom, dompet dua kotak di bawah.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid;
    final coins = uid == null ? null : ref.watch(coinBalanceProvider(uid)).valueOrNull;
    final premium = uid == null ? null : ref.watch(premiumStatusProvider(uid)).valueOrNull;
    final isPremium = premium?.isPremium == true;
    final days = premium?.daysLeft;

    void push(Widget page) => Navigator.of(context).push<void>(fadeRoute(page));

    final items = <_MenuItem>[
      _MenuItem('Nobar', Icons.groups_rounded, 160, () => push(const NobarLobbyScreen())),
      _MenuItem('Feed', Icons.dynamic_feed_rounded, 330, () => push(const FeedScreen())),
      _MenuItem('Cuplix', Icons.slow_motion_video_rounded, 280, () => openCuplix(context)),
      _MenuItem('Games', Icons.sports_esports_rounded, 40, () => push(const ZenimeGamesScreen())),
      _MenuItem('Donghua', Icons.live_tv_rounded, 18, () => openDonghua(context)),
      _MenuItem('Komik', Icons.menu_book_rounded, 200, () => openComic(context)),
      _MenuItem('Riwayat', Icons.history_rounded, 150, () => push(const HistoryScreen())),
      _MenuItem('Favorit', Icons.favorite_rounded, 300, () => push(const FavoritesScreen())),
    ];

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: ListView(
          // ruang untuk bottom bar melayang
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 130),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('メニュー', style: ZFont.jp()),
                  Text('Menu', style: ZFont.display(size: 26, height: 1.1)),
                ],
              ),
            ),
            // Grid ikon 4 kolom (52px, sudut 17, warna lembut per fitur).
            for (var r = 0; r < items.length; r += 4) ...[
              if (r > 0) const SizedBox(height: 14),
              Row(
                children: [
                  for (var c = r; c < r + 4; c++)
                    Expanded(child: c < items.length ? _MenuIcon(item: items[c]) : const SizedBox()),
                ],
              ),
            ],
            const SizedBox(height: 22),
            // Dompet: ZCoin & Premium.
            Row(
              children: [
                Expanded(
                  child: _WalletTile(
                    label: 'Saldo ZCoin',
                    icon: Image.asset('assets/images/ic_zcoin_badge.png', width: 18, height: 18),
                    value: coins == null ? 'Top up' : formatZCoin(coins),
                    // di-await supaya saldo di-refresh setelah kembali dari top up
                    onTap: () => Navigator.of(context).push<void>(fadeRoute(const CoinScreen())),
                    onReturn: uid == null ? null : () => ref.invalidate(coinBalanceProvider(uid)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WalletTile(
                    label: 'Premium',
                    icon: const Icon(Icons.workspace_premium_rounded, size: 18, color: Color(0xFFF6BE4F)),
                    value: !isPremium
                        ? 'Beli'
                        : (days != null ? '$days hari' : 'Aktif'),
                    onTap: () => Navigator.of(context).push<void>(fadeRoute(const PremiumScreen())),
                    onReturn: uid == null ? null : () => ref.invalidate(premiumStatusProvider(uid)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.label, this.icon, this.hue, this.onTap);

  final String label;
  final IconData icon;

  /// Rona warna (0..360) seperti preview: latar hsl(h 70% 55% / .16),
  /// ikon hsl(h 90% 72%).
  final double hue;
  final VoidCallback onTap;
}

/// Ikon fitur: kotak warna lembut tanpa garis tepi + label.
class _MenuIcon extends StatelessWidget {
  const _MenuIcon({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    final bg = HSLColor.fromAHSL(0.16, item.hue, 0.70, 0.55).toColor();
    final fg = HSLColor.fromAHSL(1, item.hue, 0.90, 0.72).toColor();
    return ZPress(
      onTap: item.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(17)),
            child: Icon(item.icon, color: fg, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Kotak dompet (preview): label kecil di atas, nilai tebal dengan ikon.
class _WalletTile extends StatelessWidget {
  const _WalletTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.onReturn,
  });

  final String label;
  final Widget icon;
  final String value;
  final Future<void> Function() onTap;

  /// Dipanggil setelah kembali dari halaman toko (refresh saldo/status).
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    return ZPress(
      onTap: () async {
        await onTap();
        onReturn?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariantDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(height: 3),
            Row(
              children: [
                icon,
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZFont.display(size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
