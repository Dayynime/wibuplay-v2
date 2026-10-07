import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/api/comic_network.dart';
import '../../../data/models/comic_models.dart';
import '../../components/common_components.dart';
import '../../components/shimmer.dart';
import 'comic_controller.dart';
import 'comic_screen.dart' show ComicHeroCarousel;

const Color _starYellow = Color(0xFFFFB300);

/// Warna badge per tipe komik, dipakai kartu poster.
Color comicTypeColor(String? type) => switch (type?.trim().toLowerCase()) {
      'manga' => const Color(0xFF3B82F6),
      'manhua' => const Color(0xFFF59E0B),
      'manhwa' => AppColors.accentViolet,
      _ => const Color(0xFF6B7280),
    };

/// "Chapter 11" / "Ch.19" -> "Ch. 11" / "Ch. 19" biar badge ringkas.
String compactChapterLabel(String raw) => raw
    .trim()
    .replaceFirst(RegExp(r'^(chapter|ch)\.?\s*', caseSensitive: false), 'Ch. ');

/// Gambar komik (cover + halaman chapter) dari CDN sumber. Header: UA browser,
/// TANPA Referer; http:// dinaikkan ke https://. Pakai di tempat yang
/// ukurannya sudah pasti.
class ComicImage extends StatelessWidget {
  const ComicImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memCacheWidth,
  });

  final String? url;
  final BoxFit fit;
  final Alignment alignment;
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final u = ComicNetwork.normalizeImageUrl(url);
    if (u == null) {
      return const ColoredBox(color: AppColors.surfaceDark, child: SizedBox.expand());
    }
    return CachedNetworkImage(
      imageUrl: u,
      httpHeaders: ComicNetwork.imageHeaders,
      fit: fit,
      alignment: alignment,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.expand(
        child: ShimmerBox(borderRadius: BorderRadius.zero),
      ),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: AppColors.surfaceCard,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// Kartu poster komik (2:3) + judul. Lebar ditentukan parent. Mengecil sedikit
/// saat ditekan.
class ComicPosterCard extends StatefulWidget {
  const ComicPosterCard({
    super.key,
    required this.comic,
    required this.onTap,
    this.onLongPress,
  });

  final ComicListItem comic;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<ComicPosterCard> createState() => _ComicPosterCardState();
}

class _ComicPosterCardState extends State<ComicPosterCard> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comic;
    final type = (c.type ?? '').trim();
    final rating = (c.rating ?? '').trim();
    final chapter = (c.chapter ?? '').trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.surfaceDark),
                    ComicImage(c.cover, memCacheWidth: 400),
                    // Gradient bawah biar badge chapter kebaca di cover apa pun.
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF0B0E14).withValues(alpha: 0.92),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (type.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: comicTypeColor(type),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            type.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    if (rating.isNotEmpty)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 10, color: _starYellow),
                              const SizedBox(width: 2),
                              Text(
                                rating,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (chapter.isNotEmpty)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        right: 6,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentViolet.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              compactChapterLabel(chapter),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              c.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 17 / 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ComicShimmerGrid extends StatelessWidget {
  const ComicShimmerGrid({super.key});

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
      itemBuilder: (_, __) => ShimmerBox(borderRadius: BorderRadius.circular(12)),
    );
  }
}

/// Grid komik 3 kolom dengan auto load-more. Dibuat ulang (pakai Key) tiap
/// ganti sumber/tab/filter, jadi posisi scroll otomatis kembali ke atas.
class ComicGrid extends StatefulWidget {
  const ComicGrid({
    super.key,
    required this.state,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.onClick,
    required this.onRetry,
    required this.onLoadMore,
    this.onRefresh,
    this.bottomPadding = 110,
    this.heroItems,
  });

  final ComicListState state;
  final String emptyTitle;
  final String emptyDescription;
  final ValueChanged<String> onClick;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final Future<void> Function()? onRefresh;

  /// Kalau diisi, carousel unggulan tampil di paling atas grid.
  final List<ComicListItem>? heroItems;

  /// Ruang di bawah daftar supaya tidak tertutup bottom bar melayang.
  final double bottomPadding;

  @override
  State<ComicGrid> createState() => _ComicGridState();
}

class _ComicGridState extends State<ComicGrid> {
  /// Berapa item dari ujung bawah grid sebelum halaman berikutnya mulai dimuat.
  static const int _prefetchDistance = 6;

  final ScrollController _scroll = ScrollController();
  bool _showTop = false;

  /// Ukuran list saat terakhir kali minta halaman berikutnya. Mencegah loop
  /// retry otomatis kalau request gagal: gagal = ukuran list tidak berubah
  /// -> menunggu user tap "Coba lagi".
  int _requestedAtSize = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _rowExtent(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cell = (w - 32 - 24) / 3;
    return cell * 1.5 + 8 + 36 + 18;
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 400;
    if (show != _showTop) setState(() => _showTop = show);
    _check();
  }

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
    if (s.isInitialLoading) return const ComicShimmerGrid();
    if (s.errorMessage != null && s.items.isEmpty) {
      return ErrorState(message: s.errorMessage!, onRetry: widget.onRetry);
    }
    if (s.isEmpty) {
      return EmptyState(
        title: widget.emptyTitle,
        subtitle: widget.emptyDescription,
        icon: Icons.menu_book_outlined,
      );
    }

    // Cek lagi setelah frame selesai (list pendek -> listener tidak terpicu).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });

    final cell = (MediaQuery.sizeOf(context).width - 32 - 24) / 3;
    final loadFailed =
        s.hasNextPage && !s.isLoadingMore && _requestedAtSize == s.items.length;

    Widget grid = CustomScrollView(
      controller: _scroll,
      physics: widget.onRefresh != null
          ? const AlwaysScrollableScrollPhysics()
          : null,
      slivers: [
        if (widget.heroItems != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ComicHeroCarousel(
                items: widget.heroItems!,
                onComicClick: widget.onClick,
              ),
            ),
          ),
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
              (_, i) => ComicPosterCard(
                key: ValueKey(s.items[i].slug),
                comic: s.items[i],
                onTap: () => widget.onClick(s.items[i].slug),
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
        SliverToBoxAdapter(child: SizedBox(height: widget.bottomPadding)),
      ],
    );

    if (widget.onRefresh != null) {
      grid = RefreshIndicator(
        color: AppColors.accentViolet,
        backgroundColor: AppColors.surfaceDark,
        onRefresh: widget.onRefresh!,
        child: grid,
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: grid),
        Positioned(
          right: 16,
          bottom: widget.bottomPadding - 10,
          child: AnimatedScale(
            scale: _showTop ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Material(
              color: AppColors.accentViolet,
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
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
