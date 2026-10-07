import 'package:flutter/material.dart';

import 'screens/detail/detail_screen.dart';
import 'screens/donghua/donghua_detail_screen.dart';
import 'screens/donghua/donghua_player_screen.dart';
import 'screens/donghua/donghua_premium_gate.dart';
import 'screens/donghua/donghua_screen.dart';
import 'screens/player/player_screen.dart';
import 'screens/store/coin_screen.dart';
import 'screens/store/premium_screen.dart';

/// Transisi layar: layar baru fade + geser halus dari kanan (easeOutCubic),
/// saat kembali kebalikannya. Layar di bawahnya ikut bergeser sedikit ke kiri
/// (parallax) supaya terasa menyatu, bukan sekadar ganti layar.
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondary) => page,
    transitionsBuilder: (context, animation, secondary, child) {
      final enter = CurveTween(curve: Curves.easeOutCubic);
      final exit = CurveTween(curve: Curves.easeInCubic);

      // Masuk: geser dari kanan 8% lebar layar + fade.
      final slideIn = Tween<Offset>(
        begin: const Offset(0.08, 0),
        end: Offset.zero,
      ).chain(enter);
      final fadeIn = Tween<double>(begin: 0, end: 1).chain(enter);

      // Layar ini tertimpa layar lain: geser sedikit ke kiri.
      final slideAway = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.04, 0),
      ).chain(exit);

      return SlideTransition(
        position: secondary.drive(slideAway),
        child: FadeTransition(
          opacity: animation.drive(fadeIn),
          child: SlideTransition(
            position: animation.drive(slideIn),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Kunci Navigator root: dipakai mini player (di luar Navigator) untuk membuka
/// kembali PlayerScreen. Dipasang di MaterialApp (main.dart).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void _pushDetail(NavigatorState nav, String movieId) {
  nav.push(
    fadeRoute(
      DetailScreen(
        movieId: movieId,
        onBackClick: () => nav.maybePop(),
        onWatchEpisode: (mId, epId) => _pushPlayer(nav, mId, epId),
      ),
    ),
  );
}

void _pushPlayer(NavigatorState nav, String movieId, String episodeId) {
  nav.push(
    fadeRoute(
      PlayerScreen(
        movieId: movieId,
        episodeId: episodeId,
        onBackClick: () => nav.maybePop(),
        onAnimeClick: (nextMovieId) => _pushDetail(nav, nextMovieId),
      ),
    ),
  );
}

/// Port Screen.Detail: detail/{movieId}.
void openDetail(BuildContext context, String movieId) =>
    _pushDetail(Navigator.of(context), movieId);

/// Port Screen.Player: player/{movieId}/{episodeId}.
void openPlayer(BuildContext context, String movieId, String episodeId) =>
    _pushPlayer(Navigator.of(context), movieId, episodeId);

/// Dari kartu mini player: buka player penuh untuk episode yang sama.
void openPlayerFromMini(String movieId, String episodeId) {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  _pushPlayer(nav, movieId, episodeId);
}

// ---------------------------------------------------------------- Donghua

/// Port Screen.Donghua / DonghuaDetail / DonghuaPlayer (NavGraph.kt).
void _pushDonghua(NavigatorState nav) {
  nav.push(
    fadeRoute(
      DonghuaScreen(
        onBackClick: () => nav.maybePop(),
        onDonghuaClick: (slug) => _pushDonghuaDetail(nav, slug),
      ),
    ),
  );
}

void _pushDonghuaDetail(NavigatorState nav, String slug) {
  nav.push(
    fadeRoute(
      DonghuaDetailScreen(
        slug: slug,
        onBackClick: () => nav.maybePop(),
        onEpisodeClick: (episodeSlug) => _pushDonghuaPlayer(nav, episodeSlug),
      ),
    ),
  );
}

/// Player donghua dibungkus gate Premium. Ganti episode dari dalam player
/// MENGGANTI layar player (bukan menumpuk), seperti popUpTo inclusive di Zenime.
void _pushDonghuaPlayer(NavigatorState nav, String slug, {bool replace = false}) {
  void upgrade() => nav.push(fadeRoute(const PremiumScreen()));
  final route = fadeRoute<void>(
    DonghuaPremiumGate(
      onBackClick: () => nav.maybePop(),
      onUpgradeClick: upgrade,
      child: DonghuaPlayerScreen(
        slug: slug,
        onBackClick: () => nav.maybePop(),
        onEpisodeChange: (next) => _pushDonghuaPlayer(nav, next, replace: true),
        onUpgradeClick: upgrade,
      ),
    ),
  );
  if (replace) {
    nav.pushReplacement(route);
  } else {
    nav.push(route);
  }
}

/// Halaman daftar Donghua (dari section Donghua di Beranda).
void openDonghua(BuildContext context) => _pushDonghua(Navigator.of(context));

/// Detail donghua. [slug] boleh slug anime maupun slug episode.
void openDonghuaDetail(BuildContext context, String slug) =>
    _pushDonghuaDetail(Navigator.of(context), slug);

/// Halaman beli Premium.
void openPremium(BuildContext context) {
  Navigator.of(context).push(fadeRoute(const PremiumScreen()));
}

/// Halaman top up ZCoin.
void openCoin(BuildContext context) {
  Navigator.of(context).push(fadeRoute(const CoinScreen()));
}
