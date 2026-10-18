import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/anichin_models.dart';
import '../../components/common_components.dart';
import 'donghua_detail_controller.dart';
import 'donghua_widgets.dart';

const int _episodeColumns = 3;
const Color _starYellow = Color(0xFFFFC107);

enum _DetailTab {
  episode('Episode'),
  info('Info');

  const _DetailTab(this.label);
  final String label;
}

// Field info dari situs sumber (key-nya dinamis). Tampilkan yang berguna dulu,
// buang yang isinya metadata admin (tanggal posting/update, nama pengunggah).
const List<String> _preferredInfo = [
  'status', 'tipe', 'type', 'studio', 'durasi', 'negara', 'network', 'season',
  'tanggal_rilis', 'rilis',
];
const Set<String> _hiddenInfo = {
  'diperbarui_pada', 'diposting_oleh', 'ditambahkan', 'updated_on', 'posted_by',
  'released_on',
};

List<(String, String)> _orderedInfo(Map<String, String> info) {
  final visible = Map.of(info)..removeWhere((k, _) => _hiddenInfo.contains(k));
  final first = <(String, String)>[
    for (final k in _preferredInfo)
      if (visible[k] != null) (k, visible[k]!),
  ];
  final rest = <(String, String)>[
    for (final e in visible.entries)
      if (!_preferredInfo.contains(e.key)) (e.key, e.value),
  ];
  return [...first, ...rest];
}

// "diperbarui_pada" -> "Diperbarui pada"
String _prettyKey(String key) {
  final s = key.replaceAll('_', ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Port DonghuaDetailScreen.kt: hero full-bleed + judul di atas gradient +
/// tombol play bulat, baris tab (Episode | Info), dan daftar episode grid 3
/// kolom. Desainnya disamakan dengan halaman detail anime.
class DonghuaDetailScreen extends ConsumerStatefulWidget {
  const DonghuaDetailScreen({
    super.key,
    required this.slug,
    required this.onBackClick,
    required this.onEpisodeClick,
  });

  final String slug;
  final VoidCallback onBackClick;
  final ValueChanged<String> onEpisodeClick;

  @override
  ConsumerState<DonghuaDetailScreen> createState() => _DonghuaDetailScreenState();
}

class _DonghuaDetailScreenState extends ConsumerState<DonghuaDetailScreen>
    with SingleTickerProviderStateMixin {
  _DetailTab _tab = _DetailTab.episode;
  bool _synopsisExpanded = false;

  /// Animasi isi tab: muncul perlahan (fade) sambil naik sedikit. Mulai dari
  /// value 1 supaya tampilan awal tidak ikut dianimasikan.
  late final AnimationController _tabAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final CurvedAnimation _tabCurve =
      CurvedAnimation(parent: _tabAnim, curve: Curves.easeOutCubic);

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _tabCurve.dispose();
    _tabAnim.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Satu pintu ganti tab (tap maupun geser) supaya animasinya selalu jalan.
  void _selectTab(_DetailTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _tabAnim.forward(from: 0);
    // Pindah tab saat list sudah di-scroll jauh: balik ke baris tab dulu.
    if (_scroll.hasClients && _scroll.offset > 360) {
      _scroll.jumpTo(360);
    }
  }

  /// Geser kiri = tab berikutnya, kanan = sebelumnya. Geseran vertikal tetap
  /// milik scroll.
  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 300) return;
    final tabs = _DetailTab.values;
    final i = _tab.index;
    if (v < 0 && i < tabs.length - 1) _selectTab(tabs[i + 1]);
    if (v > 0 && i > 0) _selectTab(tabs[i - 1]);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(donghuaDetailControllerProvider(widget.slug));

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Builder(builder: (context) {
        if (s.isLoading) {
          return Stack(
            children: [
              const Center(
                child: CircularProgressIndicator(color: AppColors.accentViolet),
              ),
              _backButton(),
            ],
          );
        }
        if (s.error != null) {
          return Stack(
            children: [
              ErrorState(
                message: s.error!,
                onRetry: () =>
                    ref.read(donghuaDetailControllerProvider(widget.slug).notifier).load(),
              ),
              _backButton(),
            ],
          );
        }
        return _content(s.detail!);
      }),
    );
  }

  Widget _backButton() {
    // Align supaya dapat constraint longgar (aman di dalam Stack expand).
    return Align(
      alignment: Alignment.topLeft,
      child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Material(
          color: Colors.black.withValues(alpha: 0.6),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onBackClick,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _content(AnichinAnimeDetail detail) {
    final startEpisode = startEpisodeOf(detail.episodes);
    final meta = [
      detail.info['tipe'] ?? detail.info['type'],
      detail.info['status'],
      detail.info['negara'],
    ].map((e) => e?.trim()).where((e) => e != null && e.isNotEmpty).join(' • ');
    final rating = detail.rating?.trim();
    final hasRating = rating != null && rating.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _onSwipe,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          // 1. Hero full-bleed: poster + gradient + judul + tombol play
          SliverToBoxAdapter(
            child: SizedBox(
              height: 360,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Donghua cuma punya poster potret, jadi di-crop dari atas
                  // supaya wajah/karakter tetap kelihatan.
                  DonghuaImage(detail.thumbnail, alignment: Alignment.topCenter),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.5),
                          Colors.transparent,
                          AppColors.backgroundDark.withValues(alpha: 0.7),
                          AppColors.backgroundDark,
                        ],
                      ),
                    ),
                  ),
                  _backButton(),
                  Positioned(
                    left: 20,
                    right: 96,
                    bottom: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            height: 32 / 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (hasRating || meta.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (hasRating) ...[
                                const Icon(Icons.star, size: 16, color: _starYellow),
                                const SizedBox(width: 8),
                                Text(
                                  rating,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (meta.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    hasRating ? '• $meta' : meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Tombol play bulat: mulai dari episode paling awal
                  if (startEpisode != null)
                    Positioned(
                      right: 20,
                      bottom: 12,
                      child: Material(
                        color: AppColors.accentViolet,
                        shape: const CircleBorder(),
                        elevation: 14,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => widget.onEpisodeClick(startEpisode.slug),
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
            ),
          ),

          // 2. Baris tab
          SliverToBoxAdapter(child: _tabRow()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // 3. Isi tab: fade-in + naik 18px (easeOutCubic) tiap ganti tab.
          AnimatedBuilder(
            animation: _tabCurve,
            builder: (context, child) => SliverPadding(
              padding: EdgeInsets.only(top: 18 * (1 - _tabCurve.value)),
              sliver: child,
            ),
            child: SliverFadeTransition(
              opacity: _tabCurve,
              sliver: _tab == _DetailTab.episode
                  ? _episodeSliver(detail)
                  : SliverToBoxAdapter(child: _infoTab(detail)),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 36)),
        ],
      ),
    );
  }

  // Baris tab (teks berubah warna + garis bawah).
  Widget _tabRow() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final tab in _DetailTab.values)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _selectTab(tab),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              color: tab == _tab
                                  ? AppColors.accentViolet
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: tab == _tab ? FontWeight.w700 : FontWeight.w500,
                            ),
                            child: Text(tab.label, maxLines: 1),
                          ),
                          const SizedBox(height: 8),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 260),
                            widthFactor: tab == _tab ? 1 : 0,
                            child: Container(
                              height: 3,
                              decoration: const BoxDecoration(
                                color: AppColors.accentViolet,
                                borderRadius:
                                    BorderRadius.vertical(top: Radius.circular(3)),
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
        Container(height: 1, color: AppColors.surfaceElevated),
      ],
    );
  }

  // Grid episode 3 kolom.
  Widget _episodeSliver(AnichinAnimeDetail detail) {
    if (detail.episodes.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Episode belum tersedia',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _episodeColumns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final ep = detail.episodes[i];
            return _EpisodeCard(
              key: ValueKey(ep.slug),
              ep: ep,
              fallbackThumbnail: detail.thumbnail,
              onTap: () => widget.onEpisodeClick(ep.slug),
            );
          },
          childCount: detail.episodes.length,
        ),
      ),
    );
  }

  // Tab Info: genre, sinopsis, rincian (semua dari respons detail).
  Widget _infoTab(AnichinAnimeDetail detail) {
    var synopsis = detail.sinopsis
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    // Data sumber kadang menempelkan judul di awal sinopsis.
    if (synopsis.startsWith(detail.name)) {
      synopsis = synopsis.substring(detail.name.length).trim();
    }
    final rows = _orderedInfo(detail.info);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.genres.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in detail.genres)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: AppColors.surfaceElevated),
                    ),
                    child: Text(
                      g,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (synopsis.isNotEmpty) ...[
            _infoSection(
              'Sinopsis',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    alignment: Alignment.topCenter,
                    child: Text(
                      synopsis,
                      maxLines: _synopsisExpanded ? null : 5,
                      overflow: _synopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 21 / 14,
                      ),
                    ),
                  ),
                  if (synopsis.length > 220)
                    GestureDetector(
                      onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
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
            const SizedBox(height: 20),
          ],
          if (rows.isNotEmpty)
            _infoSection(
              'Rincian',
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surfaceElevated),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 38,
                              child: Text(
                                _prettyKey(rows[i].$1),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 62,
                              child: Text(
                                rows[i].$2,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < rows.length - 1)
                        Container(
                          height: 1,
                          color: AppColors.surfaceElevated.withValues(alpha: 0.5),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          if (detail.genres.isEmpty && synopsis.isEmpty && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Belum ada informasi untuk donghua ini.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// Kartu episode: thumbnail persegi + nomor di pojok kanan bawah.
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    super.key,
    required this.ep,
    required this.fallbackThumbnail,
    required this.onTap,
  });

  final AnichinEpisodeRef ep;
  final String? fallbackThumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final own = (ep.thumbnail ?? '').trim().isNotEmpty ? ep.thumbnail : null;
    final thumbnail = own ?? fallbackThumbnail;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.surfaceVariantDark),
            if ((thumbnail ?? '').isNotEmpty)
              // Thumbnail episode biasanya landscape (tengah); poster fallback
              // potret (atas).
              DonghuaImage(
                thumbnail,
                alignment: own != null ? Alignment.center : Alignment.topCenter,
              )
            else
              Center(
                child: Icon(
                  Icons.play_arrow,
                  size: 44,
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                ),
              ),
            // Nomor episode: "tab" di pojok kanan bawah, warna sama dengan latar halaman.
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 12, 4),
                decoration: const BoxDecoration(
                  color: AppColors.backgroundDark,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(18)),
                ),
                child: Text(
                  episodeLabelOrNull(ep) ?? '?',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
