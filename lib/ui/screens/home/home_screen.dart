import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_config.dart';
import '../../../core/remote_config_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/anime_item.dart';
import '../../../data/models/home_sections.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../xp/xp_leaderboard_screen.dart';
import '../../components/cards.dart';
import '../../components/chat_ticker.dart';
import '../../components/common_components.dart';
import '../../components/hero_banner.dart';
import '../../components/home_profile_header.dart';
import '../../components/shimmer.dart';
import '../../components/staggered_section.dart';
import '../../components/home_section_cards.dart';
import 'home_controller.dart';

/// Port HomeScreen.kt.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onAnimeClick,
    required this.onWatchEpisode,
    required this.onSearchClick,
    required this.onSeeAllClick,
    required this.onProfileClick,
    required this.onCuplixClick,
  });

  final ValueChanged<String> onAnimeClick;
  final void Function(String movieId, String episodeId) onWatchEpisode;
  final VoidCallback onSearchClick;
  final ValueChanged<String> onSeeAllClick;

  /// Ketuk klip / "Lihat semua" di section Cuplix: buka tab Cuplix.
  final VoidCallback onCuplixClick;

  /// Ketuk kartu profil / chip Premium / chip ZCoin / tombol Premium: buka tab Profil.
  final VoidCallback onProfileClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeControllerProvider);

    final Widget body;
    if (state.isLoading && !state.hasValue) {
      body = const _HomeLoadingSkeleton(key: ValueKey('loading'));
    } else if (state.hasError && !state.hasValue) {
      body = Center(
        key: const ValueKey('error'),
        child: ErrorState(
          message: _cleanError(state.error),
          onRetry: () async {
            // Paksa ambil api_base_url terbaru dulu (kalau baru di-Publish).
            await RemoteConfigManager.forceRefresh();
            ref.read(homeControllerProvider.notifier).loadHomeData(forceRefresh: true);
          },
        ),
      );
    } else if (state.isLoading) {
      // Muat ulang paksa: tampil skeleton lagi seperti HomeUiState.Loading
      body = const _HomeLoadingSkeleton(key: ValueKey('loading'));
    } else {
      body = _HomeContent(
        key: const ValueKey('content'),
        sections: state.requireValue,
        onAnimeClick: onAnimeClick,
        onWatchEpisode: onWatchEpisode,
        onSearchClick: onSearchClick,
        onSeeAllClick: onSeeAllClick,
        onProfileClick: onProfileClick,
        onCuplixClick: onCuplixClick,
      );
    }

    return ColoredBox(
      color: AppColors.backgroundDark,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: body,
      ),
    );
  }

  static String _cleanError(Object? e) {
    final s = e?.toString() ?? 'Gagal memuat data beranda';
    return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
  }
}

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({
    super.key,
    required this.sections,
    required this.onAnimeClick,
    required this.onWatchEpisode,
    required this.onSearchClick,
    required this.onSeeAllClick,
    required this.onProfileClick,
    required this.onCuplixClick,
  });

  final HomeSectionData sections;
  final ValueChanged<String> onAnimeClick;
  final void Function(String movieId, String episodeId) onWatchEpisode;
  final VoidCallback onSearchClick;
  final ValueChanged<String> onSeeAllClick;
  final VoidCallback onProfileClick;
  final VoidCallback onCuplixClick;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  final ScrollController _scroll = ScrollController();
  bool _animateSections = false;
  bool _isScrolled = false;
  Timer? _enterTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _enterTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _animateSections = true);
    });
  }

  void _onScroll() {
    final scrolled = _scroll.hasClients && _scroll.offset > 40;
    if (scrolled != _isScrolled) setState(() => _isScrolled = scrolled);
  }

  @override
  void dispose() {
    _enterTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Widget _posterRow(
    List<AnimeItem> list, {
    Map<String, String> episodeLabels = const {},
    bool showNewBadge = false,
  }) {
    return SizedBox(
      height: _rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final anime = list[i];
          return Align(
            alignment: Alignment.topCenter,
            child: AnimePosterCard(
              anime: anime,
              episodeLabel: episodeLabels[anime.id],
              showNewBadge: showNewBadge,
              onTap: () {
                final id = anime.id;
                if (id != null) widget.onAnimeClick(id);
              },
            ),
          );
        },
      ),
    );
  }

  // 140 lebar -> poster 210 + judul 2 baris + subteks; beri ruang cukup.
  static const double _rowHeight = 290;

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    final history = ref.watch(localStoreProvider.select((s) => s.history));
    final cuplixClips = ref.watch(homeCuplixProvider).valueOrNull ?? const [];
    final user = ref.watch(authUserProvider).valueOrNull;
    final showProfileHeader = user != null && FirebaseConfig.ready;

    Widget section({
      required int delayMs,
      required String title,
      required Widget child,
      String? actionText,
      VoidCallback? onAction,
      bool gapAfterHeader = true,
    }) {
      return StaggeredSection(
        visible: _animateSections,
        delayMs: delayMs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            SectionHeader(title: title, actionText: actionText, onActionClick: onAction),
            if (gapAfterHeader) const SizedBox(height: 8),
            child,
          ],
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 135),
      children: [
        // Header: nama app + tombol cari
        SafeArea(
          bottom: false,
          child: Opacity(
            opacity: _isScrolled ? 0.94 : 1.0,
            // Sudah login: kartu profil ala Zenime. Belum login: header lama
            // (logo + tombol cari).
            child: showProfileHeader
                ? HomeProfileHeader(
                    user: user!,
                    onSearchClick: widget.onSearchClick,
                    onProfileClick: widget.onProfileClick,
                    onPremiumClick: () => openPremium(context),
                    onCoinClick: () => openCoin(context),
                    onShieldClick: () => Navigator.of(context)
                        .push<void>(fadeRoute(const XpLeaderboardScreen())),
                  )
                : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Zen',
                            style: TextStyle(
                              color: AppColors.textWhite,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'ime',
                            style: TextStyle(
                              color: AppColors.accentViolet,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Streaming Anime Tanpa Batas',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: widget.onSearchClick,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: AppShapes.card,
                      ),
                      child: const Icon(Icons.search, color: AppColors.textWhite, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 1. Hero carousel
        if (sections.slider.isNotEmpty)
          StaggeredSection(
            visible: _animateSections,
            delayMs: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: HeroBanner(
                sliderItems: sections.slider,
                topXp: ref.watch(heroTopXpProvider).valueOrNull ?? const [],
                topClans: ref.watch(heroTopClansProvider).valueOrNull ?? const [],
                topSupport: ref.watch(topSupportersProvider).valueOrNull ?? const [],
                onLeaderboardClick: () => Navigator.of(context)
                    .push<void>(fadeRoute(const XpLeaderboardScreen())),
                onItemClick: (item) {
                  final id = item.id;
                  if (id != null) widget.onAnimeClick(id);
                },
              ),
            ),
          ),

        // Chat global terbaru (bergeser otomatis), di bawah hero
        StaggeredSection(
          visible: _animateSections,
          delayMs: 120,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ChatTicker(),
          ),
        ),

        // Lanjutkan Menonton: tepat di bawah chat global
        if (history.isNotEmpty)
          section(
            delayMs: 140,
            title: 'Lanjutkan Menonton',
            child: SizedBox(
              height: 124 + 8 + 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: history.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final h = history[i];
                  final lower = h.episodeTitle.toLowerCase();
                  final epLabel = (lower.contains('episode') || lower.contains('ep'))
                      ? h.episodeTitle
                      : 'Episode ${h.episodeIndex}';
                  final percent = (h.progressFraction * 100).toInt();
                  final progressLabel = percent > 0 ? '$epLabel • $percent%' : epLabel;
                  return ContinueWatchingCard(
                    title: h.movieTitle,
                    episodeText: progressLabel,
                    posterUrl: h.moviePoster,
                    progress: h.progressFraction,
                    onTap: () => widget.onWatchEpisode(h.movieId, h.episodeId),
                  );
                },
              ),
            ),
          ),

        // Urutan section mengikuti Beranda Zenime.

        // 2. Cuplix
        if (cuplixClips.isNotEmpty)
          section(
            delayMs: 150,
            title: 'Cuplix',
            actionText: 'Lihat semua',
            onAction: widget.onCuplixClick,
            child: CuplixThumbRow(clips: cuplixClips, onClipClick: widget.onCuplixClick),
          ),

        // 3. Episode Baru (data/home/list -> update) + label nomor episode
        if (sections.update.isNotEmpty)
          section(
            delayMs: 180,
            title: 'Episode Baru',
            child: _posterRow(sections.update, episodeLabels: sections.updateLabels),
          ),

        // 4. Sedang Hangat (hot) - kartu cover 16:9
        if (sections.hot.isNotEmpty)
          section(
            delayMs: 220,
            title: 'Sedang Hangat',
            actionText: 'Lihat semua',
            onAction: () => widget.onSeeAllClick('hot'),
            child: AnimeCoverBannerRow(
              items: sections.hot,
              onAnimeClick: widget.onAnimeClick,
            ),
          ),

        // 5. Jadwal Hari Ini
        if (sections.today.isNotEmpty)
          section(
            delayMs: 260,
            title: 'Jadwal Hari Ini',
            child: _posterRow(sections.today),
          ),

        // 6. Judul Baru (new) + badge "New"
        if (sections.newRelease.isNotEmpty)
          section(
            delayMs: 300,
            title: 'Judul Baru',
            child: _posterRow(sections.newRelease, showNewBadge: true),
          ),

        // 7. Terpopuler - kartu berperingkat
        if (sections.popular.isNotEmpty)
          section(
            delayMs: 340,
            title: 'Terpopuler',
            child: AnimeRankedRow(
              items: sections.popular,
              onAnimeClick: widget.onAnimeClick,
            ),
          ),

        // 8. Jas Por Yu (random) - kartu cover 16:9
        if (sections.random.isNotEmpty)
          section(
            delayMs: 380,
            title: 'Jas Por Yu',
            child: AnimeCoverBannerRow(
              items: sections.random,
              onAnimeClick: widget.onAnimeClick,
            ),
          ),

        // 9. Paling Dinanti (waiting)
        if (sections.waiting.isNotEmpty)
          section(
            delayMs: 420,
            title: 'Paling Dinanti',
            child: _posterRow(sections.waiting),
          ),
      ],
    );
  }
}

class _HomeLoadingSkeleton extends StatelessWidget {
  const _HomeLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: HeroBannerSkeleton(),
            ),
            SizedBox(height: 24),
            AnimeRowSkeleton(),
            SizedBox(height: 24),
            AnimeRowSkeleton(),
          ],
        ),
      ),
    );
  }
}
