import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../app_routes.dart';
import '../components/floating_bottom_bar.dart';
import '../screens/home/home_screen.dart';

/// Port AppNavigation.kt (tahap 1): 5 tab + bottom bar melayang.
/// Detail dan Player sudah jadi; tab Jelajah, Jadwal, Cuplix, Profil menyusul
/// (sementara placeholder).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _goTab(int i) => setState(() => _index = i);

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
              const _PlaceholderTab(title: 'Jelajah'),
              const _PlaceholderTab(title: 'Jadwal'),
              const _PlaceholderTab(title: 'Cuplix'),
              const _PlaceholderTab(title: 'Profil'),
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

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title\n(segera hadir)',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
    );
  }
}
