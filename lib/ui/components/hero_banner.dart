import 'package:cached_network_image/cached_network_image.dart';
import '../../core/image_cache.dart';
import '../../core/lite_mode.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/anime_item.dart';
import '../../data/models/clan_models.dart';
import '../../data/models/support_models.dart';
import '../../data/models/xp_models.dart';
import 'hero_slides.dart';
import 'net_image.dart';
import '../redesign/z_kit.dart';

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
    this.onClanLeaderboardClick,
    this.onSupportClick,
    this.topGivers = const [],
    this.giverClanTags = const {},
    this.onGiverClick,
  });

  final List<AnimeItem> sliderItems;
  final ValueChanged<AnimeItem> onItemClick;

  /// Slide tambahan setelah slide anime (kosong = slide tidak ada).
  final List<UserXpDisplay> topXp;
  final List<ClanSummary> topClans;
  final List<TopSupporter> topSupport;
  final VoidCallback? onLeaderboardClick;
  final VoidCallback? onClanLeaderboardClick;

  /// Tap slide Top Support (buka halaman Top Support).
  final VoidCallback? onSupportClick;

  /// Slide Top Giver (kosong = slide tidak ada).
  final List<TopGiver> topGivers;
  final Map<String, String> giverClanTags;
  final VoidCallback? onGiverClick;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> with SingleTickerProviderStateMixin {
  final PageController _pager = PageController();
  int _page = 0;
  int _animeIndex = 0;
  bool _scrolling = false;

  /// Jam rotasi poster anime. Nilainya (0..1) sekaligus mengisi bar progres
  /// pertama, jadi indikator selalu sinkron dengan pergantian poster.
  late final AnimationController _rotation =
      AnimationController(vsync: this, duration: _rotateEvery)
        ..addStatusListener(_onRotationDone);

  @override
  void initState() {
    super.initState();
    _rotation.forward();
  }

  void _onRotationDone(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _tick();
    if (_page == 0) _rotation.forward(from: 0);
  }

  void _tick() {
    final n = widget.sliderItems.length;
    if (!mounted || n <= 1 || _page != 0 || _scrolling) return;
    setState(() => _animeIndex = (_animeIndex + 1) % n);
    _preloadNext();
  }

  void _onPageChanged(int i) {
    setState(() => _page = i);
    if (i == 0) {
      _rotation.forward(from: 0);
    } else {
      _rotation.stop();
    }
  }

  /// Preload gambar berikutnya supaya crossfade-nya tidak muncul kosong dulu.
  void _preloadNext() {
    final items = widget.sliderItems;
    if (items.length <= 1) return;
    final next = items[(_animeIndex + 1) % items.length];
    final url = next.coverUrl;
    if (url.isEmpty) return;
    precacheImage(
      ResizeImage.resizeIfNeeded(
        LiteMode.px(context, MediaQuery.sizeOf(context).width),
        null,
        CachedNetworkImageProvider(url, cacheManager: AppImageCache.images, headers: netImageHeaders),
      ),
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
    _rotation.dispose();
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
    // Urutan slide: poster anime -> Top Giver -> Top Leaderboard -> Top Support.
    var next = 1;
    final giverPage = widget.topGivers.isNotEmpty ? next++ : -1;
    final lbPage = hasLeaderboard ? next++ : -1;
    final supportPage = widget.topSupport.isNotEmpty ? next++ : -1;
    final pageCount = next;

    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: AppShapes.card,
        child: ColoredBox(
          color: AppColors.surfaceCard,
          child: Stack(
            children: [
              Positioned.fill(
                child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: PageView.builder(
                  controller: _pager,
                  physics: pageCount > 1
                      ? const PageScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: pageCount,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, page) {
                    if (page == lbPage) {
                      return _SlideHost(
                        controller: _pager,
                        index: page,
                        builder: (context, active, offset) => HeroLeaderboardSlide(
                          entries: widget.topXp,
                          clans: widget.topClans,
                          onTap: widget.onLeaderboardClick ?? () {},
                          onClanTap: widget.onClanLeaderboardClick,
                          active: active,
                          pageOffset: offset,
                        ),
                      );
                    }
                    if (page == supportPage) {
                      return _SlideHost(
                        controller: _pager,
                        index: page,
                        builder: (context, active, offset) => HeroSupportSlide(
                          supporters: widget.topSupport,
                          onTap: widget.onSupportClick,
                          active: active,
                          pageOffset: offset,
                        ),
                      );
                    }
                    if (page == giverPage) {
                      return _SlideHost(
                        controller: _pager,
                        index: page,
                        builder: (context, active, offset) => HeroGiverSlide(
                          givers: widget.topGivers,
                          clanTags: widget.giverClanTags,
                          onTap: widget.onGiverClick,
                          active: active,
                          pageOffset: offset,
                        ),
                      );
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
              // Indikator titik (gaya preview): titik aktif memanjang.
              if (pageCount > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pageCount; i++)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _pager.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 6),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              width: i == _page ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _page ? Colors.white : const Color(0x59FFFFFF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pembungkus slide leaderboard/support: memberi tahu slide kapan ia kelihatan
/// ([active] = mulai ada di layar sampai benar-benar keluar) dan seberapa jauh
/// ia dari tengah ([offset] -1..1) untuk efek parallax. Cuma [active] yang
/// memicu rebuild; [offset] lewat ValueNotifier supaya swipe tetap ringan.
class _SlideHost extends StatefulWidget {
  const _SlideHost({
    required this.controller,
    required this.index,
    required this.builder,
  });

  final PageController controller;
  final int index;
  final Widget Function(BuildContext context, bool active, ValueListenable<double> offset)
      builder;

  @override
  State<_SlideHost> createState() => _SlideHostState();
}

class _SlideHostState extends State<_SlideHost> {
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);
  bool _active = false;

  double _delta() {
    final c = widget.controller;
    final initial = c.initialPage.toDouble();
    final page = c.hasClients ? (c.page ?? initial) : initial;
    return (page - widget.index).clamp(-1.0, 1.0).toDouble();
  }

  @override
  void initState() {
    super.initState();
    final d = _delta();
    _offset.value = d;
    _active = d.abs() < 0.98;
    widget.controller.addListener(_onPage);
  }

  @override
  void didUpdateWidget(_SlideHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onPage);
      widget.controller.addListener(_onPage);
    }
    // Index slide bisa bergeser kalau data leaderboard/support datang belakangan.
    final d = _delta();
    _offset.value = d;
    _active = d.abs() < 0.98;
  }

  void _onPage() {
    // Pager kadang memberi notifikasi saat layout (mis. ganti ukuran layar):
    // tunda ke akhir frame supaya setState aman.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _apply();
      });
    } else {
      _apply();
    }
  }

  void _apply() {
    final d = _delta();
    _offset.value = d;
    final a = d.abs() < 0.98;
    if (a != _active) setState(() => _active = a);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPage);
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _active, _offset);
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
                stops: const [0, 0.25, 0.45, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  _heroInk.withValues(alpha: 0.35),
                  _heroInk.withValues(alpha: 0.96),
                ],
              ),
            ),
          ),
          // 5. Peringkat + judul (tengah bawah), naik pelan tiap ganti anime.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 170,
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
                onTap: onTap,
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

class _Caption extends StatelessWidget {
  const _Caption({super.key, required this.anime, required this.rank, required this.onTap});

  final AnimeItem anime;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = anime.title;
    final displayTitle =
        (!_blank(title) && !_isNone(title) && title!.toLowerCase() != 'anime')
            ? title!
            : 'Tanpa Judul';
    final status = (!_blank(anime.status) && !_isNone(anime.status)) ? anime.status! : null;
    final type = (!_blank(anime.type) && !_isNone(anime.type)) ? anime.type! : null;
    final ongoing = status != null && status.toLowerCase().contains('ongoing');

    // Gaya preview: rata kiri, baris chip, judul besar, tombol Tonton.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ZChip('#$rank', tone: ZTone.gold),
              if (status != null) ZChip(status, tone: ongoing ? ZTone.jade : ZTone.glass, live: ongoing),
              if (type != null) ZChip(type),
              if (!_blank(anime.views)) ZChip('${anime.views}', icon: Icons.visibility_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ZFont.display(size: 22, height: 1.15),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.accentViolet,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Tonton',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
