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
import '../../components/home_section_cards.dart' show compactCount;
import '../../components/net_image.dart';
import '../../components/poster_holder.dart';
import '../download/download_actions.dart';
import 'detail_controller.dart';
import '../../glass/glass.dart';
import '../../redesign/z_kit.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Kurva keluar cepat lalu mendarat halus (koreografi masuk halaman).
const Curve _outExpo = Cubic(0.16, 1, 0.3, 1);

/// Kurva pegas: melewati target sedikit lalu kembali.
const Curve _springy = Cubic(0.34, 1.56, 0.64, 1);

/// Potongan [a]..[b] dari timeline [t] (0..1), dilewatkan [curve].
double _iv(double t, double a, double b, [Curve curve = _outExpo]) {
  if (t <= a) return 0;
  if (t >= b) return 1;
  return curve.transform((t - a) / (b - a));
}

/// Klip hero yang mengembang dari ukuran kartu poster (sudut membulat) menjadi
/// penuh selebar layar, seperti kartu yang diketuk "membesar" jadi halaman.
class _ExpandClipper extends CustomClipper<Path> {
  const _ExpandClipper(this.p);

  final double p;

  @override
  Path getClip(Size size) {
    double lerp(double a, double b) => a + (b - a) * p;
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTRB(
      lerp(w * 0.2, 0),
      lerp(h * 0.16, 0),
      lerp(w * 0.8, w),
      lerp(h * 0.94, h),
    );
    return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(lerp(24, 0))));
  }

  @override
  bool shouldReclip(_ExpandClipper old) => old.p != p;
}

/// Klip "tirai": memperlihatkan anak dari atas ke bawah sebanyak [p] tanpa
/// mengubah ukuran layout (jadi isi di bawahnya tidak ikut melompat).
class _CurtainClipper extends CustomClipper<Rect> {
  const _CurtainClipper(this.p);

  final double p;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height * p);

  @override
  bool shouldReclip(_CurtainClipper old) => old.p != p;
}

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
    with TickerProviderStateMixin {
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

  // ------------------------------------------------------- koreografi masuk
  //
  // 1. Hero (_heroIn, jalan begitu halaman dibuka, termasuk saat loading):
  //    poster mengembang dari ukuran kartu jadi penuh, gambarnya "mendarat"
  //    dari zoom 1.16 lebih lambat dari klipnya (dua kecepatan = kesan dalam).
  // 2. Isi (_contentIn, jalan saat data pertama kali tampil): tombol atas
  //    memantul masuk, bar merah menyapu lalu membuka judul (title card),
  //    metadata menyusul, tombol play memegas masuk, baris tab terbuka seperti
  //    tirai, lalu isi tab masuk dengan animasi tab yang sudah ada.
  late final AnimationController _heroIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _contentIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _motionReady = false;
  bool _reduceMotion = false;
  bool _contentStarted = false;
  bool _tabKicked = false;

  void _onContentTick() {
    if (!_tabKicked && _contentIn.value >= 0.55) {
      _tabKicked = true;
      _tabAnim.forward(from: 0);
    }
  }

  /// Dipanggil saat isi halaman pertama kali dibangun (sebelum widget yang
  /// mendengarkan animasi ini dibuat, jadi aman diubah di tengah build).
  void _startContentIn() {
    if (_contentStarted) return;
    _contentStarted = true;
    if (_reduceMotion) {
      _tabKicked = true;
      _contentIn.value = 1;
      return;
    }
    _tabAnim.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentIn.forward(from: 0);
    });
  }

  /// Gambar hero + scrim: klip mengembang dari ukuran kartu, gambar mendarat
  /// dari zoom (lebih lambat dari klipnya).
  Widget _heroArt(String url) {
    return AnimatedBuilder(
      animation: _heroIn,
      builder: (context, child) {
        final t = _heroIn.value;
        return ClipPath(
          clipper: _ExpandClipper(_iv(t, 0, 0.6)),
          child: Transform.scale(scale: 1.16 - 0.16 * _iv(t, 0, 1), child: child),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isNotEmpty) NetImage(url, alignment: Alignment.topCenter),
          _heroGradient(),
        ],
      ),
    );
  }

  /// Muncul memantul (skala + fade) pada potongan [a] dari animasi isi.
  Widget _pop(double a, Widget child) {
    return AnimatedBuilder(
      animation: _contentIn,
      child: child,
      builder: (context, child) {
        final v = _iv(_contentIn.value, a, a + 0.3, _springy);
        return Opacity(
          opacity: v.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(scale: 0.5 + 0.5 * v, child: child),
        );
      },
    );
  }

  /// Fade + geser pada potongan [a]..[b] dari animasi isi.
  Widget _fadeIn(double a, double b, Widget child, {double dx = 0, double dy = 8}) {
    return AnimatedBuilder(
      animation: _contentIn,
      child: child,
      builder: (context, child) {
        final v = _iv(_contentIn.value, a, b);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(dx * (1 - v), dy * (1 - v)), child: child),
        );
      },
    );
  }

  /// Kartu judul: bar merah menyapu masuk dari kiri, lalu keluar ke kanan
  /// sambil membuka judul (gaya title card episode anime).
  Widget _titleWipe(Widget title) {
    return AnimatedBuilder(
      animation: _contentIn,
      child: title,
      builder: (context, child) {
        final t = _contentIn.value;
        final grow = _iv(t, 0.05, 0.22, Curves.easeInOutCubic);
        final shrink = _iv(t, 0.22, 0.40, Curves.easeInOutCubic);
        final leaving = t >= 0.22;
        return Stack(
          children: [
            Opacity(opacity: leaving ? 1.0 : 0.0, child: child),
            Positioned.fill(
              child: Align(
                alignment: leaving ? Alignment.centerRight : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: leaving ? 1 - shrink : grow,
                  heightFactor: 1,
                  child: const ColoredBox(color: AppColors.accentViolet),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) return;
    _motionReady = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _heroIn.value = 1;
    } else {
      _heroIn.forward();
    }
  }

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
    _contentIn.addListener(_onContentTick);
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
    _contentIn.removeListener(_onContentTick);
    _contentIn.dispose();
    _heroIn.dispose();
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
                  _heroArt(holder),
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

    return GlassScaffold(backgroundColor: AppColors.backgroundDark, body: body);
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
    _startContentIn();
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
              // Ringkasan + tombol tonton (redesain Samudra).
              SliverToBoxAdapter(
                child: _fadeIn(
                  0.25,
                  0.6,
                  _summary(anime, targetEpisodeId, history != null, isFavorite),
                ),
              ),
              // Baris tab terbuka seperti tirai (layout tetap, cuma klipnya).
              SliverToBoxAdapter(
                child: AnimatedBuilder(
                  animation: _contentIn,
                  child: _tabRow(ui),
                  builder: (context, child) {
                    final v = _iv(_contentIn.value, 0.4, 0.75);
                    return ClipRect(
                      clipper: _CurtainClipper(v),
                      child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
                    );
                  },
                ),
              ),
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
    // Status & tipe sudah tampil sebagai chip; meta = tahun + studio.
    final meta = [
      anime?.year,
      anime?.studio,
    ].where((e) => !_blank(e)).map((e) => e!.trim()).join(' · ');

    return SizedBox(
      height: _heroHeight + topInset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _heroArt(heroUrl),

          // Atas: kembali + favorit (bookmark), memantul masuk bergantian.
          Positioned(
            top: topInset + 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pop(
                  0.0,
                  _circleButton(
                    onTap: widget.onBackClick,
                    tooltip: 'Kembali',
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 1),
              ],
            ),
          ),

          // Poster menimpa backdrop di kiri bawah + chip, judul, meta (preview).
          Positioned(
            left: 16,
            right: 16,
            bottom: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _fadeIn(
                  0.1,
                  0.45,
                  dx: 0,
                  dy: 16,
                  Container(
                    width: 104,
                    height: 156,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x1AFFFFFF)),
                      boxShadow: const [
                        BoxShadow(color: Color(0xCC000000), blurRadius: 24, offset: Offset(0, 14), spreadRadius: -10),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: ColoredBox(
                        color: AppColors.surfaceCard,
                        child: NetImage(anime?.posterUrl ?? heroUrl),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fadeIn(
                          0.2,
                          0.5,
                          dx: -10,
                          dy: 0,
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (!_blank(anime?.status))
                                ZChip(
                                  anime!.status!.trim(),
                                  tone: anime!.status!.toLowerCase().contains('ongoing') ? ZTone.jade : ZTone.glass,
                                  live: anime!.status!.toLowerCase().contains('ongoing'),
                                ),
                              if (!_blank(anime?.type)) ZChip(anime!.type!.trim(), tone: ZTone.ghost),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _titleWipe(
                          Text(
                            anime?.title ?? 'Tanpa Judul',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: ZFont.display(size: 24, color: Colors.white, height: 1.05),
                          ),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _fadeIn(
                            0.3,
                            0.6,
                            dx: -12,
                            dy: 0,
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }

  // --------------------------------------------------------------- tab row

  Widget _tabRow(DetailUiState ui) {
    // Segmented (gaya preview): wadah gelap, indikator bergeser halus.
    final n = _tabs.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x12FFFFFF)),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth / n;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutQuint,
                  left: ui.selectedTab * w,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _selectTab(i),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    color: ui.selectedTab == i ? AppColors.textWhite : AppColors.textMuted,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  child: Text(_tabs[i]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Kartu ringkasan (views, favorit, tahun, studio) + tombol tonton lebar
  /// dan tombol simpan, sesuai preview redesain.
  Widget _summary(AnimeItem? anime, String targetEpisodeId, bool resume, bool isFavorite) {
    final synopsis = (anime?.synopsis ?? '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    final views = compactCount(anime?.views);
    final favs = compactCount(anime?.favorites);
    final stats = <(String, String)>[
      if (views != null) (views, 'Ditonton'),
      if (favs != null) (favs, 'Favorit'),
      if (!_blank(anime?.year)) (anime!.year!.trim(), 'Rilis'),
      if (!_blank(anime?.studio)) (anime!.studio!.trim(), 'Studio'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          // Baris angka gaya preview: angka utama besar di kiri, lalu
          // pasangan nilai/label kecil dipisah garis tipis.
          if (stats.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x12FFFFFF)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stats.first.$1, style: ZFont.display(size: 28, height: 1)),
                        const SizedBox(height: 2),
                        Text(
                          stats.first.$2,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                    for (var i = 1; i < stats.length; i++) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: VerticalDivider(width: 1, thickness: 1, color: Color(0x14FFFFFF)),
                      ),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stats[i].$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textWhite,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              stats[i].$2,
                              maxLines: 1,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (targetEpisodeId.isNotEmpty) ...[
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentViolet.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                          spreadRadius: -12,
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      onPressed: () => widget.onWatchEpisode(widget.movieId, targetEpisodeId),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentViolet,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: Text(
                        resume ? 'Lanjutkan Menonton' : 'Mulai Menonton',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                const Spacer(),
              Material(
                color: AppColors.surfaceDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0x12FFFFFF)),
                ),
                child: InkWell(
                  customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () => _notifier.toggleFavorite(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      isFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      color: isFavorite ? AppColors.accentViolet : AppColors.textWhite,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!_blank(anime?.genre)) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in anime!.genre!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariantDark,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ],
          // Sinopsis di atas tab (preview): 3 baris, bisa dibuka.
          if (synopsis.isNotEmpty) ...[
            const SizedBox(height: 14),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: synopsis.length > 160
                    ? () => setState(() => _synopsisExpanded = !_synopsisExpanded)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      synopsis,
                      maxLines: _synopsisExpanded ? null : 3,
                      overflow: _synopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 21 / 13,
                      ),
                    ),
                    if (synopsis.length > 160)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _synopsisExpanded ? 'Tutup' : 'Selengkapnya',
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
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
          if (rows.isEmpty) _centerMessage('Info belum tersedia'),
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
      // Daftar episode berupa baris (gaya preview): thumbnail 16:9, nomor,
      // judul, dan status di kanan.
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          separatorBuilder: (_, _) => const SizedBox(height: 10),
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
    final badge = _topLeftBadge();
    final num = (episode.index ?? '').isEmpty ? '?' : episode.index!;
    final title = (episode.title ?? '').trim();
    final views = (episode.views ?? '').trim();
    final IconData stateIcon = isLocked
        ? Icons.lock_rounded
        : (isWatched ? Icons.check_rounded : Icons.play_arrow_rounded);
    return ZPress(
      onTap: onTap,
      // Episode terkunci Premium / sedang diunduh tidak bisa di-long-press.
      onLongPress: isLocked || (download?.isActive ?? false) ? null : onLongPress,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 124,
              height: 70,
              child: ColoredBox(
                color: AppColors.surfaceVariantDark,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isNotEmpty)
                      NetImage(imageUrl)
                    else
                      const Center(child: Icon(Icons.play_arrow_rounded, size: 30, color: Color(0x669AA0AC))),
                    if (isLocked) const ColoredBox(color: Color(0x80000000)),
                    if (badge != null) Align(alignment: Alignment.topLeft, child: badge),
                    if (isNew)
                      const Positioned(top: 6, right: 6, child: ZChip('Baru', tone: ZTone.brand)),
                    // Episode terakhir ditonton: garis progres penuh di dasar.
                    if (isWatched)
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 3,
                        child: ColoredBox(color: AppColors.accentViolet),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWatched ? 'EP $num · Terakhir ditonton' : 'EP $num',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isWatched ? AppColors.accentVioletLight : AppColors.textWhite,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (title.isNotEmpty || views.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    title.isNotEmpty ? title : '$views ditonton',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isWatched
                  ? const Color(0x262FD3A2)
                  : (isLocked ? AppColors.accentVioletSubtle : AppColors.surfaceVariantDark),
            ),
            child: Icon(
              stateIcon,
              size: 16,
              color: isWatched
                  ? const Color(0xFF2FD3A2)
                  : (isLocked ? AppColors.accentVioletLight : AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
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
