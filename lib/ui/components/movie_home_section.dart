import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/repository/moviebox_repository.dart';
import '../screens/moviebox/moviebox_widgets.dart';
import 'common_components.dart';
import 'shimmer.dart';

/// Film yang SELALU jadi sorotan section Film di Beranda.
const String kMovieHomeFeaturedId = '6026412232966389904'; // Spider-Man: Brand New Day

/// Isi section Film: sorotan (film pilihan di atas) + baris Rekomendasi
/// (10 film pertama urutan "Rekomendasi" MovieBox, daftar khusus film,
/// urutan tetap dari server, bukan acak).
class MovieHomeData {
  const MovieHomeData({this.featured, this.items = const []});

  final MbDetail? featured;
  final List<MbItem> items;
}

final movieHomeProvider = FutureProvider<MovieHomeData>((ref) async {
  final repo = ref.watch(movieBoxRepositoryProvider);
  final results = await Future.wait<Object?>([
    repo.getDetail(kMovieHomeFeaturedId).then<Object?>((v) => v).catchError((Object _) => null),
    repo.getMovies(page: 1, sort: MbSort.recommend).then<Object?>((v) => v).catchError((Object _) => null),
  ]);
  final featured = results[0] as MbDetail?;
  final list = (results[1] as List<MbItem>?) ?? const <MbItem>[];
  final items = list.where((m) => m.id != kMovieHomeFeaturedId).take(10).toList();
  if (featured == null && items.isEmpty) throw Exception('Film tidak tersedia');
  return MovieHomeData(featured: featured, items: items);
});

/// Section "Film" di Beranda (desain B: kartu sorotan + Rekomendasi).
/// Gagal total = section tidak tampil.
class MovieHomeSection extends ConsumerWidget {
  const MovieHomeSection({super.key, required this.onMovieClick, required this.onSeeAllClick});

  final ValueChanged<String> onMovieClick;
  final VoidCallback onSeeAllClick;

  static const double _cardWidth = 98;
  static const double _rowHeight = _cardWidth * 1.5 + 8 + 34 + 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movieHomeProvider);
    final data = async.valueOrNull;
    if (async.hasError && data == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        SectionHeader(title: 'Film', actionText: 'Lihat semua', onActionClick: onSeeAllClick),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 200,
            child: data == null
                ? ShimmerBox(borderRadius: BorderRadius.circular(18))
                : data.featured != null
                    ? _Spotlight(movie: data.featured!, onTap: () => onMovieClick(data.featured!.id))
                    : const SizedBox.shrink(),
          ),
        ),
        if (data == null || data.items.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Rekomendasi',
              style: TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            height: _rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: data?.items.length ?? 4,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: _cardWidth,
                child: data == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(aspectRatio: 2 / 3, child: ShimmerBox(borderRadius: BorderRadius.circular(10))),
                          const SizedBox(height: 8),
                          const ShimmerBox(width: 80, height: 12),
                        ],
                      )
                    : MovieBoxCard(item: data.items[i], onTap: () => onMovieClick(data.items[i].id)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Kartu sorotan lebar: poster dipotong jadi latar, gradasi dari kiri,
/// chip, judul, info, tombol Tonton.
class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.movie, required this.onTap});

  final MbDetail movie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final genre = (movie.genre ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).take(2).join(', ');
    final meta = [
      if (movie.year != null) movie.year!,
      if (movie.duration != null) movie.duration!,
      if (genre.isNotEmpty) genre,
    ].join(' • ');
    final rating = movie.rating;

    return Material(
      color: AppColors.surfaceVariantDark,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster tegak dipotong ke 16:9, fokus agak ke atas (wajah/judul).
            const ColoredBox(color: AppColors.surfaceElevated),
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.62,
                heightFactor: 1,
                child: MovieBoxImage(movie.cover),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [0.0, 0.42, 0.75],
                  colors: [Color(0xF20B0E14), Color(0xCC0B0E14), Color(0x000B0E14)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 210,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _Tag('SOROTAN', color: Colors.white, background: AppColors.accentViolet),
                        if (rating != null && rating != '0' && rating != '0.0') ...[
                          const SizedBox(width: 6),
                          _Tag('★ $rating', color: const Color(0xFFFFC107), background: const Color(0x8C000000)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      movie.title ?? 'Film',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFC9CDD4), fontSize: 11.5),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.textWhite,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.backgroundDark),
                          SizedBox(width: 4),
                          Text(
                            'Tonton',
                            style: TextStyle(
                              color: AppColors.backgroundDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.color, required this.background});

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }
}
