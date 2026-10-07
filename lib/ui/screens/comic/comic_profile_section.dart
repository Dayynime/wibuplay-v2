import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/comic/comic_providers.dart';
import '../../../data/models/comic_models.dart';
import '../../app_routes.dart';
import 'comic_widgets.dart';

Widget _header(IconData icon, String title, String? trailing) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentViolet, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
        ],
      ),
    );

Widget _emptyBox(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: Text(title, style: const TextStyle(color: AppColors.textWhite)),
      content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
      ],
    ),
  );
  return ok ?? false;
}

/// Komik favorit (tab Favorit di Profil). Tahan kartu untuk menghapus.
class ComicFavoritesBlock extends ConsumerWidget {
  const ComicFavoritesBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(comicStoreProvider);
    final favs = store.favorites;
    const cardW = 112.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(Icons.menu_book_rounded, 'Komik Favorit',
            favs.isEmpty ? null : '${favs.length} Komik'),
        if (favs.isEmpty)
          _emptyBox('Belum ada komik favorit.')
        else
          SizedBox(
            height: cardW * 1.5 + 8 + 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: favs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final f = favs[i];
                return SizedBox(
                  width: cardW,
                  child: ComicPosterCard(
                    comic: ComicListItem(title: f.title, slug: f.slug, cover: f.cover),
                    onTap: () => openComicDetail(context, f.slug),
                    onLongPress: () async {
                      if (await _confirm(
                        context,
                        'Hapus dari Favorit?',
                        '"${f.title}" akan dihapus dari komik favorit.',
                      )) {
                        await store.removeFavorite(f.slug);
                      }
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Riwayat baca komik (tab Riwayat di Profil): chapter terakhir per komik.
class ComicProgressBlock extends ConsumerWidget {
  const ComicProgressBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(comicStoreProvider);
    final list = store.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(Icons.auto_stories_rounded, 'Riwayat Baca Komik', null),
        if (list.isEmpty)
          _emptyBox('Belum ada riwayat baca komik.')
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final p in list)
                  Padding(
                    key: ValueKey(p.comicSlug),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => openComicReader(
                          context,
                          comicKey: p.comicSlug,
                          chapterSlug: p.chapterSlug,
                          title: p.comicTitle,
                          cover: p.comicCover,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 52,
                                  height: 76,
                                  child: ComicImage(p.comicCover, memCacheWidth: 200),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.comicTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      p.chapterLabel ?? extractChapterLabel(p.chapterSlug),
                                      style: const TextStyle(
                                        color: AppColors.accentViolet,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => store.deleteProgress(p.comicSlug),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
