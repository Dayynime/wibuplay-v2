import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/anichin_models.dart';
import '../../components/common_components.dart';
import '../../components/shimmer.dart';
import 'donghua_controller.dart';
import 'donghua_widgets.dart';

/// Port DonghuaScreen.kt: daftar donghua (Terbaru / Ongoing / Semua), cari,
/// dan filter genre. Dibuka dari section "Donghua" di Beranda, bukan dari
/// bottom bar.
class DonghuaScreen extends ConsumerStatefulWidget {
  const DonghuaScreen({
    super.key,
    required this.onBackClick,
    required this.onDonghuaClick,
  });

  final VoidCallback onBackClick;
  final ValueChanged<String> onDonghuaClick;

  @override
  ConsumerState<DonghuaScreen> createState() => _DonghuaScreenState();
}

class _DonghuaScreenState extends ConsumerState<DonghuaScreen> {
  DonghuaTab _tab = DonghuaTab.latest;
  bool _searchOpen = false;
  final TextEditingController _search = TextEditingController();

  DonghuaController get _ctrl => ref.read(donghuaControllerProvider.notifier);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _search.clear();
    _ctrl.clearSearch();
    setState(() => _searchOpen = false);
  }

  void _selectTab(DonghuaTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _ctrl.onTabSelected(tab);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(donghuaControllerProvider);
    final filtering = ui.isFiltering;

    final Widget content;
    if (filtering) {
      content = _DonghuaGrid(
        key: ValueKey('filter-${ui.query}-${ui.selectedGenre?.slug}'),
        state: ui.filter,
        emptyTitle: 'Donghua Tidak Ditemukan',
        emptyDescription: 'Coba kata kunci atau genre lain.',
        onClick: widget.onDonghuaClick,
        onRetry: _ctrl.retryFilter,
        onLoadMore: _ctrl.loadMoreFilter,
      );
    } else if (_tab == DonghuaTab.latest) {
      content = _HomeContent(
        key: const ValueKey('latest'),
        state: ui.home,
        onClick: widget.onDonghuaClick,
        onRetry: _ctrl.loadHome,
      );
    } else if (_tab == DonghuaTab.ongoing) {
      content = _DonghuaGrid(
        key: const ValueKey('ongoing'),
        state: ui.ongoing,
        emptyTitle: 'Belum Ada Donghua',
        emptyDescription: 'Konten belum tersedia saat ini.',
        onClick: widget.onDonghuaClick,
        onRetry: () => _ctrl.loadOngoing(1),
        onLoadMore: _ctrl.loadMoreOngoing,
      );
    } else {
      content = _DonghuaGrid(
        key: const ValueKey('all'),
        state: ui.all,
        emptyTitle: 'Belum Ada Donghua',
        emptyDescription: 'Konten belum tersedia saat ini.',
        onClick: widget.onDonghuaClick,
        onRetry: () => _ctrl.loadAll(1),
        onLoadMore: _ctrl.loadMoreAll,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(ui),
            if (ui.genres.isNotEmpty) _genreRow(ui),
            if (!filtering)
              _Tabs(selected: _tab, onSelect: _selectTab)
            else
              Divider(
                height: 1,
                color: AppColors.surfaceElevated.withValues(alpha: 0.6),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(DonghuaUiState ui) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        height: 44,
        child: _searchOpen
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _SearchField(
                  controller: _search,
                  onChanged: _ctrl.onSearchQueryChange,
                  onClose: _closeSearch,
                ),
              )
            : Row(
                children: [
                  IconButton(
                    onPressed: widget.onBackClick,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Text(
                    'Donghua',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => setState(() => _searchOpen = true),
                    icon: const Icon(Icons.search, color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _genreRow(DonghuaUiState ui) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _GenreChip(
            title: 'Semua',
            selected: ui.selectedGenre == null,
            onTap: () => _ctrl.selectGenre(null),
          ),
          for (final g in ui.genres) ...[
            const SizedBox(width: 8),
            _GenreChip(
              title: g.name ?? g.slug ?? '',
              selected: ui.selectedGenre?.slug == g.slug,
              onTap: () => _ctrl.selectGenre(ui.selectedGenre?.slug == g.slug ? null : g),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Header: pencarian ─────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(Icons.search, size: 20, color: AppColors.textSecondary),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.accentViolet,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Cari donghua...',
                hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: const Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Chip genre & tab ─────────────────────────

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.title, required this.selected, required this.onTap});

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentViolet.withValues(alpha: 0.16)
              : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: AppColors.accentViolet) : null,
        ),
        child: Text(
          title,
          maxLines: 1,
          style: TextStyle(
            color: selected ? AppColors.accentViolet : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Tab teks dengan garis bawah aktif.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onSelect});

  final DonghuaTab selected;
  final ValueChanged<DonghuaTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final tab in DonghuaTab.values) ...[
                if (tab != DonghuaTab.values.first) const SizedBox(width: 24),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(tab),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: Text(
                          tab.label,
                          style: TextStyle(
                            color: tab == selected ? Colors.white : AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: tab == selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 28,
                        height: 3,
                        decoration: BoxDecoration(
                          color: tab == selected ? AppColors.accentViolet : Colors.transparent,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.surfaceElevated.withValues(alpha: 0.6)),
      ],
    );
  }
}

// ───────────────────────── Tab "Terbaru" ─────────────────────────

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    super.key,
    required this.state,
    required this.onClick,
    required this.onRetry,
  });

  final DonghuaHomeState state;
  final ValueChanged<String> onClick;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) return const _ShimmerGrid();
    if (state.errorMessage != null) {
      return ErrorState(message: state.errorMessage!, onRetry: onRetry);
    }
    if (state.isEmpty) {
      return const EmptyState(
        title: 'Belum Ada Donghua',
        subtitle: 'Konten belum tersedia saat ini.',
        icon: Icons.movie_outlined,
      );
    }

    final sections = state.sections.where((s) => s.cards.isNotEmpty).toList();
    // Hero: utamakan section rilisan terbaru, kalau tidak ada pakai section pertama.
    final heroSection = sections.firstWhere(
      (s) => (s.section ?? '').toLowerCase().contains('rilis'),
      orElse: () => sections.first,
    );
    final heroCards = heroSection.cards
        .where((c) => (c.slug ?? '').isNotEmpty && (c.thumbnail ?? '').isNotEmpty)
        .take(5)
        .toList();

    final count = (heroCards.isNotEmpty ? 1 : 0) + sections.length;
    return ListView.separated(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 28),
      itemBuilder: (context, i) {
        if (heroCards.isNotEmpty) {
          if (i == 0) return _HeroCarousel(cards: heroCards, onClick: onClick);
          i -= 1;
        }
        final section = sections[i];
        final ranked = (section.section ?? '').toLowerCase().contains('populer');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                prettySectionName(section.section),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ranked
                ? _RankedRow(section: section, onClick: onClick)
                : _PosterRow(section: section, onClick: onClick),
          ],
        );
      },
    );
  }
}

class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.section, required this.onClick});

  final AnichinHomeSection section;
  final ValueChanged<String> onClick;

  @override
  Widget build(BuildContext context) {
    final cards = section.cards.where((c) => (c.slug ?? '').isNotEmpty).toList();
    return SizedBox(
      height: 232,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(
          width: 124,
          child: DonghuaCard(card: cards[i], onTap: () => onClick(cards[i].slug!)),
        ),
      ),
    );
  }
}

/// Baris peringkat: angka besar berkontur di kiri poster.
class _RankedRow extends StatelessWidget {
  const _RankedRow({required this.section, required this.onClick});

  final AnichinHomeSection section;
  final ValueChanged<String> onClick;

  @override
  Widget build(BuildContext context) {
    final cards = section.cards.where((c) => (c.slug ?? '').isNotEmpty).take(10).toList();
    return SizedBox(
      height: 222,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onClick(cards[i].slug!),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 2, bottom: 30),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 84,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -4,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 1.6
                      ..color = Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
              SizedBox(
                width: 112,
                child: DonghuaCard(card: cards[i], onTap: () => onClick(cards[i].slug!)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Hero carousel ─────────────────────────

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.cards, required this.onClick});

  final List<AnichinCard> cards;
  final ValueChanged<String> onClick;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  PageController? _pc;
  double _fraction = 0;
  int _page = 0;

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    // Kartu selebar layar - 32 (padding 16), antar-halaman 12.
    final fraction = (w - 20) / w;
    if (_pc == null || _fraction != fraction) {
      _pc?.dispose();
      _fraction = fraction;
      _pc = PageController(viewportFraction: fraction, initialPage: _page);
    }
    final h = (w - 32) / 0.86;
    final cards = widget.cards;

    return Column(
      children: [
        SizedBox(
          height: h,
          child: PageView.builder(
            controller: _pc,
            itemCount: cards.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _HeroCard(card: cards[i], onTap: () => widget.onClick(cards[i].slug!)),
            ),
          ),
        ),
        if (cards.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < cards.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 4,
                    width: _page == i ? 18 : 6,
                    decoration: BoxDecoration(
                      color: _page == i ? Colors.white : Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.card, required this.onTap});

  final AnichinCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      cleanMeta(card.type),
      if (card.eps != null) 'Episode ${card.eps}',
      cleanMeta(card.status),
    ].whereType<String>().join('  •  ');

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.surfaceDark),
            DonghuaImage(card.thumbnail),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.45, 1],
                  colors: [
                    Colors.transparent,
                    AppColors.backgroundDark.withValues(alpha: 0.96),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meta.isNotEmpty) ...[
                    Text(
                      meta,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    cardTitle(card),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 28 / 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, color: Colors.black, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'Tonton',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Grid (Ongoing / Semua / hasil filter) ─────────────────────────

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 2 / 3,
      ),
      itemCount: 9,
      itemBuilder: (_, __) => ShimmerBox(borderRadius: BorderRadius.circular(10)),
    );
  }
}

class _DonghuaGrid extends StatefulWidget {
  const _DonghuaGrid({
    super.key,
    required this.state,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.onClick,
    required this.onRetry,
    required this.onLoadMore,
  });

  final DonghuaGridState state;
  final String emptyTitle;
  final String emptyDescription;
  final ValueChanged<String> onClick;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  @override
  State<_DonghuaGrid> createState() => _DonghuaGridState();
}

class _DonghuaGridState extends State<_DonghuaGrid> {
  /// Berapa item dari ujung bawah grid sebelum halaman berikutnya mulai
  /// dimuat (2 baris).
  static const int _prefetchDistance = 6;

  final ScrollController _scroll = ScrollController();

  /// Ukuran list saat terakhir kali minta halaman berikutnya. Mencegah loop
  /// retry otomatis kalau request gagal: gagal = ukuran list tidak berubah
  /// -> menunggu user tap "Coba lagi".
  int _requestedAtSize = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DonghuaGrid old) {
    super.didUpdateWidget(old);
    // List diganti total (ganti tab/genre -> item pertama beda).
    if (old.state.items.firstOrNull?.slug != widget.state.items.firstOrNull?.slug) {
      _requestedAtSize = -1;
    }
  }

  double _rowExtent(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cell = (w - 32 - 24) / 3;
    return cell * 1.5 + 8 + 36 + 18;
  }

  /// Auto load more: begitu jempol scroll mendekati ujung bawah, atau kalau
  /// halaman yang sudah dimuat belum cukup panjang untuk di-scroll.
  void _check() {
    final s = widget.state;
    if (!_scroll.hasClients || !s.hasNextPage || s.isLoadingMore) return;
    if (s.items.length == _requestedAtSize) return;
    final threshold = (_prefetchDistance / 3) * _rowExtent(context);
    final p = _scroll.position;
    if (p.maxScrollExtent - p.pixels <= threshold) {
      _requestedAtSize = s.items.length;
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (s.isInitialLoading) return const _ShimmerGrid();
    if (s.errorMessage != null && s.items.isEmpty) {
      return ErrorState(message: s.errorMessage!, onRetry: widget.onRetry);
    }
    if (s.isEmpty) {
      return EmptyState(
        title: widget.emptyTitle,
        subtitle: widget.emptyDescription,
        icon: Icons.movie_outlined,
      );
    }

    // Cek lagi setelah frame selesai (list pendek -> listener tidak terpicu).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });

    final cell = (MediaQuery.sizeOf(context).width - 32 - 24) / 3;
    final loadFailed = s.hasNextPage && !s.isLoadingMore && _requestedAtSize == s.items.length;

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 18,
              mainAxisExtent: cell * 1.5 + 8 + 36,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => DonghuaCard(
                key: ValueKey(s.items[i].slug),
                card: s.items[i],
                onTap: () => widget.onClick(s.items[i].slug!),
              ),
              childCount: s.items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: s.hasNextPage
              ? _LoadMoreFooter(
                  isLoading: s.isLoadingMore,
                  failed: loadFailed,
                  onRetry: () {
                    _requestedAtSize = s.items.length;
                    widget.onLoadMore();
                  },
                )
              : const SizedBox(height: 32),
        ),
      ],
    );
  }
}

/// Footer grid: spinner selama memuat; tombol "Coba lagi" cuma muncul kalau
/// request gagal.
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.isLoading,
    required this.failed,
    required this.onRetry,
  });

  final bool isLoading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AppColors.accentViolet,
                  strokeWidth: 2.5,
                ),
              )
            : failed
                ? GestureDetector(
                    onTap: onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.surfaceElevated),
                      ),
                      child: const Text(
                        'Gagal memuat. Coba lagi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
      ),
    );
  }
}
