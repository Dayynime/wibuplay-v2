import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/comic/comic_providers.dart';
import '../../../data/local/comic_store.dart';
import '../../../data/models/comic_models.dart';
import '../../components/common_components.dart';
import 'comic_detail_controller.dart';
import 'comic_widgets.dart';

const Color _starYellow = Color(0xFFFFB300);

/// Port ComicDetailScreen.kt: cover + info + sinopsis + daftar chapter.
/// Tombol baca: "Lanjutkan Baca" kalau ada progress tersimpan, kalau belum
/// "Mulai Baca" dari chapter pertama (urutan API terbaru di atas -> chapter
/// pertama = elemen paling akhir).
class ComicDetailScreen extends ConsumerWidget {
  const ComicDetailScreen({
    super.key,
    required this.comicKey,
    required this.onBackClick,
    required this.onChapterClick,
  });

  /// Kunci komik (ComicKey).
  final String comicKey;
  final VoidCallback onBackClick;

  /// (chapterSlug, judul komik, cover) -> buka reader.
  final void Function(String chapterSlug, String? title, String? cover) onChapterClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(comicDetailControllerProvider(comicKey));
    final ctrl = ref.read(comicDetailControllerProvider(comicKey).notifier);
    final isFav = ref.watch(comicStoreProvider.select((s) => s.isFavorite(comicKey)));
    final progress = ref.watch(comicStoreProvider.select((s) => s.progressFor(comicKey)));

    final Widget body;
    if (ui.isLoading) {
      body = const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet),
      );
    } else if (ui.error != null || ui.detail == null) {
      body = Center(
        child: ErrorState(
          message: ui.error ?? 'Gagal memuat detail komik.',
          onRetry: () => ctrl.load(forceRefresh: true),
        ),
      );
    } else {
      final d = ui.detail!;
      body = _Content(
        detail: d,
        progress: progress,
        onChapterClick: (slug) => onChapterClick(slug, d.title, d.cover),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _RoundIcon(icon: Icons.arrow_back, onTap: onBackClick),
                  const Spacer(),
                  if (ui.detail != null)
                    _RoundIcon(
                      icon: isFav ? Icons.bookmark : Icons.bookmark_border,
                      color: isFav ? _starYellow : Colors.white,
                      onTap: ctrl.toggleFavorite,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.color = Colors.white});

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

class _Content extends StatefulWidget {
  const _Content({
    required this.detail,
    required this.progress,
    required this.onChapterClick,
  });

  final ComicDetail detail;
  final ComicProgress? progress;
  final ValueChanged<String> onChapterClick;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  bool _synopsisExpanded = false;

  bool _has(String? s) => s != null && s.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final chapters = d.chapters ?? const <ComicChapterRef>[];
    final progress = widget.progress;
    final synopsis = d.synopsis?.trim();

    final infoRows = <(String, String)>[
      if (_has(d.author)) ('Author', d.author!),
      if (_has(d.artist)) ('Artist', d.artist!),
      if (_has(d.release)) ('Rilis', d.release!),
      if (_has(d.series)) ('Series', d.series!),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.surfaceDark),
                RepaintBoundary(child: ComicCoverImage(d.cover)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.backgroundDark.withValues(alpha: 0.6),
                        AppColors.backgroundDark,
                      ],
                      stops: const [0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title ?? 'Tanpa Judul',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_has(d.otherTitle))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      d.otherTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (_has(d.status)) _InfoChip(d.status!),
                    if (_has(d.type)) _InfoChip(d.type!),
                    if (_has(d.rating)) _InfoChip(d.rating!, star: true),
                  ],
                ),
                const SizedBox(height: 14),
                if (infoRows.isNotEmpty) ...[
                  for (final (label, value) in infoRows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$label  ',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: value,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
                if ((d.genres ?? const []).isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in d.genres!)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            g.title,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (synopsis != null && synopsis.isNotEmpty) ...[
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.topCenter,
                    child: Text(
                      synopsis,
                      maxLines: _synopsisExpanded ? null : 4,
                      overflow: _synopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                  if (synopsis.length > 150)
                    GestureDetector(
                      onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _synopsisExpanded ? 'Sembunyikan' : 'Selengkapnya',
                              style: const TextStyle(
                                color: AppColors.accentViolet,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Icon(
                              _synopsisExpanded ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: AppColors.accentViolet,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                if (progress != null)
                  _ReadButton(
                    icon: Icons.play_arrow_rounded,
                    text:
                        'Lanjutkan Baca • ${progress.chapterLabel ?? extractChapterLabel(progress.chapterSlug)}',
                    onTap: () => widget.onChapterClick(progress.chapterSlug),
                  )
                else if (chapters.isNotEmpty)
                  _ReadButton(
                    icon: Icons.menu_book_rounded,
                    text: 'Mulai Baca dari ${chapters.last.displayLabel}',
                    onTap: () => widget.onChapterClick(chapters.last.slug),
                  ),
                const SizedBox(height: 20),
                Text(
                  'Daftar Chapter (${chapters.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final c = chapters[i];
              return _FadeSlideIn(
                key: ValueKey(c.slug),
                delay: Duration(milliseconds: (i % 12) * 25),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  child: _ChapterRow(
                    chapter: c,
                    isLastRead: progress?.chapterSlug == c.slug,
                    onTap: () => widget.onChapterClick(c.slug),
                  ),
                ),
              );
            },
            childCount: chapters.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.text, {this.star = false});

  final String text;
  final bool star;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (star) ...[
            const Icon(Icons.star_rounded, size: 13, color: _starYellow),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadButton extends StatelessWidget {
  const _ReadButton({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentViolet,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.isLastRead,
    required this.onTap,
  });

  final ComicChapterRef chapter;
  final bool isLastRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = (chapter.date ?? '').trim();
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isLastRead
                ? Border.all(color: AppColors.accentViolet.withValues(alpha: 0.7))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  chapter.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isLastRead ? AppColors.accentViolet : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (date.isNotEmpty)
                Text(
                  date,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade + naik sedikit saat baris pertama kali dibuat (daftar chapter).
class _FadeSlideIn extends StatefulWidget {
  const _FadeSlideIn({super.key, required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
            .animate(curve),
        child: widget.child,
      ),
    );
  }
}
