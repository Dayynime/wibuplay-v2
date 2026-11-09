import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../components/cards.dart';
import '../../components/common_components.dart';
import '../../components/shimmer.dart';
import '../../../data/models/genre_item.dart';
import 'explore_controller.dart';
import '../../glass/glass.dart';

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
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    showGlassSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: maxHeight),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => const _FilterSheet(),
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
            // Judul + tombol filter (redesain Samudra)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '探す',
                          style: TextStyle(
                            color: AppColors.accentVioletLight,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          'Jelajah',
                          style: TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: ui.hasActiveFilter ? AppColors.accentViolet : AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x12FFFFFF)),
                      ),
                      child: const Icon(Icons.tune_rounded, color: AppColors.textWhite, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            // Kolom cari besar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: SizedBox(
                height: 50,
                child: TextField(
                  controller: _search,
                  onChanged: (v) => _notifier.onQueryChange(v),
                  maxLines: 1,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
                  cursorColor: AppColors.accentViolet,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceDark,
                    hintText: 'Cari judul, studio, atau genre',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search_rounded, size: 21, color: AppColors.textSecondary),
                    suffixIcon: ui.query.isNotEmpty
                        ? IconButton(
                            onPressed: () => _notifier.onQueryChange(''),
                            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0x12FFFFFF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0x12FFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.accentViolet, width: 1.2),
                    ),
                  ),
                ),
              ),
            ),

            // Chip genre (semua genre dari API) + "Semua"
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  GenreChip(
                    text: 'Semua',
                    isSelected: ui.selectedGenreId == null,
                    onTap: () {
                      if (ui.selectedGenreId != null) {
                        _notifier.onGenreSelected(ui.selectedGenreId);
                      }
                    },
                  ),
                  for (final genre in ui.genres) ...[
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
        // Tanpa pencarian/filter: tampilkan tile genre dulu (gaya preview).
        final browsing = ui.query.isEmpty && !ui.hasActiveFilter && ui.selectedGenreId == null;
        final tiles = browsing ? ui.genres.where((g) => g.id != null).take(6).toList() : const <GenreItem>[];
        String? genreName;
        for (final g in ui.genres) {
          if (g.id == ui.selectedGenreId) genreName = g.name;
        }
        final listTitle = ui.query.isNotEmpty
            ? 'Hasil Pencarian'
            : (genreName != null && genreName.isNotEmpty ? genreName : 'Semua Anime');
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            if (tiles.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    const SectionHeader(title: 'Genre'),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.05,
                        children: [
                          for (var i = 0; i < tiles.length; i++)
                            _GenreTile(
                              name: tiles[i].name ?? '',
                              index: i,
                              onTap: () => _notifier.onGenreSelected(tiles[i].id),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 4),
                child: SectionHeader(
                  title: listTitle,
                  eyebrow: ui.query.isNotEmpty ? '検索結果' : '作品一覧',
                ),
              ),
            ),
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


/// Tile genre berwarna dengan nama Jepang kecil (gaya preview Jelajah).
class _GenreTile extends StatelessWidget {
  const _GenreTile({required this.name, required this.index, required this.onTap});

  final String name;
  final int index;
  final VoidCallback onTap;

  static const Map<String, String> _jp = {
    'action': 'アクション', 'aksi': 'アクション', 'adventure': '冒険', 'petualangan': '冒険',
    'comedy': 'コメディ', 'komedi': 'コメディ', 'drama': 'ドラマ', 'fantasy': 'ファンタジー',
    'fantasi': 'ファンタジー', 'romance': 'ロマンス', 'romansa': 'ロマンス', 'isekai': '異世界',
    'mystery': 'ミステリー', 'misteri': 'ミステリー', 'horror': 'ホラー', 'sci-fi': 'SF',
    'slice of life': '日常', 'sports': 'スポーツ', 'olahraga': 'スポーツ', 'school': '学園',
    'supernatural': '超常', 'music': '音楽', 'mecha': 'メカ', 'psychological': '心理',
    'thriller': 'スリラー', 'shounen': '少年', 'shoujo': '少女', 'seinen': '青年', 'harem': 'ハーレム',
  };

  // Rona tiap tile (derajat HSL), bergiliran.
  static const List<double> _hues = [200, 340, 160, 28, 265, 190];

  @override
  Widget build(BuildContext context) {
    final h = _hues[index % _hues.length];
    final jp = _jp[name.toLowerCase().trim()];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HSLColor.fromAHSL(1, h, 0.62, 0.42).toColor(),
              HSLColor.fromAHSL(1, (h + 35) % 360, 0.65, 0.16).toColor(),
            ],
          ),
        ),
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (jp != null)
              Text(
                jp,
                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 10.5, letterSpacing: 1.2),
              ),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet filter: Status, Tipe, Genre, Tahun, Urutkan. Pilihan disimpan
/// sementara dan baru diterapkan lewat tombol "Terapkan" (satu kali muat).
/// Tombol ditaruh di footer tetap dengan padding system navigation bar, jadi
/// tidak tertutup tombol navigasi HP.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  static const List<(String?, String)> _statuses = [
    (null, 'Semua'),
    ('ONGOING', 'Ongoing'),
    ('FINISHED', 'Completed'),
  ];
  static const List<(String?, String)> _types = [
    (null, 'Semua'),
    ('TV', 'TV Series'),
    ('Movie', 'Movie'),
    ('OVA', 'OVA'),
    ('ONA', 'ONA'),
    ('Special', 'Special'),
  ];
  static const List<(String, String)> _sorts = [
    ('views', 'Terpopuler'),
    ('alphabet', 'A - Z'),
  ];

  late String? _genre;
  late String? _status;
  late String? _type;
  late String? _year;
  late String _sort;

  @override
  void initState() {
    super.initState();
    final s = ref.read(exploreControllerProvider);
    _genre = s.selectedGenreId;
    _status = s.selectedStatus;
    _type = s.selectedType;
    _year = s.selectedYear;
    _sort = s.selectedSort;
  }

  void _reset() => setState(() {
        _genre = null;
        _status = null;
        _type = null;
        _year = null;
        _sort = 'views';
      });

  void _apply() {
    ref.read(exploreControllerProvider.notifier).applyFilters(
          genreId: _genre,
          status: _status,
          type: _type,
          year: _year,
          sort: _sort,
        );
    Navigator.of(context).pop();
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  Widget _chips<T>(
    List<(T, String)> options,
    T selected,
    ValueChanged<T> onSelect,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          GenreChip(
            text: o.$2,
            isSelected: selected == o.$1,
            onTap: () => setState(() => onSelect(o.$1)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final genres = ref.watch(exploreControllerProvider.select((s) => s.genres));
    final thisYear = DateTime.now().year;
    final years = [for (var y = thisYear; y >= 2000; y--) '$y'];
    // Tinggi system navigation bar (3 tombol / gesture bar).
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
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
                onTap: _reset,
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
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Status'),
                _chips<String?>(_statuses, _status, (v) => _status = v),
                _label('Tipe'),
                _chips<String?>(_types, _type, (v) => _type = v),
                if (genres.isNotEmpty) ...[
                  _label('Genre'),
                  _chips<String?>(
                    [
                      (null, 'Semua'),
                      for (final g in genres)
                        if (g.id != null) (g.id, g.name ?? ''),
                    ],
                    _genre,
                    (v) => _genre = v,
                  ),
                ],
                _label('Tahun Rilis'),
                _chips<String?>(
                  [(null, 'Semua'), for (final y in years) (y, y)],
                  _year,
                  (v) => _year = v,
                ),
                _label('Urutkan'),
                _chips<String>(_sorts, _sort, (v) => _sort = v),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _apply,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentViolet,
                foregroundColor: AppColors.textWhite,
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Terapkan',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
