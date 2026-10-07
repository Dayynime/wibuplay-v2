import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers.dart';
import '../app_routes.dart';
import '../components/floating_bottom_bar.dart';
import '../screens/cuplix/cuplix_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/schedule/schedule_screen.dart';

/// Port AppNavigation.kt: 5 tab + bottom bar melayang.
/// Beranda, Jelajah, Jadwal, Cuplix, Profil; Detail dan Player dibuka lewat
/// openDetail/openPlayer (app_routes.dart).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Sambung lagi polling progres download yang masih jalan di sistem.
    ref.read(episodeDownloadManagerProvider).reconcileActiveDownloads();
  }

  /// Tab dibuat saat pertama kali dibuka (seperti NavHost), supaya Jelajah,
  /// Jadwal, dan Cuplix tidak memanggil API sebelum dikunjungi.
  final Set<int> _visited = {0};

  /// Arah perpindahan tab (+1 ke kanan, -1 ke kiri) untuk animasi geser.
  int _dir = 1;

  void _goTab(int i) {
    if (i == _index) return;
    setState(() {
      _dir = i > _index ? 1 : -1;
      _index = i;
      _visited.add(i);
    });
  }

  Widget _tab(int i, Widget Function() build) => _AnimatedTab(
        active: _index == i,
        direction: _dir,
        child: _visited.contains(i) ? build() : const SizedBox.shrink(),
      );

  void _openDetail(String movieId) => openDetail(context, movieId);

  void _openPlayer(String movieId, String episodeId) =>
      openPlayer(context, movieId, episodeId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          Stack(
            fit: StackFit.expand,
            children: [
              _tab(0, () => HomeScreen(
                onAnimeClick: _openDetail,
                onWatchEpisode: _openPlayer,
                onSearchClick: () => _goTab(1),
                onSeeAllClick: (_) => _goTab(1),
                onProfileClick: () => _goTab(4),
                onCuplixClick: () => _goTab(3),
              )),
              _tab(1, () => ExploreScreen(onAnimeClick: _openDetail)),
              _tab(2, () => ScheduleScreen(onAnimeClick: _openDetail)),
              _tab(
                3,
                () => CuplixScreen(
                  isTabActive: _index == 3,
                  onWatchAnime: _openPlayer,
                ),
              ),
              _tab(
                4,
                () => ProfileScreen(
                  onAnimeClick: _openDetail,
                  onWatchEpisode: _openPlayer,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FloatingBottomBar(currentIndex: _index, onTabSelected: _goTab),
          ),
        ],
      ),
    );
  }
}

/// Satu tab di dalam Stack: state tetap terjaga (maintainState) dan perpindahan
/// memakai fade-through. Tab lama memudar cepat, tab baru fade-in sambil
/// bergeser halus sesuai arah perpindahan.
class _AnimatedTab extends StatefulWidget {
  const _AnimatedTab({
    required this.active,
    required this.direction,
    required this.child,
  });

  final bool active;
  final int direction;
  final Widget child;

  @override
  State<_AnimatedTab> createState() => _AnimatedTabState();
}

class _AnimatedTabState extends State<_AnimatedTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.active ? 1.0 : 0.0,
  )..addStatusListener((_) {
      if (mounted) setState(() {});
    });

  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    // Masuk: tunggu tab lama memudar dulu (35% awal), lalu muncul.
    curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
    // Keluar: memudar cepat di awal.
    reverseCurve: const Interval(0.65, 1.0, curve: Curves.easeInCubic),
  );

  @override
  void didUpdateWidget(_AnimatedTab old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      widget.active ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = !widget.active && _c.isDismissed;
    final dir = widget.active ? widget.direction : -widget.direction;
    return Visibility(
      visible: !hidden,
      maintainState: true,
      child: IgnorePointer(
        ignoring: !widget.active,
        child: RepaintBoundary(
          child: FadeTransition(
            opacity: _curve,
            child: AnimatedBuilder(
              animation: _curve,
              child: widget.child,
              builder: (context, child) => FractionalTranslation(
                translation: Offset(dir * 0.05 * (1 - _curve.value), 0),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
