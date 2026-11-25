import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../glass/glass.dart';
import '../avatar_frame/avatar_frame_screen.dart';
import '../games/game_list_tile.dart';
import '../games/game_previews.dart';
import '../../components/name_deco_styles.dart';
import '../level_badge/level_badge_shop_screen.dart';
import '../name_deco/name_deco_shop_screen.dart';

/// Hub "Zenime Decoration": Border Avatar, Badge Level & Dekorasi Nama.
class ZenimeDecorationScreen extends ConsumerStatefulWidget {
  const ZenimeDecorationScreen({super.key});

  @override
  ConsumerState<ZenimeDecorationScreen> createState() => _ZenimeDecorationScreenState();
}

class _DecorItem {
  const _DecorItem({
    required this.title,
    required this.info,
    required this.icon,
    required this.colors,
    required this.page,
    required this.preview,
  });

  final String title;
  final String info;
  final IconData icon;
  final List<Color> colors;
  final Widget Function() page;
  final Widget Function() preview;
}

class _ZenimeDecorationScreenState extends ConsumerState<ZenimeDecorationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  static final List<_DecorItem> _items = [
    _DecorItem(
      title: 'Border Avatar',
      info: 'Border animasi untuk avatar',
      icon: Icons.blur_circular_rounded,
      colors: const [Color(0xFF0B2A4A), Color(0xFF7C3AED), Color(0xFF22D3EE)],
      page: () => const AvatarFrameScreen(),
      preview: () => const FramePreview(),
    ),
    _DecorItem(
      title: 'Badge Level',
      info: 'Gaya badge LV beranimasi',
      icon: Icons.military_tech_rounded,
      colors: const [Color(0xFF1A1033), Color(0xFF6D28D9), Color(0xFFE8A317)],
      page: () => const LevelBadgeShopScreen(),
      preview: () => const LevelBadgePreview(),
    ),
    _DecorItem(
      title: 'Dekorasi Nama',
      info: 'Nama futuristik beranimasi',
      icon: Icons.text_fields_rounded,
      colors: const [Color(0xFF041A2A), Color(0xFF0E7490), Color(0xFFFF2A5F)],
      page: () => const NameDecoShopScreen(),
      preview: () => const NameDecoPreview(),
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
    final start = (i * 0.12).clamp(0.0, 0.5).toDouble();
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

  Future<void> _open(_DecorItem d) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<void>(fadeRoute(d.page()));
    // Saldo berubah kalau beli border/badge/dekorasi.
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid != null && mounted) ref.invalidate(coinBalanceProvider(uid));
    if (mounted) refreshGamePreviews(ref);
  }

  @override
  Widget build(BuildContext context) {
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
          'Zenime Decoration',
          style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView.separated(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final d = _items[i];
          return _reveal(
            i,
            GameListTile(
              title: d.title,
              info: d.info,
              infoIcon: d.icon,
              colors: d.colors,
              preview: d.preview(),
              onTap: () => _open(d),
            ),
          );
        },
      ),
    );
  }
}
