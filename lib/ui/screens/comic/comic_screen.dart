import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/comic/comic_source.dart';
import '../../../data/models/comic_models.dart';
import 'comic_controller.dart';
import 'comic_widgets.dart';

/// Port ComicScreen.kt: tab "Komik" di bottom bar. Pemilih sumber
/// (Dayynime-v1 / v2), tab per sumber, cari, filter genre, grid dengan
/// auto load-more, dan carousel unggulan di tab pertama.
class ComicScreen extends ConsumerStatefulWidget {
  const ComicScreen({super.key, required this.onComicClick});

  /// Argumen = kunci komik (ComicKey).
  final ValueChanged<String> onComicClick;

  @override
  ConsumerState<ComicScreen> createState() => _ComicScreenState();
}

class _ComicScreenState extends ConsumerState<ComicScreen> {
  bool _searchOpen = false;
  final TextEditingController _search = TextEditingController();

  ComicController get _ctrl => ref.read(comicControllerProvider.notifier);

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

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(comicControllerProvider);
    final filtering = ui.isFiltering;

    final Widget content;
    if (filtering) {
      content = ComicGrid(
        key: ValueKey('filter-${ui.source.id}-${ui.query}-${ui.selectedGenre?.slug}'),
        state: ui.filter,
        emptyTitle: 'Komik Tidak Ditemukan',
        emptyDescription: 'Coba kata kunci atau genre lain.',
        onClick: widget.onComicClick,
        onRetry: _ctrl.retryFilter,
        onLoadMore: _ctrl.loadMoreFilter,
      );
    } else {
      final isFirstTab = ui.tabs.isNotEmpty && ui.selectedTab == ui.tabs.first.id;
      content = ComicGrid(
        key: ValueKey('tab-${ui.source.id}-${ui.selectedTab}'),
        state: ui.list,
        emptyTitle: 'Belum Ada Komik',
        emptyDescription: 'Konten belum tersedia saat ini.',
        onClick: widget.onComicClick,
        onRetry: () => _ctrl.loadTab(),
        onLoadMore: _ctrl.loadMoreTab,
        onRefresh: () => _ctrl.loadTab(forceRefresh: true, silent: true),
        // Carousel unggulan cuma di tab pertama & kalau datanya cukup.
        heroItems: isFirstTab && ui.list.items.length >= 5
            ? ui.list.items.take(5).toList()
            : null,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            _SourceSwitcher(
              sources: _ctrl.sources,
              selected: ui.source,
              onSelect: (s) {
                _search.clear();
                _ctrl.selectSource(s);
              },
            ),
            if (ui.genres.isNotEmpty) _genreRow(ui),
            if (!filtering)
              _Tabs(
                key: ValueKey('tabs-${ui.source.id}'),
                tabs: ui.tabs,
                selected: ui.selectedTab,
                onSelect: _ctrl.selectTab,
              )
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

  Widget _header() {
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
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text(
                      'Komik',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
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

  Widget _genreRow(ComicUiState ui) {
    return SizedBox(
      height: 46,
      child: ListView(
        key: PageStorageKey('genres-${ui.source.id}'),
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
              title: g.title,
              selected: ui.selectedGenre?.slug == g.slug,
              onTap: () => _ctrl.selectGenre(ui.selectedGenre?.slug == g.slug ? null : g),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Pemilih sumber ─────────────────────────

class _SourceSwitcher extends StatelessWidget {
  const _SourceSwitcher({
    required this.sources,
    required this.selected,
    required this.onSelect,
  });

  final List<ComicSourceId> sources;
  final ComicSourceId selected;
  final ValueChanged<ComicSourceId> onSelect;

  @override
  Widget build(BuildContext context) {
    if (sources.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final s in sources)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s == selected ? AppColors.accentViolet : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      s.label,
                      style: TextStyle(
                        color: s == selected ? Colors.white : AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: s == selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Pencarian, chip, tab ─────────────────────────

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
                hintText: 'Cari komik...',
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

/// Tab teks dengan garis bawah aktif. Bisa digeser (Westmanga punya 15 tab).
class _Tabs extends StatelessWidget {
  const _Tabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<ComicTab> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final tab in tabs) ...[
                if (tab != tabs.first) const SizedBox(width: 24),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(tab.id),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: Text(
                          tab.label,
                          style: TextStyle(
                            color: tab.id == selected ? Colors.white : AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: tab.id == selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 28,
                        height: 3,
                        decoration: BoxDecoration(
                          color: tab.id == selected ? AppColors.accentViolet : Colors.transparent,
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

/// Carousel "Unggulan" di paling atas tab pertama: cover besar + judul +
/// chapter terbaru, geser otomatis tiap 4,5 detik (berhenti kalau lagi
/// digeser manual).
class ComicHeroCarousel extends StatefulWidget {
  const ComicHeroCarousel({super.key, required this.items, required this.onComicClick});

  final List<ComicListItem> items;
  final ValueChanged<String> onComicClick;

  @override
  State<ComicHeroCarousel> createState() => _ComicHeroCarouselState();
}

class _ComicHeroCarouselState extends State<ComicHeroCarousel> {
  final PageController _page = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _current = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 4500), (_) {
      if (!mounted || _dragging || !_page.hasClients) return;
      final next = (_current + 1) % widget.items.length;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _dragging = true;
              } else if (n is ScrollEndNotification) {
                _dragging = false;
              }
              return false;
            },
            child: PageView.builder(
              controller: _page,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _HeroCard(
                  comic: items[i],
                  onTap: () => widget.onComicClick(items[i].slug),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                height: 6,
                width: i == _current ? 18 : 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _current
                      ? AppColors.accentViolet
                      : Colors.white.withValues(alpha: 0.25),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.comic, required this.onTap});

  final ComicListItem comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = (comic.type ?? '').trim();
    final chapter = (comic.chapter ?? '').trim();
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.surfaceDark),
            ComicImage(comic.cover, alignment: Alignment.topCenter, memCacheWidth: 800),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xF20B0E14)],
                  stops: [0.35, 1.0],
                ),
              ),
            ),
            if (type.isNotEmpty)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: comicTypeColor(type),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    type.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chapter.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentViolet,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        compactChapterLabel(chapter),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
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
