import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/anime_item.dart';
import '../../data/models/clan_models.dart';
import '../../data/models/support_models.dart';
import '../../data/models/xp_models.dart';
import 'hero_slides.dart';
import 'net_image.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;
bool _isNone(String? s) => s != null && s.toLowerCase() == 'none';

const Color _heroInk = Color(0xFF0B0E14);
const Duration _rotateEvery = Duration(milliseconds: 4500);

/// Hero carousel gaya "Poster Otomatis" (port FullBleedHeroBannerCarousel di
/// HomeScreen.kt, Zenime).
///
/// Pager luar cuma punya slide: (1) SATU kartu anime yang gambarnya ganti
/// sendiri (crossfade + zoom pelan, peringkat & judul ikut beranimasi),
/// (2) Top Leaderboard, (3) Top Support. Rotasi anime berhenti selama user
/// lagi geser atau sedang di slide leaderboard/support.
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.sliderItems,
    required this.onItemClick,
    this.topXp = const [],
    this.topClans = const [],
    this.topSupport = const [],
    this.onLeaderboardClick,
  });

  final List<AnimeItem> sliderItems;
  final ValueChanged<AnimeItem> onItemClick;

  /// Slide tambahan setelah slide anime (kosong = slide tidak ada).
  final List<UserXpDisplay> topXp;
  final List<ClanSummary> topClans;
  final List<TopSupporter> topSupport;
  final VoidCallback? onLeaderboardClick;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final PageController _pager = PageController();
  Timer? _timer;
  int _page = 0;
  int _animeIndex = 0;
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_rotateEvery, (_) => _tick());
  }

  void _tick() {
    final n = widget.sliderItems.length;
    if (!mounted || n <= 1 || _page != 0 || _scrolling) return;
    setState(() => _animeIndex = (_animeIndex + 1) % n);
    _preloadNext();
  }

  /// Preload gambar berikutnya supaya crossfade-nya tidak muncul kosong dulu.
  void _preloadNext() {
    final items = widget.sliderItems;
    if (items.length <= 1) return;
    final next = items[(_animeIndex + 1) % items.length];
    final url = next.coverUrl;
    if (url.isEmpty) return;
    precacheImage(
      CachedNetworkImageProvider(url, headers: netImageHeaders),
      context,
      onError: (_, __) {},
    );
  }

  @override
  void didUpdateWidget(HeroBanner old) {
    super.didUpdateWidget(old);
    // Jaga-jaga kalau jumlah item berkurang (mis. ganti sumber banner).
    if (_animeIndex >= widget.sliderItems.length) _animeIndex = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pager.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _scrolling = true;
    } else if (n is ScrollEndNotification) {
      _scrolling = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.sliderItems;
    if (items.isEmpty) return const SizedBox.shrink();
    final index = _animeIndex < items.length ? _animeIndex : 0;

    final hasLeaderboard = widget.topXp.isNotEmpty || widget.topClans.isNotEmpty;
    final lbPage = hasLeaderboard ? 1 : -1;
    final supportPage = widget.topSupport.isNotEmpty ? 1 + (hasLeaderboard ? 1 : 0) : -1;
    final pageCount = 1 + (hasLeaderboard ? 1 : 0) + (widget.topSupport.isNotEmpty ? 1 : 0);

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: AppShapes.card,
            child: ColoredBox(
              color: AppColors.surfaceCard,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: PageView.builder(
                  controller: _pager,
                  physics: pageCount > 1
                      ? const PageScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: pageCount,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, page) {
                    if (page == lbPage) {
                      return HeroLeaderboardSlide(
                        entries: widget.topXp,
                        clans: widget.topClans,
                        onTap: widget.onLeaderboardClick ?? () {},
                      );
                    }
                    if (page == supportPage) {
                      return HeroSupportSlide(supporters: widget.topSupport);
                    }
                    return _AutoPosterSlide(
                      items: items,
                      index: index,
                      onTap: () => widget.onItemClick(items[index]),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (pageCount > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pageCount; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pager.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutBack,
                      width: i == _page ? 22 : 6,
                      height: 5,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? (i == lbPage
                                ? heroGold
                                : i == supportPage
                                    ? heroPink
                                    : AppColors.accentViolet)
                            : (i == supportPage
                                ? heroPink.withValues(alpha: 0.4)
                                : AppColors.surfaceDark),
                        borderRadius: AppShapes.pill,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Slide anime: satu kartu, gambar ganti sendiri mengikuti [index]. Chip
/// views di kiri atas, indikator rotasi di kanan atas, peringkat + judul rata
/// tengah di bawah. Seluruh kartu bisa di-tap buat buka anime.
class _AutoPosterSlide extends StatelessWidget {
  const _AutoPosterSlide({
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<AnimeItem> items;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final anime = items[index];

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _heroInk),
          // 1. Gambar: crossfade antar anime + zoom pelan (Ken Burns).
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            child: _KenBurnsImage(
              key: ValueKey('hero_img_$index'),
              url: anime.coverUrl,
            ),
          ),
          // 2. Scrim: atas tipis (chip kebaca), bawah tebal (judul kebaca).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.28, 0.5, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  _heroInk.withValues(alpha: 0.35),
                  _heroInk.withValues(alpha: 0.96),
                ],
              ),
            ),
          ),
          // 3. Chip views (kiri atas).
          Positioned(
            left: 12,
            top: 12,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              reverseDuration: const Duration(milliseconds: 250),
              child: _blank(anime.views)
                  ? SizedBox.shrink(key: ValueKey('views_none_$index'))
                  : _ViewsChip(key: ValueKey('views_$index'), views: anime.views!),
            ),
          ),
          // 4. Indikator rotasi (kanan atas): ini poster ke berapa.
          if (items.length > 1)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: i == index ? 16 : 5,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: i == index ? 0.95 : 0.35),
                            borderRadius: AppShapes.pill,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // 5. Peringkat + judul (tengah bawah), naik pelan tiap ganti anime.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 124,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              reverseDuration: const Duration(milliseconds: 250),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.bottomCenter,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, anim) {
                // Yang masuk menunggu 200ms (0.4 dari 500ms) biar tidak
                // numpuk sama caption lama yang sedang memudar.
                final incoming = child.key == ValueKey('hero_caption_$index');
                final a = incoming
                    ? anim.drive(CurveTween(curve: const Interval(0.4, 1.0)))
                    : anim;
                return FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: a.drive(
                      Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero),
                    ),
                    child: child,
                  ),
                );
              },
              child: _Caption(
                key: ValueKey('hero_caption_$index'),
                anime: anime,
                rank: index + 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gambar hero dengan zoom pelan 1.0 -> 1.08 selama poster ini tampil.
class _KenBurnsImage extends StatelessWidget {
  const _KenBurnsImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1.0, end: 1.08),
      duration: _rotateEvery + const Duration(milliseconds: 700),
      curve: Curves.linear,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: SizedBox.expand(child: NetImage(url)),
    );
  }
}

class _ViewsChip extends StatelessWidget {
  const _ViewsChip({super.key, required this.views});

  final String views;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            '$views views',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({super.key, required this.anime, required this.rank});

  final AnimeItem anime;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final title = anime.title;
    final displayTitle =
        (!_blank(title) && !_isNone(title) && title!.toLowerCase() != 'anime')
            ? title!
            : 'Tanpa Judul';
    final meta = [anime.type, anime.status]
        .where((e) => !_blank(e) && !_isNone(e))
        .join(' \u2022 ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: heroGold.withValues(alpha: 0.35)),
            ),
            child: Text(
              '#$rank',
              style: const TextStyle(
                color: heroGold,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 26 / 20,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
