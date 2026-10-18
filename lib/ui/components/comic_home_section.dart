import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/comic/comic_providers.dart';
import '../../data/models/comic_models.dart';
import '../screens/comic/comic_widgets.dart';
import 'common_components.dart';
import 'shimmer.dart';

/// Komik terbaru di Beranda: selalu dari Bacakomik (Dayynime-v1), sama seperti
/// Zenime. Gagal/kosong = section tidak tampil.
final comicHomeLatestProvider = FutureProvider<List<ComicListItem>>((ref) async {
  final res = await ref.watch(comicRepositoryProvider).getLatest();
  return (res.komikList ?? const <ComicListItem>[]).take(12).toList();
});

class ComicHomeSection extends ConsumerWidget {
  const ComicHomeSection({
    super.key,
    required this.onComicClick,
    required this.onSeeAllClick,
  });

  final ValueChanged<String> onComicClick;
  final VoidCallback onSeeAllClick;

  static const double _cardWidth = 112;
  static const double _rowHeight = _cardWidth * 1.5 + 8 + 38;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(comicHomeLatestProvider);
    final items = async.valueOrNull;

    if (async.hasError && items == null) return const SizedBox.shrink();
    if (items != null && items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Komik Terbaru',
          actionText: 'Lihat semua',
          onActionClick: onSeeAllClick,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _rowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items?.length ?? 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: _cardWidth,
              child: items == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ShimmerBox(borderRadius: BorderRadius.circular(12)),
                        ),
                      ],
                    )
                  : ComicPosterCard(
                      comic: items[i],
                      onTap: () => onComicClick(items[i].slug),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
