import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../components/cards.dart';
import '../../components/common_components.dart';
import '../../components/shimmer.dart';
import 'explore_controller.dart';

/// Port ExploreScreen.kt.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key, required this.onAnimeClick});

  final ValueChanged<String> onAnimeClick;

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  static const double _minCell = 105;
  static const double _hGap = 10;
  static const double _vGap = 14;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  double _loadMoreThreshold = 500;

  ExploreController get _notifier => ref.read(exploreControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Muat halaman berikutnya kalau sudah dekat ujung (sekitar 6 item terakhir).
  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.maxScrollExtent - p.pixels <= _loadMoreThreshold) {
      _notifier.loadNextPage();
    }
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final ui = ref.watch(exploreControllerProvider);
            const types = ['TV', 'Movie', 'OVA', 'ONA', 'Special'];
            const years = ['2026', '2025', '2024', '2023', '2022', '2021', '2020'];
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filter Pencarian',
                        style: TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _notifier.resetFilters();
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Text(
                            'Reset',
                            style: TextStyle(
                              color: AppColors.accentViolet,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tipe',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in types)
                        GenreChip(
                          text: type,
                          isSelected: ui.selectedType == type,
                          onTap: () {
                            _notifier.onTypeSelected(type);
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tahun Rilis',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < years.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          GenreChip(
                            text: years[i],
                            isSelected: ui.selectedYear == years[i],
                            onTap: () {
                              _notifier.onYearSelected(years[i]);
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(exploreControllerProvider);

    // Samakan isi kolom cari kalau query diubah dari luar (mis. Reset)
    ref.listen<String>(
      exploreControllerProvider.select((s) => s.query),
      (prev, next) {
        if (_search.text != next) {
          _search.value = TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: next.length),
          );
        }
      },
    );
    // Setelah daftar bertambah, cek lagi apakah masih dekat ujung
    ref.listen<int>(
      exploreControllerProvider.select((s) => s.items.length),
      (prev, next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeLoadMore();
        });
      },
    );

    return ColoredBox(
      color: AppColors.backgroundDark,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Kolom cari + tombol filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => _notifier.onQueryChange(v),
                        maxLines: 1,
                        style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
                        cursorColor: AppColors.accentViolet,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surfaceDark,
                          hintText: 'Cari judul anime, genre, dll...',
                          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                          suffixIcon: ui.query.isNotEmpty
                              ? IconButton(
                                  onPressed: () => _notifier.onQueryChange(''),
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              : null,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: AppShapes.pill,
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppShapes.pill,
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: AppShapes.pill,
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: ui.hasActiveFilter
                            ? AppColors.accentViolet
                            : AppColors.surfaceDark,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.tune, color: AppColors.textWhite, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Chip cepat: urutan + genre
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  GenreChip(
                    text: 'Terpopuler',
                    isSelected: ui.selectedSort == 'views',
                    onTap: () => _notifier.onSortSelected('views'),
                  ),
                  const SizedBox(width: 8),
                  GenreChip(
                    text: 'A - Z',
                    isSelected: ui.selectedSort == 'alphabet',
                    onTap: () => _notifier.onSortSelected('alphabet'),
                  ),
                  for (final genre in ui.genres.take(15)) ...[
                    const SizedBox(width: 8),
                    GenreChip(
                      text: genre.name ?? '',
                      isSelected: ui.selectedGenreId == genre.id,
                      onTap: () => _notifier.onGenreSelected(genre.id),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),

            Expanded(child: _content(ui)),
          ],
        ),
      ),
    );
  }

  /// Hitung kolom seperti GridCells.Adaptive(minSize = 105.dp).
  ({int count, double cell}) _gridMetrics(double maxWidth) {
    final avail = maxWidth - 32;
    final count = math.max(1, ((avail + _hGap) / (_minCell + _hGap)).floor());
    final cell = (avail - _hGap * (count - 1)) / count;
    return (count: count, cell: cell);
  }

  Widget _content(ExploreUiState ui) {
    return LayoutBuilder(
      builder: (context, c) {
        final m = _gridMetrics(c.maxWidth);
        final extent = m.cell * 1.5 + 62;
        _loadMoreThreshold = (extent + _vGap) * 2;

        if (ui.isLoading) {
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: m.count,
              mainAxisSpacing: _vGap,
              crossAxisSpacing: _hGap,
              mainAxisExtent: extent,
            ),
            itemCount: 9,
            itemBuilder: (context, i) => AnimeCardSkeleton(width: m.cell),
          );
        }
        if (ui.error != null) {
          return Center(
            child: ErrorState(message: ui.error!, onRetry: () => _notifier.retry()),
          );
        }
        if (ui.items.isEmpty) {
          return const Center(
            child: EmptyState(
              title: 'Tidak Ada Hasil',
              subtitle: 'Coba kata kunci lain atau ubah filter pencarianmu',
              icon: Icons.search_off,
            ),
          );
        }
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: m.count,
                  mainAxisSpacing: _vGap,
                  crossAxisSpacing: _hGap,
                  mainAxisExtent: extent,
                ),
                itemCount: ui.items.length,
                itemBuilder: (context, i) {
                  final anime = ui.items[i];
                  return AnimePosterCard(
                    anime: anime,
                    width: m.cell,
                    onTap: () {
                      final id = anime.id;
                      if (id != null) widget.onAnimeClick(id);
                    },
                  );
                },
              ),
            ),
            if (ui.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: AppColors.accentViolet,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 135)),
          ],
        );
      },
    );
  }
}
