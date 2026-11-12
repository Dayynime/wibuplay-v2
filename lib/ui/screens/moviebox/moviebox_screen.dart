import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/moviebox_models.dart';
import '../../../data/repository/moviebox_repository.dart';
import '../../components/common_components.dart';
import '../../components/shimmer.dart';
import '../../glass/glass.dart';
import 'moviebox_widgets.dart';

/// Daftar film MovieBox (Rekomendasi / Terbaru / Rating) + cari. Hanya film;
/// series, musik, dan upload lain tidak ditampilkan.
class MovieBoxScreen extends ConsumerStatefulWidget {
  const MovieBoxScreen({super.key, required this.onBackClick, required this.onMovieClick});

  final VoidCallback onBackClick;
  final ValueChanged<String> onMovieClick;

  @override
  ConsumerState<MovieBoxScreen> createState() => _MovieBoxScreenState();
}

class _MovieBoxScreenState extends ConsumerState<MovieBoxScreen> {
  MbSort _sort = MbSort.recommend;

  final List<MbItem> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _gen = 0;

  bool _searchOpen = false;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<MbItem>? _results;
  bool _searching = false;
  String? _searchError;

  final ScrollController _scroll = ScrollController();

  MovieBoxRepository get _repo => ref.read(movieBoxRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_query.isNotEmpty) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final gen = _gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await _repo.getMovies(page: _page + 1, sort: _sort);
      if (!mounted || gen != _gen) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _page++;
        _items.addAll(next.where((e) => known.add(e.id)));
        _hasMore = next.length >= MovieBoxRepository.pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = errorMessage(e, 'Gagal memuat daftar film.');
      });
    }
  }

  void _selectSort(MbSort s) {
    if (s == _sort) return;
    _gen++;
    setState(() {
      _sort = s;
      _items.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadMore();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(v));
  }

  Future<void> _runSearch(String v) async {
    final q = v.trim();
    setState(() {
      _query = q;
      _results = null;
      _searchError = null;
      _searching = q.isNotEmpty;
    });
    if (q.isEmpty) return;
    try {
      final r = await _repo.search(q);
      if (!mounted || _query != q) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || _query != q) return;
      setState(() {
        _searching = false;
        _searchError = errorMessage(e, 'Gagal mencari film.');
      });
    }
  }

  void _closeSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _searchOpen = false;
      _query = '';
      _results = null;
      _searching = false;
      _searchError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_query.isNotEmpty) {
      if (_searching) {
        content = const _ShimmerGrid(key: ValueKey('s-load'));
      } else if (_searchError != null) {
        content = ErrorState(message: _searchError!, onRetry: () => _runSearch(_query));
      } else if ((_results ?? const []).isEmpty) {
        content = const EmptyState(
          title: 'Film Tidak Ditemukan',
          subtitle: 'Coba kata kunci lain. Hanya film yang ditampilkan.',
          icon: Icons.movie_outlined,
        );
      } else {
        content = _Grid(key: ValueKey('s-$_query'), items: _results!, onClick: widget.onMovieClick);
      }
    } else if (_items.isEmpty && _loading) {
      content = const _ShimmerGrid(key: ValueKey('load'));
    } else if (_items.isEmpty && _error != null) {
      content = ErrorState(message: _error!, onRetry: _loadMore);
    } else if (_items.isEmpty) {
      content = const EmptyState(
        title: 'Belum Ada Film',
        subtitle: 'Konten belum tersedia saat ini.',
        icon: Icons.movie_outlined,
      );
    } else {
      content = _Grid(
        key: ValueKey('list-${_sort.name}'),
        items: _items,
        onClick: widget.onMovieClick,
        controller: _scroll,
        footer: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: TextButton(onPressed: _loadMore, child: const Text('Gagal memuat, coba lagi')),
                    ),
                  )
                : null,
      );
    }

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            if (_query.isEmpty) _tabs() else Divider(height: 1, color: AppColors.surfaceElevated.withValues(alpha: 0.6)),
            Expanded(
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: content),
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
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          autofocus: true,
                          onChanged: _onQuery,
                          onSubmitted: _runSearch,
                          textInputAction: TextInputAction.search,
                          cursorColor: AppColors.accentViolet,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Cari film...',
                            hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _closeSearch,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        icon: const Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            : Row(
                children: [
                  IconButton(onPressed: widget.onBackClick, icon: const Icon(Icons.arrow_back, color: Colors.white)),
                  const Text('Film', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
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

  Widget _tabs() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final s in MbSort.values) ...[
                if (s != MbSort.values.first) const SizedBox(width: 24),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectSort(s),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: Text(
                          s.label,
                          style: TextStyle(
                            color: s == _sort ? Colors.white : AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: s == _sort ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 28,
                        height: 3,
                        decoration: BoxDecoration(
                          color: s == _sort ? AppColors.accentViolet : Colors.transparent,
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

class _Grid extends StatelessWidget {
  const _Grid({super.key, required this.items, required this.onClick, this.controller, this.footer});

  final List<MbItem> items;
  final ValueChanged<String> onClick;
  final ScrollController? controller;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: 0.5,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => MovieBoxCard(item: items[i], onTap: () => onClick(items[i].id)),
              childCount: items.length,
            ),
          ),
        ),
        if (footer != null) SliverToBoxAdapter(child: footer),
        SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.viewPaddingOf(context).bottom)),
      ],
    );
  }
}

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.5,
      ),
      itemCount: 12,
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ShimmerBox(borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 12, width: 80, child: ShimmerBox(borderRadius: BorderRadius.zero)),
        ],
      ),
    );
  }
}
