import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../glass/glass.dart';
import '../chess/chess_board.dart';
import '../chess/chess_lobby_screen.dart';
import '../ludo/ludo_preview.dart';
import '../ludo/ludo_webview_screen.dart';
import '../store/coin_screen.dart';
import '../tree/tree_screen.dart';
import '../wallpaper/wallpaper_screen.dart';
import 'game_list_tile.dart';
import 'game_previews.dart';

/// Hub "Zenime Games": daftar game (Gaple, Ludo, Ular Tangga, Block!, Congklak,
/// Duel, Catur, Gacha, Pohon ZCoin). Border Avatar & Badge Level ada di
/// Zenime Decoration.
class ZenimeGamesScreen extends ConsumerStatefulWidget {
  const ZenimeGamesScreen({super.key});

  @override
  ConsumerState<ZenimeGamesScreen> createState() => _ZenimeGamesScreenState();
}

class _GameItem {
  const _GameItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.page,
    required this.preview,
    required this.info,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final Widget Function() page;

  /// Thumbnail halaman game (live, pakai data user).
  final Widget Function() preview;

  /// Jumlah pemain, mis. "2–4 pemain".
  final String info;
}

class _ZenimeGamesScreenState extends ConsumerState<ZenimeGamesScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  static final List<_GameItem> _games = [
    _GameItem(
      title: 'Gaple',
      subtitle: 'Domino klasik, 2–4 pemain',
      icon: Icons.view_agenda_rounded,
      colors: const [Color(0xFF0E3B26), Color(0xFF1F8A55), Color(0xFFFFE9A8)],
      page: () => const LudoWebViewScreen(path: '/gaple/'),
      preview: () => const GaplePreview(),
      info: '2–4 pemain',
    ),
    _GameItem(
      title: 'Ludo',
      subtitle: 'Mabar 2–4 pemain bareng temanmu',
      icon: Icons.groups_rounded,
      colors: const [Color(0xFF0E2A47), Color(0xFF2F80ED), Color(0xFFFFC94D)],
      page: () => const LudoWebViewScreen(),
      preview: () => const LudoBoardPreview(),
      info: '2–4 pemain',
    ),
    _GameItem(
      title: 'Ular Tangga',
      subtitle: 'Naik tangga, hindari ular, 2–6 pemain',
      icon: Icons.stairs_rounded,
      colors: const [Color(0xFF0F3D2A), Color(0xFF1FA35C), Color(0xFFFFC94D)],
      page: () => const LudoWebViewScreen(path: '/ular/'),
      preview: () => const UlarBoardPreview(),
      info: '2–6 pemain',
    ),
    _GameItem(
      title: 'Block!',
      subtitle: 'Susun balok, kejar rekor & peringkat',
      icon: Icons.view_module_rounded,
      colors: const [Color(0xFF1B2847), Color(0xFF6D4AFF), Color(0xFFFF6B81)],
      page: () => const LudoWebViewScreen(path: '/block/'),
      preview: () => const BlockPreview(),
      info: '1 pemain',
    ),
    _GameItem(
      title: 'Congklak',
      subtitle: 'Permainan tradisional, 1 lawan 1',
      icon: Icons.blur_on_rounded,
      colors: const [Color(0xFF3A1F0C), Color(0xFF9A5A28), Color(0xFFFFC94D)],
      page: () => const LudoWebViewScreen(path: '/congklak/'),
      preview: () => const CongklakPreview(),
      info: '2 pemain',
    ),
    _GameItem(
      title: 'Duel',
      subtitle: 'Tic-Tac-Toe & Connect 4, 1 lawan 1',
      icon: Icons.grid_3x3_rounded,
      colors: const [Color(0xFF14204A), Color(0xFF3D6EE0), Color(0xFFFF5C76)],
      page: () => const LudoWebViewScreen(path: '/duel/'),
      preview: () => const DuelPreview(),
      info: '2 pemain',
    ),
    _GameItem(
      title: 'Catur',
      subtitle: 'Mabar 1 lawan 1 dengan temanmu',
      icon: Icons.grid_on_rounded,
      colors: const [Color(0xFF141B2B), Color(0xFF3B4A6B), Color(0xFFE4344A)],
      page: () => const ChessLobbyScreen(),
      preview: () => const ChessBoardPreview(),
      info: '2 pemain',
    ),
    _GameItem(
      title: 'Gacha',
      subtitle: 'Spin wallpaper animasi buat komentarmu',
      icon: Icons.casino_rounded,
      colors: const [Color(0xFF3B1A6B), Color(0xFF8B3DFF), Color(0xFFFF2E63)],
      page: () => const WallpaperScreen(),
      preview: () => const GachaPreview(),
      info: '1 pemain',
    ),
    _GameItem(
      title: 'Pohon ZCoin',
      subtitle: 'Panen buahnya, dapat ZCoin tiap hari',
      icon: Icons.park_rounded,
      colors: const [Color(0xFF0F3D2A), Color(0xFF1F8A4C), Color(0xFFF59E0B)],
      page: () => const TreeScreen(),
      preview: () => const TreePreview(),
      info: '1 pemain',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _reveal(int i, Widget child) {
    final start = (i * 0.07).clamp(0.0, 0.5).toDouble();
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0).toDouble(), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  Future<void> _open(_GameItem g) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<void>(fadeRoute(g.page()));
    // Saldo bisa berubah (gacha / panen pohon).
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid != null && mounted) ref.invalidate(coinBalanceProvider(uid));
    // Thumbnail ikut update (buah dipanen, dll).
    if (mounted) refreshGamePreviews(ref);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid;
    final coins = uid == null ? null : ref.watch(coinBalanceProvider(uid)).valueOrNull;

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textWhite),
        ),
        title: const Text(
          'Zenime Games',
          style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView.separated(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        itemCount: _games.length + 2,
        separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 18 : 12),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _reveal(0, _CoinBar(coins: coins, onTap: () => Navigator.of(context).push<void>(fadeRoute(const CoinScreen()))));
          }
          if (i == 1) {
            return _reveal(1, const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Pilih game',
                style: TextStyle(color: AppColors.textWhite, fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ));
          }
          final g = _games[i - 2];
          return _reveal(
            i,
            GameListTile(
              title: g.title,
              info: g.info,
              infoIcon: Icons.people_outline_rounded,
              colors: g.colors,
              preview: g.preview(),
              onTap: () => _open(g),
            ),
          );
        },
      ),
    );
  }
}

class _CoinBar extends StatelessWidget {
  const _CoinBar({required this.coins, required this.onTap});

  final int? coins;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1A4A), AppColors.surfaceCard],
          ),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Image.asset('assets/images/ic_zcoin_badge.png', width: 34, height: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Saldo ZCoin',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (coins ?? 0).toDouble()),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => Text(
                      coins == null ? '—' : formatZCoin(v.round()),
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6),
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text('Top up',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
