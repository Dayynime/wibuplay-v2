import 'package:flutter/material.dart';

import 'screens/detail/detail_screen.dart';
import 'screens/player/player_screen.dart';
import 'screens/store/coin_screen.dart';
import 'screens/store/premium_screen.dart';

/// Transisi layar: layar baru fade-in 300ms, saat kembali fade-out 300ms
/// (port enterTransition/popExitTransition di AppNavigation.kt).
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondary) => page,
    transitionsBuilder: (context, animation, secondary, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Port Screen.Detail: detail/{movieId}.
void openDetail(BuildContext context, String movieId) {
  Navigator.of(context).push(
    fadeRoute(
      DetailScreen(
        movieId: movieId,
        onBackClick: () => Navigator.of(context).maybePop(),
        onWatchEpisode: (mId, epId) => openPlayer(context, mId, epId),
      ),
    ),
  );
}

/// Port Screen.Player: player/{movieId}/{episodeId}.
void openPlayer(BuildContext context, String movieId, String episodeId) {
  Navigator.of(context).push(
    fadeRoute(
      PlayerScreen(
        movieId: movieId,
        episodeId: episodeId,
        onBackClick: () => Navigator.of(context).maybePop(),
        onAnimeClick: (nextMovieId) => openDetail(context, nextMovieId),
      ),
    ),
  );
}

/// Halaman beli Premium.
void openPremium(BuildContext context) {
  Navigator.of(context).push(fadeRoute(const PremiumScreen()));
}

/// Halaman top up ZCoin.
void openCoin(BuildContext context) {
  Navigator.of(context).push(fadeRoute(const CoinScreen()));
}
