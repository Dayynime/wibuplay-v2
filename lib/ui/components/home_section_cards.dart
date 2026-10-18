import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anime_item.dart';
import '../../data/models/cuplix_item.dart';
import 'net_image.dart';
import 'poster_holder.dart';

/// 1.874.111 -> "1,9jt", 24.803 -> "24,8rb"; null kalau bukan angka.
String? compactCount(String? raw) {
  final value = int.tryParse((raw ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
  if (value == null) return null;
  String one(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  if (value >= 1000000) return '${one(value / 1000000)}jt';
  if (value >= 1000) return '${one(value / 1000)}rb';
  return '$value';
}

String? _firstGenre(String? genre) {
  if (genre == null) return null;
  final g = genre.split(',').first.trim();
  return g.isEmpty ? null : g;
}

bool _has(String? s) => s != null && s.trim().isNotEmpty;

/// Section bergaya banner ("Sedang Hangat" dan "Jas Por Yu"): kartu cover 16:9
/// yang bergulir ke samping; di bawah tiap cover ada poster mini, genre, judul,
/// lalu jumlah views & favorit. Lebar kartu ~62% layar supaya kartu berikutnya
/// mengintip. Port AnimeCoverBannerSection (Zenime).
class AnimeCoverBannerRow extends StatelessWidget {
  const AnimeCoverBannerRow({super.key, required this.items, required this.onAnimeClick});

  final List<AnimeItem> items;
  final ValueChanged<String> onAnimeClick;

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.of(context).size.width * 0.62;
    // cover 16:9 + jarak + poster mini (46 x 69) + napas
    final height = cardWidth * 9 / 16 + 10 + 69 + 8;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final anime = items[i];
          return _CoverBannerCard(
            anime: anime,
            width: cardWidth,
            onTap: () {
              final id = anime.id;
              if (id == null) return;
              PosterTransitionHolder.url = anime.posterUrl;
              onAnimeClick(id);
            },
          );
        },
      ),
    );
  }
}

class _CoverBannerCard extends StatelessWidget {
  const _CoverBannerCard({required this.anime, required this.width, required this.onTap});

  final AnimeItem anime;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final views = compactCount(anime.views);
    final favorites = compactCount(anime.favorites);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: AppColors.surfaceCard,
                  child: NetImage(anime.coverUrl),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 46,
                  height: 69,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: AppColors.surfaceCard,
                      child: NetImage(anime.posterUrl),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_has(anime.genre))
                        Text(
                          anime.genre!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.accentVioletLight,
                            fontSize: 11,
                          ),
                        ),
                      Text(
                        anime.title ?? 'Tanpa Judul',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (views != null || favorites != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (views != null) ...[
                              const Icon(Icons.play_arrow, size: 13, color: Color(0xFFE53935)),
                              const SizedBox(width: 2),
                              Text(
                                views,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            if (views != null && favorites != null) const SizedBox(width: 10),
                            if (favorites != null) ...[
                              const Icon(Icons.star, size: 13, color: Color(0xFFFFB300)),
                              const SizedBox(width: 2),
                              Text(
                                favorites,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Section "tangga lagu" ("Terpopuler"): poster besar dengan nomor peringkat
/// raksasa di kiri bawah (1-3 emas/perak/perunggu), views di kanan bawah, lalu
/// judul, genre, dan favorit di bawah poster. Port AnimeRankedSection (Zenime).
class AnimeRankedRow extends StatelessWidget {
  const AnimeRankedRow({
    super.key,
    required this.items,
    required this.onAnimeClick,
    this.maxItems = 10,
  });

  final List<AnimeItem> items;
  final ValueChanged<String> onAnimeClick;
  final int maxItems;

  static const double _cardWidth = 148;

  @override
  Widget build(BuildContext context) {
    final ranked = items.take(maxItems).toList();
    // poster 2:3 + judul 2 baris + baris genre/favorit
    const height = _cardWidth * 3 / 2 + 8 + 36 + 22;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: ranked.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final anime = ranked[i];
          return _RankedCard(
            rank: i + 1,
            anime: anime,
            onTap: () {
              final id = anime.id;
              if (id == null) return;
              PosterTransitionHolder.url = anime.posterUrl;
              onAnimeClick(id);
            },
          );
        },
      ),
    );
  }
}

class _RankedCard extends StatelessWidget {
  const _RankedCard({required this.rank, required this.anime, required this.onTap});

  final int rank;
  final AnimeItem anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rankColor = switch (rank) {
      1 => const Color(0xFFFFC107),
      2 => const Color(0xFFE0E0E0),
      3 => const Color(0xFFCD7F32),
      _ => Colors.white,
    };
    final views = compactCount(anime.views);
    final favorites = compactCount(anime.favorites);
    final genre = _firstGenre(anime.genre);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: AnimeRankedRow._cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ColoredBox(
                  color: AppColors.surfaceCard,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImage(anime.posterUrl),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 96,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xD9000000)],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 4,
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            color: rankColor,
                            fontSize: 46,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            shadows: const [
                              Shadow(
                                color: Color(0x99000000),
                                offset: Offset(0, 4),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (views != null)
                        Positioned(
                          right: 10,
                          bottom: 12,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_arrow, size: 13, color: Color(0xFFE53935)),
                              const SizedBox(width: 2),
                              Text(
                                views,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              anime.title ?? 'Tanpa Judul',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (genre != null)
                  Flexible(
                    child: Text(
                      genre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.accentVioletLight,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (favorites != null) ...[
                  if (genre != null) const SizedBox(width: 8),
                  const Icon(Icons.star, size: 12, color: Color(0xFFFFB300)),
                  const SizedBox(width: 2),
                  Text(
                    favorites,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Baris thumbnail klip Cuplix 80x80 (section "Cuplix" di Beranda).
class CuplixThumbRow extends StatelessWidget {
  const CuplixThumbRow({super.key, required this.clips, required this.onClipClick});

  final List<CuplixItem> clips;
  final VoidCallback onClipClick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: clips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => GestureDetector(
          onTap: onClipClick,
          child: SizedBox(
            width: 80,
            height: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: AppColors.surfaceCard,
                child: NetImage(clips[i].thumbnailUrl),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
