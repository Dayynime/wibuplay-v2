import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/anime_item.dart';
import '../../../providers.dart';
import '../../components/cards.dart';
import '../../components/common_components.dart';
import '../../components/net_image.dart';
import '../../components/poster_holder.dart';
import 'detail_controller.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Port DetailScreen.kt.
class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({
    super.key,
    required this.movieId,
    required this.onBackClick,
    required this.onWatchEpisode,
  });

  final String movieId;
  final VoidCallback onBackClick;
  final void Function(String movieId, String episodeId) onWatchEpisode;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  static const List<String> _tabs = ['Ringkasan', 'Daftar Episode', 'Media & Cuplix'];

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  bool _synopsisExpanded = false;

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  DetailController get _notifier =>
      ref.read(detailControllerProvider(widget.movieId).notifier);

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(detailControllerProvider(widget.movieId));
    final isFavorite =
        ref.watch(localStoreProvider.select((s) => s.isFavorite(widget.movieId)));

    final loaded = ui.anime;
    var backdropUrl = loaded?.posterUrl ?? '';
    if (backdropUrl.isEmpty) backdropUrl = loaded?.coverUrl ?? '';
    if (backdropUrl.isEmpty) backdropUrl = PosterTransitionHolder.url ?? '';
    final showBackdrop = backdropUrl.isNotEmpty && !(ui.error != null && loaded == null);

    final children = <Widget>[
      // Latar poster layar penuh
      if (showBackdrop)
        Positioned.fill(
          child: NetImage(backdropUrl, alignment: Alignment.topCenter),
        ),
    ];

    if (ui.isLoading) {
      children.add(const Center(child: CircularProgressIndicator(color: AppColors.accentViolet)));
    } else if (ui.error != null && ui.anime == null) {
      children.add(
        Center(
          child: ErrorState(message: ui.error!, onRetry: () => _notifier.loadDetail()),
        ),
      );
    } else {
      children.addAll(_loadedLayers(ui, isFavorite));
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(fit: StackFit.expand, children: children),
    );
  }

  List<Widget> _loadedLayers(DetailUiState ui, bool isFavorite) {
    final anime = ui.anime;
    return [
      Positioned.fill(
        child: LayoutBuilder(
          builder: (context, c) {
            final heroHeight = c.maxHeight * 0.42;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Gradien: gambar jelas di atas, makin gelap ke bawah
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x331E1B2E),
                        Color(0x661E1B2E),
                        Color(0xE61E1B2E),
                        AppColors.backgroundDark,
                      ],
                      stops: [0.0, 0.40, 0.68, 1.0],
                    ),
                  ),
                ),
                // Makin gelap saat konten di-scroll ke atas
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _scroll,
                    builder: (context, _) {
                      final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                      final extra = (offset / heroHeight).clamp(0.0, 1.0).toDouble();
                      return Opacity(
                        opacity: extra * 0.92,
                        child: const ColoredBox(color: AppColors.backgroundDark),
                      );
                    },
                  ),
                ),
                CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: heroHeight)),
                    SliverToBoxAdapter(child: _tabRow(ui)),
                    SliverToBoxAdapter(child: _titleBlock(anime)),
                    ..._tabContent(ui, anime),
                    const SliverToBoxAdapter(child: SizedBox(height: 110)),
                  ],
                ),
              ],
            );
          },
        ),
      ),

      // Tombol Back
      Positioned(
        top: 0,
        left: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: widget.onBackClick,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0x881E1B2E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: AppColors.textWhite, size: 20),
              ),
            ),
          ),
        ),
      ),

      // Bar bawah: tombol favorit + "Tonton Sekarang"
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xE61E1B2E), AppColors.backgroundDark],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _notifier.toggleFavorite(),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFavorite ? AppColors.accentViolet : null,
                        border: isFavorite
                            ? null
                            : Border.all(color: const Color(0xCCFFFFFF), width: 1.5),
                      ),
                      child: Icon(
                        isFavorite ? Icons.check : Icons.add,
                        color: AppColors.textWhite,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () {
                          final firstEp = ui.episodes.isNotEmpty ? (ui.episodes.first.id ?? '') : '';
                          widget.onWatchEpisode(widget.movieId, firstEp);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.textWhite,
                          foregroundColor: AppColors.backgroundDark,
                          shape: const StadiumBorder(),
                        ),
                        icon: const Icon(Icons.play_arrow, size: 24),
                        label: const Text(
                          'Tonton Sekarang',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _tabRow(DetailUiState ui) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _notifier.setTab(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        _tabs[i],
                        style: TextStyle(
                          color: ui.selectedTab == i
                              ? AppColors.textWhite
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: ui.selectedTab == i ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 3,
                        width: ui.selectedTab == i ? 28 : 0,
                        decoration: BoxDecoration(
                          color: AppColors.accentViolet,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _titleBlock(AnimeItem? anime) {
    final genres = (anime?.genre ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final meta = <Widget>[
      if (!_blank(anime?.status))
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.accentViolet,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            anime!.status!,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      if (!_blank(anime?.type))
        Text(
          anime!.type!,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      if (!_blank(anime?.year))
        Text(
          '• ${anime!.year}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      if (!_blank(anime?.views))
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_outlined, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text(
              anime!.views!,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            anime?.title ?? 'Detail Anime',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 32 / 26,
            ),
          ),
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final g in genres) _OutlineChip(text: g)],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: meta,
          ),
        ],
      ),
    );
  }

  List<Widget> _tabContent(DetailUiState ui, AnimeItem? anime) {
    switch (ui.selectedTab) {
      case 0:
        return [SliverToBoxAdapter(child: _overview(anime))];
      case 1:
        return _episodesTab(ui);
      default:
        return [SliverToBoxAdapter(child: _mediaTab(ui))];
    }
  }

  Widget _overview(AnimeItem? anime) {
    final synopsis = anime?.synopsis ?? 'Belum ada sinopsis untuk anime ini.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tentang',
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  synopsis,
                  maxLines: _synopsisExpanded ? null : 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 20 / 13,
                  ),
                ),
                if (synopsis.length > 180) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _synopsisExpanded ? 'Sembunyikan' : 'Baca selengkapnya',
                        style: const TextStyle(
                          color: AppColors.accentViolet,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Informasi Tambahan',
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow(label: 'Studio', value: anime?.studio ?? '-'),
          _InfoRow(label: 'Hari Rilis', value: anime?.day ?? '-'),
          _InfoRow(label: 'Mulai Tayang', value: anime?.airedStart ?? '-'),
          _InfoRow(label: 'Selesai Tayang', value: anime?.airedEnd ?? '-'),
        ],
      ),
    );
  }

  List<Widget> _episodesTab(DetailUiState ui) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _search,
              onChanged: (v) => _notifier.onEpisodeSearchChange(v),
              maxLines: 1,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
              cursorColor: AppColors.accentViolet,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceDark,
                hintText: 'Cari episode...',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
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
      ),
      if (ui.isLoadingEpisodes)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
              ),
            ),
          ),
        )
      else if (ui.episodes.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: EmptyState(
              title: 'Belum Ada Episode',
              subtitle: 'Daftar episode belum tersedia atau sedang diperbarui',
              icon: Icons.play_arrow,
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: ui.episodes.length,
          itemBuilder: (context, i) {
            final ep = ui.episodes[i];
            return EpisodeListItem(
              episode: ep,
              onTap: () {
                final id = ep.id;
                if (id != null) widget.onWatchEpisode(widget.movieId, id);
              },
            );
          },
        ),
    ];
  }

  Widget _mediaTab(DetailUiState ui) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ui.covers.isNotEmpty) ...[
            const Text(
              'Cover & Poster',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < ui.covers.take(3).length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: AppShapes.card,
                        child: ColoredBox(
                          color: AppColors.surfaceDark,
                          child: NetImage(ui.covers[i].fullImageUrl),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (ui.cuplix.isNotEmpty) ...[
            const Text(
              'Cuplix Terkait',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final clip in ui.cuplix)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Material(
                  color: AppColors.surfaceCard,
                  borderRadius: AppShapes.card,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      final epId = clip.idEpisode;
                      if (epId != null) widget.onWatchEpisode(widget.movieId, epId);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 54,
                            height: 54,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ColoredBox(
                                color: AppColors.surfaceDark,
                                child: NetImage(clip.thumbnailUrl),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  clip.caption ?? 'Klip Anime',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textWhite,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${clip.countViews ?? '0'} views • ${clip.countLikes ?? '0'} suka',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
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
              ),
          ],
        ],
      ),
    );
  }
}

class _OutlineChip extends StatelessWidget {
  const _OutlineChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: AppShapes.pill,
        border: Border.all(color: const Color(0x99FFFFFF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textWhite,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
