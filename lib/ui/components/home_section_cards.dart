import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anime_item.dart';
import '../../data/models/cuplix_item.dart';
import 'net_image.dart';
import 'poster_holder.dart';
import '../redesign/z_kit.dart';

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
/// yang bergulir ke samping, judul di atas gambar (redesain Samudra). Lebar
/// kartu ~68% layar supaya kartu berikutnya mengintip.
class AnimeCoverBannerRow extends StatelessWidget {
  const AnimeCoverBannerRow({
    super.key,
    required this.items,
    required this.onAnimeClick,
    this.showRank = false,
  });

  final List<AnimeItem> items;
  final ValueChanged<String> onAnimeClick;

  /// Tampilkan nomor urut besar bergaris + chip "Hangat" (Sedang Hangat).
  final bool showRank;

  @override
  Widget build(BuildContext context) {
    final cardWidth = (MediaQuery.sizeOf(context).width * 0.68).clamp(220.0, 340.0);
    return SizedBox(
      height: cardWidth * 9 / 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final anime = items[i];
          return _CoverBannerCard(
            anime: anime,
            width: cardWidth,
            rank: showRank ? i + 1 : null,
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

/// Kartu cover lebar 16:9 (gaya preview): judul & genre di atas gambar,
/// chip di kiri atas, nomor peringkat bergaris di kanan atas.
class _CoverBannerCard extends StatelessWidget {
  const _CoverBannerCard({
    required this.anime,
    required this.width,
    required this.onTap,
    this.rank,
  });

  final AnimeItem anime;
  final double width;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final views = compactCount(anime.views);
    final meta = [
      if (_has(anime.genre)) anime.genre!.split(',').take(2).map((e) => e.trim()).join(' · '),
      if (_has(anime.year)) anime.year!.trim(),
    ].join(' · ');
    return ZPress(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: AppColors.surfaceCard,
                child: NetImage(_has(anime.coverUrl) ? anime.coverUrl : anime.posterUrl),
              ),
              const ZScreentone(opacity: 0.12),
              const DecoratedBox(decoration: BoxDecoration(gradient: zBottomShade)),
              Positioned(
                left: 10,
                top: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (views != null) ZChip(views, icon: Icons.play_arrow_rounded, tone: ZTone.scrim),
                    if (rank != null) ...[
                      if (views != null) const SizedBox(width: 6),
                      const ZChip('Hangat', icon: Icons.local_fire_department_rounded, tone: ZTone.brand),
                    ],
                  ],
                ),
              ),
              if (rank != null)
                Positioned(
                  right: 10,
                  top: 4,
                  child: ZRankNumber(rank!, size: 44, color: const Color(0xC7FFFFFF)),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      anime.title ?? 'Tanpa Judul',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZFont.display(size: 16, color: Colors.white),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xC7FFFFFF), fontSize: 11.5),
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

/// Section "Terpopuler" (gaya preview): daftar peringkat vertikal dengan
/// angka besar bergaris. Tampil 5 dulu; "Tampilkan lebih banyak" membuka
/// sisanya sampai [maxItems], jadi tidak ada judul yang hilang.
class AnimeRankedRow extends StatefulWidget {
  const AnimeRankedRow({
    super.key,
    required this.items,
    required this.onAnimeClick,
    this.maxItems = 10,
  });

  final List<AnimeItem> items;
  final ValueChanged<String> onAnimeClick;
  final int maxItems;

  @override
  State<AnimeRankedRow> createState() => _AnimeRankedRowState();
}

class _AnimeRankedRowState extends State<AnimeRankedRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.items.take(widget.maxItems).toList();
    final shown = _expanded ? all : all.take(5).toList();
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutQuint,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (var i = 0; i < shown.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RankedCard(
                  rank: i + 1,
                  anime: shown[i],
                  onTap: () {
                    final id = shown[i].id;
                    if (id == null) return;
                    PosterTransitionHolder.url = shown[i].posterUrl;
                    widget.onAnimeClick(id);
                  },
                ),
              ),
            if (all.length > 5)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: Text(
                  _expanded ? 'Tampilkan lebih sedikit' : 'Tampilkan lebih banyak',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
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
    final views = compactCount(anime.views);
    final favorites = compactCount(anime.favorites);
    final genre = _firstGenre(anime.genre);
    final sub = [
      if (genre != null) genre,
      if (views != null) '$views ditonton',
    ].join(' · ');

    return ZPress(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Center(
              child: ZRankNumber(
                rank,
                size: 40,
                color: rank == 1 ? const Color(0xFFF6BE4F) : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 70,
              child: ColoredBox(color: AppColors.surfaceCard, child: NetImage(anime.posterUrl)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anime.title ?? 'Tanpa Judul',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (favorites != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF6BE4F)),
            const SizedBox(width: 2),
            Text(
              favorites,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ],
        ],
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
