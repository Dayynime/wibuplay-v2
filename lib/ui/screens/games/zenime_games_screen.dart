import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../glass/glass.dart';
import '../avatar_frame/avatar_frame_screen.dart';
import '../profile_effect/profile_effect_screen.dart';
import '../store/coin_screen.dart';
import '../tree/tree_screen.dart';
import '../wallpaper/wallpaper_screen.dart';
import 'game_previews.dart';

/// Hub "Zenime Games": satu pintu ke Gacha, Pohon ZCoin, Border Avatar, dan
/// Efek Profil (dulunya empat kartu terpisah di tab Menu).
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
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final Widget Function() page;

  /// Thumbnail halaman game (live, pakai data user).
  final Widget Function() preview;
}

class _ZenimeGamesScreenState extends ConsumerState<ZenimeGamesScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  static final List<_GameItem> _games = [
    _GameItem(
      title: 'Gacha',
      subtitle: 'Spin wallpaper animasi buat komentarmu',
      icon: Icons.casino_rounded,
      colors: const [Color(0xFF3B1A6B), Color(0xFF8B3DFF), Color(0xFFFF2E63)],
      page: () => const WallpaperScreen(),
      preview: () => const GachaPreview(),
    ),
    _GameItem(
      title: 'Pohon ZCoin',
      subtitle: 'Panen buahnya, dapat ZCoin tiap hari',
      icon: Icons.park_rounded,
      colors: const [Color(0xFF0F3D2A), Color(0xFF1F8A4C), Color(0xFFF59E0B)],
      page: () => const TreeScreen(),
      preview: () => const TreePreview(),
    ),
    _GameItem(
      title: 'Border Avatar',
      subtitle: 'Hias avatarmu dengan border animasi',
      icon: Icons.blur_circular_rounded,
      colors: const [Color(0xFF0B2A4A), Color(0xFF7C3AED), Color(0xFF22D3EE)],
      page: () => const AvatarFrameScreen(),
      preview: () => const FramePreview(),
    ),
    _GameItem(
      title: 'Efek Profil',
      subtitle: 'Animasi keren di profilmu',
      icon: Icons.auto_awesome_rounded,
      colors: const [Color(0xFF2A0B3D), Color(0xFFDB2777), Color(0xFFF59E0B)],
      page: () => const ProfileEffectScreen(),
      preview: () => const EffectPreview(),
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
    final start = (i * 0.1).clamp(0.0, 0.5).toDouble();
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0).toDouble(), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  Future<void> _open(_GameItem g) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<void>(fadeRoute(g.page()));
    // Saldo bisa berubah (gacha / panen pohon / beli border & efek).
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid != null && mounted) ref.invalidate(coinBalanceProvider(uid));
    // Thumbnail ikut update (border/efek baru dipasang, buah dipanen, dll).
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
      body: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          _reveal(0, _CoinBar(coins: coins, onTap: () => Navigator.of(context).push<void>(fadeRoute(const CoinScreen())))),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _games.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.7,
            ),
            itemBuilder: (_, i) => _reveal(i + 1, _GameTile(item: _games[i], onTap: () => _open(_games[i]))),
          ),
        ],
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
    return _Pressable(
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

class _GameTile extends StatelessWidget {
  const _GameTile({required this.item, required this.onTap});

  final _GameItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: item.colors,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail halaman game.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0x59000000)),
                      RepaintBoundary(child: item.preview()),
                      // Ikon game di pojok kiri atas thumbnail.
                      Positioned(
                        left: 7,
                        top: 7,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: Icon(item.icon, color: Colors.white, size: 17),
                        ),
                      ),
                      // Garis tepi tipis biar terlihat seperti "layar".
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, height: 1.3),
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

/// Efek tekan: mengecil sedikit lalu membal balik.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

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
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
