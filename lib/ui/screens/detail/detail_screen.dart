import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/premium_access.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/entities.dart';
import '../../../data/models/anime_item.dart';
import '../../../data/models/episode_item.dart';
import '../../../data/models/media_item.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/common_components.dart';
import '../../components/net_image.dart';
import '../../components/poster_holder.dart';
import '../download/download_actions.dart';
import 'detail_controller.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Garis pemisah / outline kartu Zenime (CardOutlineBorder).
const Color _kOutline = Color(0xFF2A2F3A);

/// Port DetailScreen.kt (layout Zenime): hero cover penuh 360dp dengan judul,
/// tombol favorit dan tombol play crimson bulat; baris tab Info | Episode |
/// Season | Cuplix | Cover | Poster; daftar episode berbentuk grid 3 kolom.
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

class _DetailScreenState extends ConsumerState<DetailScreen>
    with SingleTickerProviderStateMixin {
  // Urutan = indeks selectedTab di DetailUiState (sama dengan DetailTab Zenime).
  static const List<String> _tabs = ['Info', 'Episode', 'Season', 'Cuplix', 'Cover', 'Poster'];

  static const double _heroHeight = 360;

  final ScrollController _scroll = ScrollController();

  /// Animasi masuk isi tab: muncul perlahan (fade) sambil bergeser sedikit.
  late final AnimationController _tabAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final CurvedAnimation _tabCurve =
      CurvedAnimation(parent: _tabAnim, curve: Curves.easeOutCubic);
  int _tabDirection = 1;

  bool _synopsisExpanded = false;

  /// Satu pintu ganti tab (tap maupun swipe) supaya animasinya selalu jalan.
  void _selectTab(int index) {
    final current = ref.read(detailControllerProvider(widget.movieId)).selectedTab;
    if (index == current) return;
    _tabDirection = index > current ? 1 : -1;
    _notifier.setTab(index);
    _tabAnim.forward(from: 0);
    // Pindah tab saat list sudah di-scroll jauh: balik ke baris tab dulu supaya
    // isi tab baru langsung kelihatan.
    if (_scroll.hasClients && _scroll.offset > _heroHeight) {
      _scroll.jumpTo(_heroHeight);
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  /// Swipe kiri = tab berikutnya, kanan = tab sebelumnya (lewat kecepatan lepas
  /// jari supaya geseran pelan atau miring tidak salah baca).
  void _onSwipeTab(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 300) return;
    final current = ref.read(detailControllerProvider(widget.movieId)).selectedTab;
    final next = v < 0 ? current + 1 : current - 1;
    if (next < 0 || next >= _tabs.length) return;
    HapticFeedback.selectionClick();
    _selectTab(next);
  }

  /// Load more otomatis: mendekati ujung bawah di tab Episode, minta halaman
  /// berikutnya (tanpa tombol).
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final ui = ref.read(detailControllerProvider(widget.movieId));
    if (ui.selectedTab != 1) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _notifier.loadMoreEpisodesIfNeeded();
    }
  }

  /// Kalau halaman yang sudah dimuat belum cukup panjang untuk di-scroll,
  /// listener tidak akan pernah terpicu, jadi cek lagi setelah frame selesai.
  void _checkFillViewport(DetailUiState ui) {
    if (ui.selectedTab != 1 || ui.isLoadingEpisodes || ui.isLoadingMoreEpisodes) return;
    if (!ui.hasMoreEpisodes || ui.episodes.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent - _scroll.position.pixels <= 600) {
        _notifier.loadMoreEpisodesIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _tabCurve.dispose();
    _tabAnim.dispose();
    super.dispose();
  }

  DetailController get _notifier =>
      ref.read(detailControllerProvider(widget.movieId).notifier);

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(detailControllerProvider(widget.movieId));
    _checkFillViewport(ui);

    final anime = ui.anime;
    final Widget body;
    if (ui.isLoading && anime == null) {
      // Poster dari kartu yang diketuk dipakai sebagai hero sementara.
      final holder = PosterTransitionHolder.url ?? '';
      body = Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: _heroHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (holder.isNotEmpty) NetImage(holder, alignment: Alignment.topCenter),
                  _heroGradient(),
                ],
              ),
            ),
          ),
          _backButton(),
          const Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
        ],
      );
    } else if (ui.error != null && anime == null) {
      body = Stack(
        children: [
          Center(
            child: ErrorState(message: ui.error!, onRetry: () => _notifier.loadDetail()),
          ),
          _backButton(),
        ],
      );
    } else {
      body = _loaded(ui);
    }

    return Scaffold(backgroundColor: AppColors.backgroundDark, body: body);
  }

  Widget _heroGradient() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x80000000),
              Color(0x00000000),
              Color(0xB30B0E14),
              AppColors.backgroundDark,
            ],
          ),
        ),
      );

  Widget _circleButton({required VoidCallback onTap, required Widget child, String? tooltip}) {
    return Material(
      color: const Color(0x99000000),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          child: SizedBox(width: 40, height: 40, child: Center(child: child)),
        ),
      ),
    );
  }

  Widget _backButton() => Positioned(
        top: MediaQuery.paddingOf(context).top + 12,
        left: 16,
        child: _circleButton(
          onTap: widget.onBackClick,
          tooltip: 'Kembali',
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
        ),
      );

  // ------------------------------------------------------------------ loaded

  Widget _loaded(DetailUiState ui) {
    final anime = ui.anime;
    final topInset = MediaQuery.paddingOf(context).top;
    final isFavorite =
        ref.watch(localStoreProvider.select((s) => s.isFavorite(widget.movieId)));

    // Hero: cover dulu (landscape), jatuh ke poster, lalu poster dari kartu.
    var heroUrl = anime?.coverUrl ?? '';
    if (heroUrl.isEmpty) heroUrl = anime?.posterUrl ?? '';
    if (heroUrl.isEmpty) heroUrl = PosterTransitionHolder.url ?? '';

    // Tombol play: lanjut episode terakhir ditonton, kalau belum pernah ->
    // episode pertama di daftar.
    final history = ref.watch(localStoreProvider.select(
      (s) => s.history.where((h) => h.movieId == widget.movieId).firstOrNull,
    ));
    final targetEpisodeId = (history?.episodeId.isNotEmpty ?? false)
        ? history!.episodeId
        : (ui.episodes.isNotEmpty ? (ui.episodes.first.id ?? '') : '');

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _onSwipeTab,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: _hero(
                  anime: anime,
                  heroUrl: heroUrl,
                  topInset: topInset,
                  isFavorite: isFavorite,
                  targetEpisodeId: targetEpisodeId,
                ),
              ),
              SliverToBoxAdapter(child: _tabRow(ui)),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              // Isi tab: fade + geser sedikit dari arah tab (sesuai TabSlide Zenime).
              AnimatedBuilder(
                animation: _tabCurve,
                builder: (context, child) => SliverPadding(
                  padding: EdgeInsets.only(
                    left: math.max(0.0, _tabDirection * 40 * (1 - _tabCurve.value)),
                    right: math.max(0.0, -_tabDirection * 40 * (1 - _tabCurve.value)),
                  ),
                  sliver: child,
                ),
                child: SliverFadeTransition(
                  opacity: _tabCurve,
                  sliver: SliverMainAxisGroup(slivers: _tabContent(ui, anime)),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 36)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hero({
    required AnimeItem? anime,
    required String heroUrl,
    required double topInset,
    required bool isFavorite,
    required String targetEpisodeId,
  }) {
    final meta = [
      anime?.year,
      anime?.type,
      anime?.status,
    ].where((e) => !_blank(e)).map((e) => e!.trim()).join(' • ');

    return SizedBox(
      height: _heroHeight + topInset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (heroUrl.isNotEmpty) NetImage(heroUrl, alignment: Alignment.topCenter),
          _heroGradient(),

          // Atas: kembali + favorit (bookmark).
          Positioned(
            top: topInset + 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _circleButton(
                  onTap: widget.onBackClick,
                  tooltip: 'Kembali',
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
                _circleButton(
                  onTap: () => _notifier.toggleFavorite(),
                  tooltip: 'Favorit',
                  child: Icon(
                    isFavorite ? Icons.bookmark : Icons.bookmark_border,
                    color: isFavorite ? AppColors.accentViolet : Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          // Judul + metadata di kiri bawah.
          Positioned(
            left: 20,
            right: 96,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anime?.title ?? 'Tanpa Judul',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 32 / 26,
                  ),
                ),
                if (meta.isNotEmpty || !_blank(anime?.views)) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (meta.isNotEmpty)
                        Flexible(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xD9FFFFFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (!_blank(anime?.views)) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.visibility_outlined,
                            size: 13, color: Color(0xB3FFFFFF)),
                        const SizedBox(width: 3),
                        Text(
                          anime!.views!,
                          style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Tombol play crimson bulat besar di kanan bawah.
          if (targetEpisodeId.isNotEmpty)
            Positioned(
              right: 20,
              bottom: 12,
              child: Material(
                color: AppColors.accentViolet,
                shape: const CircleBorder(),
                elevation: 14,
                shadowColor: AppColors.accentViolet,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => widget.onWatchEpisode(widget.movieId, targetEpisodeId),
                  child: const SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- tab row

  Widget _tabRow(DetailUiState ui) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _selectTab(i),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            maxLines: 1,
                            style: TextStyle(
                              color: ui.selectedTab == i
                                  ? AppColors.accentViolet
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight:
                                  ui.selectedTab == i ? FontWeight.w700 : FontWeight.w500,
                            ),
                            child: Text(_tabs[i]),
                          ),
                          const SizedBox(height: 8),
                          // Garis bawah "tumbuh" dari tengah saat tab dipilih.
                          LayoutBuilder(
                            builder: (context, c) => AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              height: 3,
                              width: ui.selectedTab == i ? c.maxWidth : 0,
                              decoration: const BoxDecoration(
                                color: AppColors.accentViolet,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(3),
                                  topRight: Radius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: _kOutline),
      ],
    );
  }

  List<Widget> _tabContent(DetailUiState ui, AnimeItem? anime) {
    switch (ui.selectedTab) {
      case 0:
        return [SliverToBoxAdapter(child: _infoTab(anime))];
      case 2:
        return [SliverToBoxAdapter(child: _seasonTab(ui))];
      case 3:
        return _cuplixTab(ui);
      case 4:
        return _galleryTab(
          items: ui.covers,
          loading: ui.isLoadingGallery,
          columns: 2,
          aspectRatio: 16 / 9,
          emptyMessage: 'Belum ada cover kiriman pengguna.',
        );
      case 5:
        return _galleryTab(
          items: ui.posters,
          loading: ui.isLoadingGallery,
          columns: 3,
          aspectRatio: 2 / 3,
          emptyMessage: 'Belum ada poster kiriman pengguna.',
        );
      default:
        return _episodesTab(ui, anime);
    }
  }

  Widget _centerMessage(String text, {VoidCallback? onRetry}) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Coba lagi',
                      style: TextStyle(color: AppColors.accentViolet)),
                ),
            ],
          ),
        ),
      );

  Widget _spinner() => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
          ),
        ),
      );

  // ------------------------------------------------------------------ Info

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static String? _number(String? raw) {
    final n = int.tryParse(_clean(raw) ?? '');
    if (n == null) return null;
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  List<MapEntry<String, String>> _infoRows(AnimeItem a) {
    final aired = [_clean(a.airedStart), _clean(a.airedEnd)]
        .whereType<String>()
        .where((e) => !e.startsWith('0000'))
        .join(' - ');
    final dayRaw = _clean(a.day);
    final day = dayRaw == null
        ? null
        : (dayRaw.toUpperCase() == 'RANDOM'
            ? 'Tidak tentu'
            : dayRaw[0].toUpperCase() + dayRaw.substring(1).toLowerCase());
    final status = _clean(a.status);
    return [
      if (_clean(a.type) != null) MapEntry('Tipe', _clean(a.type)!),
      if (status != null)
        MapEntry('Status', status[0].toUpperCase() + status.substring(1).toLowerCase()),
      if (_clean(a.year) != null) MapEntry('Tahun', _clean(a.year)!),
      if (_clean(a.studio) != null) MapEntry('Studio', _clean(a.studio)!),
      if (aired.isNotEmpty) MapEntry('Tayang', aired),
      if (day != null) MapEntry('Hari tayang', day),
      if (_number(a.views) != null) MapEntry('Views', _number(a.views)!),
      if (_number(a.favorites) != null) MapEntry('Favorit', _number(a.favorites)!),
    ];
  }

  Widget _infoTab(AnimeItem? anime) {
    if (anime == null) return _centerMessage('Info belum tersedia');
    final genres = (anime.genre ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final synopsis = (anime.synopsis ?? '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    final rows = _infoRows(anime);

    Widget section(String title, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (genres.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final g in genres) _OutlineChip(text: g)],
            ),
            const SizedBox(height: 20),
          ],
          if (synopsis.isNotEmpty) ...[
            section(
              'Sinopsis',
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      synopsis,
                      maxLines: _synopsisExpanded ? null : 5,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 21 / 13,
                      ),
                    ),
                    if (synopsis.length > 220)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _synopsisExpanded ? 'Tutup' : 'Baca selengkapnya',
                            style: const TextStyle(
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
            ),
            const SizedBox(height: 20),
          ],
          if (rows.isNotEmpty)
            section(
              'Informasi',
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kOutline),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) Container(height: 1, color: _kOutline),
                      _InfoRow(label: rows[i].key, value: rows[i].value),
                    ],
                  ],
                ),
              ),
            ),
          if (genres.isEmpty && synopsis.isEmpty && rows.isEmpty)
            _centerMessage('Info belum tersedia'),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- Episode

  static bool _truthy(dynamic v) =>
      v == true || v == 1 || v == '1' || (v is String && v.toLowerCase() == 'true');

  List<Widget> _episodesTab(DetailUiState ui, AnimeItem? anime) {
    // Loading dianggap premium biar gembok tidak berkedip; player tetap
    // menegakkan kunci dengan status yang sudah pasti.
    final premium = ref.watch(myPremiumProvider).valueOrNull ?? true;
    final downloads = ref.watch(localStoreProvider.select((s) => s.downloads));
    final watchedId = ref.watch(localStoreProvider.select(
      (s) => s.history.where((h) => h.movieId == widget.movieId).firstOrNull?.episodeId,
    ));
    final fallbackImage = anime?.coverUrl ?? '';

    if (ui.isLoadingEpisodes) {
      return [SliverToBoxAdapter(child: _spinner())];
    }
    if (ui.episodes.isEmpty) {
      return [SliverToBoxAdapter(child: _centerMessage('Episode belum tersedia'))];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: ui.episodes.length,
          itemBuilder: (context, i) {
            final ep = ui.episodes[i];
            final id = ep.id;
            return _EpisodeGridCard(
              key: ValueKey(id ?? 'ep_$i'),
              episode: ep,
              imageUrl: ep.imageUrl.isNotEmpty ? ep.imageUrl : fallbackImage,
              isWatched: id != null && id == watchedId,
              isLocked: isEpisodeLocked(ep.index, ui.totalEpisodes, premium),
              isNew: _truthy(ep.isNew),
              download: downloads.where((d) => d.episodeId == id).firstOrNull,
              onTap: () {
                if (id != null) widget.onWatchEpisode(widget.movieId, id);
              },
              // Tekan lama: download (khusus Premium) atau hapus download.
              onLongPress: () {
                HapticFeedback.mediumImpact();
                onEpisodeDownloadTap(
                  context,
                  ref,
                  movieId: widget.movieId,
                  anime: ui.anime,
                  episode: ep,
                );
              },
            );
          },
        ),
      ),
      if (ui.isLoadingMoreEpisodes)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 2),
              ),
            ),
          ),
        ),
    ];
  }

  // ---------------------------------------------------------------- Season

  static String? _compactCount(String? raw) {
    final n = int.tryParse(_clean(raw) ?? '');
    if (n == null) return null;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
    return '$n';
  }

  Widget _seasonTab(DetailUiState ui) {
    if (ui.isLoadingSeasons || (!ui.seasonsLoaded && ui.seasonsError == null)) {
      return _spinner();
    }
    if (ui.seasonsError != null) {
      return _centerMessage(ui.seasonsError!, onRetry: () => _notifier.loadSeasons(force: true));
    }
    if (ui.seasons.isEmpty) {
      return _centerMessage('Anime ini belum punya season lain.');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < ui.seasons.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _SeasonCard(
              season: ui.seasons[i],
              number: i + 1,
              isCurrent: ui.seasons[i].id == widget.movieId,
              views: _compactCount(ui.seasons[i].views),
              favorites: _compactCount(ui.seasons[i].favorites),
              onTap: () {
                final id = ui.seasons[i].id;
                if (id != null && id != widget.movieId) openDetail(context, id);
              },
            ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- Cuplix

  List<Widget> _cuplixTab(DetailUiState ui) {
    if (ui.isLoadingGallery) return [SliverToBoxAdapter(child: _spinner())];
    if (ui.cuplix.isEmpty) {
      return [
        SliverToBoxAdapter(child: _centerMessage('Belum ada klip Cuplix untuk anime ini.')),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 9 / 14,
          ),
          itemCount: ui.cuplix.length,
          itemBuilder: (context, i) {
            final clip = ui.cuplix[i];
            return GestureDetector(
              onTap: () {
                final epId = clip.idEpisode;
                if (epId != null) widget.onWatchEpisode(widget.movieId, epId);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.surfaceVariantDark),
                    NetImage(clip.thumbnailUrl),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xCC000000)],
                          stops: [0.5, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clip.caption ?? 'Klip Anime',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.play_arrow, size: 12, color: Colors.white70),
                              const SizedBox(width: 2),
                              Text(
                                '${clip.countViews ?? '0'}',
                                style: const TextStyle(color: Colors.white70, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  // ---------------------------------------------------------- Cover & Poster

  List<Widget> _galleryTab({
    required List<MediaGalleryItem> items,
    required bool loading,
    required int columns,
    required double aspectRatio,
    required String emptyMessage,
  }) {
    if (loading) return [SliverToBoxAdapter(child: _spinner())];
    if (items.isEmpty) return [SliverToBoxAdapter(child: _centerMessage(emptyMessage))];
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => _previewImage(items[i]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: AppColors.surfaceVariantDark,
                child: NetImage(items[i].fullImageUrl),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Pratinjau gambar penuh (zoom dengan cubit), ketuk di luar untuk menutup.
  void _previewImage(MediaGalleryItem item) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xE6000000),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: NetImage(item.fullImageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(ctx).top + 12,
              right: 16,
              child: const Icon(Icons.close, color: Colors.white, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================= grid

/// Kartu episode grid 3 kolom (port EpisodeGridCard Zenime): thumbnail persegi,
/// nomor episode di "tab" pojok kanan bawah, badge gembok/download kiri atas,
/// pita NEW kanan atas, bingkai untuk episode yang terakhir ditonton.
class _EpisodeGridCard extends StatelessWidget {
  const _EpisodeGridCard({
    super.key,
    required this.episode,
    required this.imageUrl,
    required this.isWatched,
    required this.isLocked,
    required this.isNew,
    required this.download,
    required this.onTap,
    required this.onLongPress,
  });

  final EpisodeItem episode;
  final String imageUrl;
  final bool isWatched;
  final bool isLocked;
  final bool isNew;
  final DownloadedEpisodeEntity? download;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Widget _badge({required Color color, required Widget child}) => Container(
        margin: const EdgeInsets.all(8),
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: child),
      );

  Widget? _topLeftBadge() {
    if (isLocked) {
      return _badge(
        color: AppColors.accentViolet,
        child: const Icon(Icons.lock, size: 13, color: Colors.white),
      );
    }
    final d = download;
    if (d == null) return null;
    final Widget icon;
    if (d.isActive) {
      final p = d.totalBytes > 0 ? (d.downloadedBytes / d.totalBytes).clamp(0.0, 1.0) : 0.0;
      icon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          value: p,
          strokeWidth: 2,
          color: AppColors.accentViolet,
        ),
      );
    } else if (d.isCompleted) {
      icon = const Icon(Icons.download_done, size: 14, color: Color(0xFF4CAF50));
    } else {
      icon = const Icon(Icons.error_outline, size: 14, color: Color(0xFFE57373));
    }
    return _badge(color: const Color(0x99000000), child: icon);
  }

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(20);
    final badge = _topLeftBadge();
    return Material(
      color: AppColors.surfaceVariantDark,
      borderRadius: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // Episode terkunci Premium tidak bisa di-download.
        onLongPress: isLocked || (download?.isActive ?? false) ? null : onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              NetImage(imageUrl)
            else
              const Center(
                child: Icon(Icons.play_arrow, size: 44, color: Color(0x669AA0AC)),
              ),
            if (isLocked) const ColoredBox(color: Color(0x66000000)),
            if (badge != null) Align(alignment: Alignment.topLeft, child: badge),
            if (isNew) const Align(alignment: Alignment.topRight, child: _NewRibbon()),
            // Nomor episode: "tab" berwarna sama dengan latar halaman, jadi
            // tampak seperti potongan kartu.
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.only(left: 14, right: 12, top: 6, bottom: 4),
                decoration: const BoxDecoration(
                  color: AppColors.backgroundDark,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(18)),
                ),
                child: Text(
                  (episode.index ?? '').isEmpty ? '?' : episode.index!,
                  maxLines: 1,
                  style: TextStyle(
                    color: isWatched ? AppColors.accentViolet : AppColors.textWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // Episode yang terakhir ditonton diberi bingkai.
            if (isWatched)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: shape,
                    border: Border.all(color: AppColors.accentViolet, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pita segitiga "NEW" di pojok kanan atas.
class _NewRibbon extends StatelessWidget {
  const _NewRibbon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        children: [
          CustomPaint(size: const Size(54, 54), painter: _RibbonPainter()),
          Positioned(
            left: 29,
            top: 8,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: const Text(
                'NEW',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.28, 0)
      ..lineTo(w, 0)
      ..lineTo(w, w * 0.72)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.accentViolet);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Kartu season 16:9 (port SeasonCard Zenime).
class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    required this.season,
    required this.number,
    required this.isCurrent,
    required this.views,
    required this.favorites,
    required this.onTap,
  });

  final AnimeItem season;
  final int number;
  final bool isCurrent;
  final String? views;
  final String? favorites;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(24);
    final img = (season.imageCover ?? '').isNotEmpty ? season.coverUrl : season.posterUrl;
    const shadow = [Shadow(color: Color(0xB3000000), blurRadius: 6)];

    Widget stat(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 11, shadows: shadow),
            ),
          ],
        );

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Material(
        color: AppColors.surfaceVariantDark,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        elevation: 8,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (img.isNotEmpty) NetImage(img),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xE0000000)],
                    stops: [0.35, 1.0],
                  ),
                ),
              ),
              if (isCurrent)
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accentViolet,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Text(
                      'Sedang dilihat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (isCurrent)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: shape,
                      border: Border.all(color: AppColors.accentViolet, width: 1.5),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Season $number',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        shadows: shadow,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (views != null) stat(Icons.play_circle_outline, '$views views'),
                        if (favorites != null) ...[
                          const SizedBox(height: 2),
                          stat(Icons.favorite_border, '$favorites favorit'),
                        ],
                      ],
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

class _OutlineChip extends StatelessWidget {
  const _OutlineChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: _kOutline),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textWhite,
          fontSize: 12,
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
      padding: const EdgeInsets.symmetric(vertical: 10),
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
