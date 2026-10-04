import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
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
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// Tab dibuat saat pertama kali dibuka (seperti NavHost), supaya Jelajah,
  /// Jadwal, dan Cuplix tidak memanggil API sebelum dikunjungi.
  final Set<int> _visited = {0};

  void _goTab(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  Widget _tab(int i, Widget Function() build) =>
      _visited.contains(i) ? build() : const SizedBox.shrink();

  void _openDetail(String movieId) => openDetail(context, movieId);

  void _openPlayer(String movieId, String episodeId) =>
      openPlayer(context, movieId, episodeId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              HomeScreen(
                onAnimeClick: _openDetail,
                onWatchEpisode: _openPlayer,
                onSearchClick: () => _goTab(1),
                onSeeAllClick: (_) => _goTab(1),
              ),
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
