import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/anime_item.dart';
import '../../data/models/support_models.dart';
import '../../data/models/xp_models.dart';
import 'hero_slides.dart';
import 'net_image.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;
bool _isNone(String? s) => s != null && s.toLowerCase() == 'none';

/// Port HeroBanner.kt: carousel 220dp, auto-slide 5 dtk (jeda saat disentuh),
/// parallax + Ken Burns, chip tipe/tahun/genre, tombol play berdenyut,
/// indikator pill yang melebar.
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.sliderItems,
    required this.onItemClick,
    this.topXp = const [],
    this.topSupport = const [],
    this.onLeaderboardClick,
  });

  final List<AnimeItem> sliderItems;
  final ValueChanged<AnimeItem> onItemClick;

  /// Slide tambahan setelah semua slide anime (kosong = slide tidak ada).
  final List<UserXpDisplay> topXp;
  final List<TopSupporter> topSupport;
  final VoidCallback? onLeaderboardClick;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> with SingleTickerProviderStateMixin {
  final PageController _pager = PageController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  Timer? _autoTimer;
  Timer? _resumeTimer;
  bool _interacting = false;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _startAuto();
  }

  void _startAuto() {
    _autoTimer?.cancel();
    if (widget.sliderItems.length <= 1) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _interacting || !_pager.hasClients) return;
      // Rotasi otomatis berhenti selama user ada di slide leaderboard/support.
      if (_current >= widget.sliderItems.length) return;
      final next = (_current + 1) % widget.sliderItems.length;
      _pager.animateToPage(
        next,
        duration: const Duration(milliseconds: 650),
        curve: Curves.fastOutSlowIn,
      );
    });
  }

  @override
  void didUpdateWidget(HeroBanner old) {
    super.didUpdateWidget(old);
    if (old.sliderItems.length != widget.sliderItems.length) {
      _startAuto();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _resumeTimer?.cancel();
    _pulse.dispose();
    _pager.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _resumeTimer?.cancel();
      _interacting = true;
    } else if (n is ScrollEndNotification && _interacting) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(seconds: 4), () {
        _interacting = false;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.sliderItems;
    if (items.isEmpty) return const SizedBox.shrink();

    final lbPage = widget.topXp.isNotEmpty ? items.length : -1;
    final supportPage =
        widget.topSupport.isNotEmpty ? items.length + (lbPage >= 0 ? 1 : 0) : -1;
    final pageCount = items.length + (lbPage >= 0 ? 1 : 0) + (supportPage >= 0 ? 1 : 0);

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
                  itemCount: pageCount,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, page) {
                    if (page == lbPage) {
                      return HeroLeaderboardSlide(
                        entries: widget.topXp,
                        onTap: widget.onLeaderboardClick ?? () {},
                      );
                    }
                    if (page == supportPage) {
                      return HeroSupportSlide(supporters: widget.topSupport);
                    }
                    return AnimatedBuilder(
                      animation: _pager,
                      builder: (context, _) {
                        double pageValue = _current.toDouble();
                        if (_pager.hasClients && _pager.position.haveDimensions) {
                          pageValue = _pager.page ?? pageValue;
                        }
                        return _HeroPage(
                          anime: items[page],
                          isCurrent: _current == page,
                          pageOffset: (pageValue - page).abs(),
                          pulse: _pulse,
                          onClick: () => widget.onItemClick(items[page]),
                        );
                      },
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    width: i == _current ? 22 : 6,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i == _current
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
            ],
          ),
        ],
      ],
    );
  }
}

class _HeroPage extends StatefulWidget {
  const _HeroPage({
    required this.anime,
    required this.isCurrent,
    required this.pageOffset,
    required this.pulse,
    required this.onClick,
  });

  final AnimeItem anime;
  final bool isCurrent;
  final double pageOffset;
  final Animation<double> pulse;
  final VoidCallback onClick;

  @override
  State<_HeroPage> createState() => _HeroPageState();
}

class _HeroPageState extends State<_HeroPage> {
  bool _showMeta = false;
  bool _playPressed = false;
  Timer? _metaTimer;

  @override
  void initState() {
    super.initState();
    _syncMeta();
  }

  @override
  void didUpdateWidget(_HeroPage old) {
    super.didUpdateWidget(old);
    if (old.isCurrent != widget.isCurrent) _syncMeta();
  }

  void _syncMeta() {
    _metaTimer?.cancel();
    if (widget.isCurrent) {
      _metaTimer = Timer(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _showMeta = true);
      });
    } else {
      _showMeta = false;
    }
  }

  @override
  void dispose() {
    _metaTimer?.cancel();
    super.dispose();
  }

  Widget _chip(String text, Color bg, Color fg, FontWeight w) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 10, fontWeight: w)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    // Cover dulu, fallback ke poster
    final imageUrl = !_blank(anime.imageCover) ? anime.coverUrl : anime.posterUrl;

    final genres = (anime.genre ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_isNone(e))
        .take(3)
        .toList();

    final title = anime.title;
    final displayTitle =
        (!_blank(title) && !_isNone(title) && title!.toLowerCase() != 'anime') ? title : '';

    return GestureDetector(
      onTap: widget.onClick,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Gambar dengan parallax + Ken Burns
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.isCurrent ? 1.06 : 1.0),
            duration: const Duration(milliseconds: 4500),
            curve: Curves.linear,
            builder: (context, scale, child) {
              return Transform.translate(
                offset: Offset(widget.pageOffset * 40 / dpr, 0),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: NetImage(imageUrl),
          ),
          // Gradien sinematik atas -> bawah
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x111E1B2E),
                  Color(0x551E1B2E),
                  Color(0xDD1E1B2E),
                  Color(0xFF1E1B2E),
                ],
              ),
            ),
          ),
          // Vinyet kiri
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 400 / dpr,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xAA1E1B2E), Colors.transparent],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
          // Teks: chip + judul
          Align(
            alignment: Alignment.bottomLeft,
            child: FractionallySizedBox(
              widthFactor: 0.72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedOpacity(
                      opacity: _showMeta ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: AnimatedSlide(
                        offset: _showMeta ? Offset.zero : const Offset(0, 0.5),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (!_blank(anime.type) && !_isNone(anime.type))
                              _chip(
                                anime.type!,
                                AppColors.accentViolet.withValues(alpha: 0.25),
                                AppColors.accentViolet,
                                FontWeight.w700,
                              ),
                            if (!_blank(anime.year) && !_isNone(anime.year))
                              _chip(
                                anime.year!,
                                AppColors.surfaceDark.withValues(alpha: 0.6),
                                AppColors.textSecondary,
                                FontWeight.w500,
                              ),
                            for (final g in genres)
                              _chip(
                                g,
                                AppColors.surfaceDark.withValues(alpha: 0.7),
                                AppColors.textWhite,
                                FontWeight.w500,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (displayTitle.isNotEmpty)
                      Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 22 / 17,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Tombol play berdenyut
          Positioned(
            right: 16,
            bottom: 16,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _playPressed = true),
              onTapUp: (_) => setState(() => _playPressed = false),
              onTapCancel: () => setState(() => _playPressed = false),
              onTap: widget.onClick,
              child: AnimatedBuilder(
                animation: widget.pulse,
                builder: (context, child) {
                  final pulseScale =
                      1.0 + 0.06 * Curves.fastOutSlowIn.transform(widget.pulse.value);
                  return Transform.scale(
                    scale: _playPressed ? 0.94 : pulseScale,
                    child: child,
                  );
                },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: AppColors.accentViolet,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: AppColors.textWhite, size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
