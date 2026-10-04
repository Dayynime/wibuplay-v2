import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../components/floating_bottom_bar.dart';
import '../screens/home/home_screen.dart';

/// Port AppNavigation.kt (tahap 1): 5 tab + bottom bar melayang.
/// Layar lain (Jelajah, Jadwal, Cuplix, Profil, Detail, Player) menyusul;
/// sementara memakai placeholder supaya navigasinya sudah bisa dicoba.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _goTab(int i) => setState(() => _index = i);

  void _openDetail(String movieId) {
    Navigator.of(context).push(_fadeRoute(_PlaceholderPage(title: 'Detail #$movieId')));
  }

  void _openPlayer(String movieId, String episodeId) {
    Navigator.of(context).push(
      _fadeRoute(_PlaceholderPage(title: 'Player #$movieId / $episodeId')),
    );
  }

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

Route<T> _fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondary) => page,
    transitionsBuilder: (context, animation, secondary, child) =>
        FadeTransition(opacity: animation, child: child),
  );
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

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        title: Text(title, style: const TextStyle(fontSize: 14)),
      ),
      body: const Center(
        child: Text(
          'Segera hadir',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ),
    );
  }
}
