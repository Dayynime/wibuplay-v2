import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../components/name_deco_styles.dart';
import '../../components/net_image.dart';
import '../../glass/glass.dart';
import '../../redesign/z_kit.dart';
import '../auth/login_posters.dart';

// -----------------------------------------------------------------------------
// Intro Zenime (redesain Nov 2026, gaya kit "Samudra").
// - Latar polos + screentone, judul Sora rata kiri, label Jepang kecil.
// - Tiap slide memperagakan potongan UI app (kartu anime, unduhan, komik,
//   chat clan, leaderboard, Premium).
// - Animasi masuk jalan sekali tiap slide dibuka (satu controller per slide);
//   kalau HP diset "hapus animasi", semuanya langsung tampil diam.
// -----------------------------------------------------------------------------

// Poster publik MyAnimeList, cuma di-link seperti kLoginPosters.
const String _kDonghuaPoster = 'https://cdn.myanimelist.net/images/anime/1438/101531l.jpg';
const String _kComicPoster = 'https://cdn.myanimelist.net/images/manga/4/221353l.jpg';

const Color _gold = Color(0xFFF6BE4F);
const Duration _enterDur = Duration(milliseconds: 2800);

class _Slide {
  const _Slide(this.no, this.jp, this.line1, this.line2, this.desc);

  final String no;
  final String jp;
  final String line1;
  final String line2;
  final String desc;
}

const List<_Slide> _slides = [
  _Slide('01', 'アニメ見放題', 'Nonton anime', 'tanpa batas.',
      'Ribuan judul favoritmu siap ditonton langsung dari HP, kapan aja.'),
  _Slide('02', 'オフライン', 'Download, nonton', 'offline.',
      'Simpan episode favorit, terus tonton tanpa kuota di mana pun kamu berada.'),
  _Slide('03', '漫画・ドンファ', 'Komik &', 'donghua juga ada.',
      'Baca komik favoritmu dan nonton donghua terbaru, semua di satu aplikasi.'),
  _Slide('04', 'クラン', 'Ngobrol bareng,', 'gabung clan.',
      'Chat Global, tambah teman, dan bikin Clan bareng sesama penonton.'),
  _Slide('05', 'ランキング', 'Naik level,', 'jadi legenda.',
      'Kumpulin XP tiap nonton dan panjat Leaderboard bareng yang lain.'),
  _Slide('06', 'プレミアム', 'Upgrade ke', 'Premium.',
      'Kualitas sampai 1080p, tanpa iklan, dan XP nonton dobel biar naik level makin cepat.'),
];

// -----------------------------------------------------------------------------
// Layar utama
// -----------------------------------------------------------------------------

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Dipanggil saat user menekan "Mulai Sekarang" atau "Lewati".
  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _slides.length - 1) {
      widget.onFinished();
    } else {
      _pc.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;

    return PopScope(
      // Back di slide > 1 = mundur satu slide, bukan keluar app.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _pc.previousPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      },
      child: GlassScaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Stack(
          children: [
            const Positioned(
              top: 0,
              right: 0,
              width: 230,
              height: 300,
              child: ZScreentone(),
            ),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(isLast: isLast, onSkip: widget.onFinished),
                  Expanded(
                    child: PageView.builder(
                      controller: _pc,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) => _SlidePage(index: i, active: _page == i),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    child: Column(
                      children: [
                        _Progress(page: _page, count: _slides.length),
                        const SizedBox(height: 16),
                        _CtaButton(isLast: isLast, onTap: _next),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isLast, required this.onSkip});

  final bool isLast;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/images/logo.jpg', width: 28, height: 28),
            ),
            const SizedBox(width: 9),
            Text('Zenime', style: ZFont.display(size: 17)),
            const Spacer(),
            AnimatedOpacity(
              opacity: isLast ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: isLast,
                child: GestureDetector(
                  onTap: onSkip,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Text(
                      'Lewati',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
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

// -----------------------------------------------------------------------------
// Animasi masuk per slide
// -----------------------------------------------------------------------------

/// Membagikan progres animasi masuk slide (0..1 selama [_enterDur]).
class _Enter extends InheritedWidget {
  const _Enter({required this.t, required super.child});

  final Animation<double> t;

  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Enter>()!.t;

  @override
  bool updateShouldNotify(_Enter old) => old.t != t;
}

/// Kurva potongan waktu: mulai di [atMs], selama [durMs].
Animation<double> _seg(Animation<double> t, int atMs, int durMs, [Curve curve = Curves.easeOutCubic]) {
  final total = _enterDur.inMilliseconds;
  final a = (atMs / total).clamp(0.0, 1.0);
  final b = ((atMs + durMs) / total).clamp(a, 1.0);
  return _Part(t, Interval(a, b, curve: curve));
}

/// Seperti CurvedAnimation tapi tanpa listener sendiri (aman dibuat tiap build).
class _Part extends Animation<double> with AnimationWithParentMixin<double> {
  _Part(this.parent, this.curve);

  @override
  final Animation<double> parent;
  final Curve curve;

  @override
  double get value => curve.transform(parent.value);
}

/// Muncul: fade + naik [dy] px (atau geser dari kiri kalau [dx] diisi).
class _In extends StatelessWidget {
  const _In({required this.at, required this.child, this.dur = 500, this.dy = 14, this.dx = 0});

  final int at;
  final int dur;
  final double dy;
  final double dx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = _seg(_Enter.of(context), at, dur);
    return AnimatedBuilder(
      animation: a,
      builder: (context, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(dx * (1 - a.value), dy * (1 - a.value)), child: child),
      ),
      child: child,
    );
  }
}

/// Muncul membesar dengan pantulan (chip, panel manga).
class _Pop extends StatelessWidget {
  const _Pop({required this.at, required this.child, this.from = 0, this.dur = 380});

  final int at;
  final int dur;
  final double from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = _seg(_Enter.of(context), at, dur, Curves.easeOutBack);
    final f = _seg(_Enter.of(context), at, dur ~/ 2, Curves.linear);
    return AnimatedBuilder(
      animation: a,
      builder: (context, child) => Opacity(
        opacity: f.value,
        child: Transform.scale(scale: from + (1 - from) * a.value, child: child),
      ),
      child: child,
    );
  }
}

/// Baris teks judul yang naik dari balik garis.
class _MaskLine extends StatelessWidget {
  const _MaskLine({required this.at, required this.child});

  final int at;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = _seg(_Enter.of(context), at, 600);
    return ClipRect(
      child: AnimatedBuilder(
        animation: a,
        builder: (context, child) =>
            FractionalTranslation(translation: Offset(0, 1.05 * (1 - a.value)), child: child),
        child: child,
      ),
    );
  }
}

/// Bar progres yang terisi sampai [to].
class _FillBar extends StatelessWidget {
  const _FillBar({required this.at, required this.to, this.height = 4});

  final int at;
  final double to;
  final double height;

  @override
  Widget build(BuildContext context) {
    final a = _seg(_Enter.of(context), at, 1600);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: AppColors.surfaceElevated,
          child: AnimatedBuilder(
            animation: a,
            builder: (context, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: to * a.value,
              child: const ColoredBox(color: AppColors.accentViolet),
            ),
          ),
        ),
      ),
    );
  }
}

/// Angka yang menghitung naik ke [to].
class _CountUp extends StatelessWidget {
  const _CountUp({required this.at, required this.to, required this.style, this.dots = false});

  final int at;
  final int to;
  final TextStyle style;
  final bool dots;

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final a = _seg(_Enter.of(context), at, 1300);
    return AnimatedBuilder(
      animation: a,
      builder: (context, _) {
        final v = (to * a.value).round();
        return Text(dots ? _fmt(v) : '$v', style: style);
      },
    );
  }
}

class _SlidePage extends StatefulWidget {
  const _SlidePage({required this.index, required this.active});

  final int index;
  final bool active;

  @override
  State<_SlidePage> createState() => _SlidePageState();
}

class _SlidePageState extends State<_SlidePage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _enterDur);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _c.value = 1;
    } else if (widget.active && _c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(_SlidePage old) {
    super.didUpdateWidget(old);
    if (_still) return;
    if (widget.active && !old.active) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _slides[widget.index];
    final title = ZFont.display(size: 29, height: 1.12, letterSpacing: -0.6);

    return _Enter(
      t: _c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: LayoutBuilder(
                builder: (context, c) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: c.maxWidth,
                    child: RepaintBoundary(child: _hero(widget.index)),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _In(
                  at: 50,
                  child: Row(
                    children: [
                      Text(s.no, style: ZFont.display(size: 11, letterSpacing: 0.5)),
                      Container(
                        width: 16,
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: AppColors.textMuted,
                      ),
                      Text(s.jp, style: ZFont.jp()),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _MaskLine(at: 100, child: Text(s.line1, style: title)),
                _MaskLine(
                  at: 180,
                  child: Text(s.line2, style: title.copyWith(color: AppColors.accentViolet)),
                ),
                const SizedBox(height: 10),
                _In(
                  at: 280,
                  child: SizedBox(
                    height: 44,
                    child: Text(
                      s.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.5),
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

  Widget _hero(int i) => switch (i) {
        0 => const _HeroAnime(),
        1 => const _HeroOffline(),
        2 => const _HeroComic(),
        3 => const _HeroClan(),
        4 => const _HeroRank(),
        _ => const _HeroPremium(),
      };
}

// -----------------------------------------------------------------------------
// Progres & tombol
// -----------------------------------------------------------------------------

class _Progress extends StatelessWidget {
  const _Progress({required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: ColoredBox(
                  color: AppColors.surfaceElevated,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: i <= page ? 1 : 0),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: v,
                      child: ColoredBox(
                        color: AppColors.accentViolet.withValues(alpha: i == page ? 1 : 0.45),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.isLast, required this.onTap});

  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isLast ? const Color(0xFF1A1206) : Colors.white;
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      height: 52,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isLast ? _gold : AppColors.accentViolet,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isLast ? 'Mulai Sekarang' : 'Lanjut',
            style: TextStyle(color: fg, fontSize: 15.5, fontWeight: FontWeight.w800),
          ),
          if (!isLast) ...[
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, color: fg, size: 20),
          ],
        ],
      ),
    );
    return ZPress(
      onTap: onTap,
      child: isLast ? ZSheen(radius: BorderRadius.circular(14), opacity: 0.45, child: body) : body,
    );
  }
}

// -----------------------------------------------------------------------------
// Potongan UI bersama
// -----------------------------------------------------------------------------

BoxDecoration _cardDeco([Color? border]) => BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border ?? const Color(0x0FFFFFFF)),
    );

const Divider _rowLine = Divider(height: 1, thickness: 1, color: Color(0x0DFFFFFF));

class _Thumb extends StatelessWidget {
  const _Thumb(this.url, {this.w = 52, this.h = 70, this.r = 9, this.gray = false});

  final String url;
  final double w;
  final double h;
  final double r;
  final bool gray;

  @override
  Widget build(BuildContext context) {
    Widget img = NetImage(url);
    if (gray) img = ColorFiltered(colorFilter: _grayscale, child: img);
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: w,
        height: h,
        child: ColoredBox(color: AppColors.surfaceVariantDark, child: img),
      ),
    );
  }
}

const ColorFilter _grayscale = ColorFilter.matrix(<double>[
  0.36, 0.72, 0.12, 0, -30, //
  0.36, 0.72, 0.12, 0, -30, //
  0.36, 0.72, 0.12, 0, -30, //
  0, 0, 0, 1, 0,
]);

class _Avatar extends StatelessWidget {
  const _Avatar(this.url);

  final String url;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: SizedBox(
          width: 30,
          height: 30,
          child: ColoredBox(color: AppColors.surfaceVariantDark, child: NetImage(url)),
        ),
      );
}

class _SecTitle extends StatelessWidget {
  const _SecTitle(this.title, this.note);

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Row(
          children: [
            Text(title, style: ZFont.display(size: 14)),
            const Spacer(),
            Text(note, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _LvTag extends StatelessWidget {
  const _LvTag(this.lv);

  final int lv;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: const Color(0x29F6BE4F), borderRadius: BorderRadius.circular(5)),
        child: Text('Lv $lv', style: const TextStyle(color: _gold, fontSize: 9, fontWeight: FontWeight.w800)),
      );
}

const TextStyle _rowTitle = TextStyle(color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w800);
const TextStyle _rowMeta = TextStyle(color: AppColors.textSecondary, fontSize: 11.5);

// -----------------------------------------------------------------------------
// 01 Anime
// -----------------------------------------------------------------------------

class _HeroAnime extends StatelessWidget {
  const _HeroAnime();

  @override
  Widget build(BuildContext context) {
    Widget mini(String url, Widget chip) => Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: AppColors.surfaceVariantDark),
                  NetImage(url),
                  Positioned(left: 6, top: 6, child: chip),
                ],
              ),
            ),
          ),
        );

    return Column(
      children: [
        _In(
          at: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 250,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: AppColors.surfaceVariantDark),
                  NetImage(kLoginPosters[0], alignment: const Alignment(0, -0.6)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.35, 1],
                        colors: [Color(0x000B0E14), Color(0xED0B0E14)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            ZChip('Populer #1', tone: ZTone.brand),
                            SizedBox(width: 6),
                            ZChip('Ongoing', tone: ZTone.scrim, live: true),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Sousou no Frieren', style: ZFont.display(size: 19)),
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            ZChip('EP 28'),
                            SizedBox(width: 6),
                            ZChip('9.3', icon: Icons.star_rounded),
                            SizedBox(width: 6),
                            ZChip('1080p'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _In(
          at: 250,
          child: Row(
            children: [
              mini(kLoginPosters[2], const ZChip('EP 64', tone: ZTone.scrim)),
              const SizedBox(width: 10),
              mini(kLoginPosters[3], const ZChip('Baru', tone: ZTone.brand)),
              const SizedBox(width: 10),
              mini(kLoginPosters[1], const ZChip('EP 12', tone: ZTone.scrim)),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 02 Offline
// -----------------------------------------------------------------------------

class _HeroOffline extends StatelessWidget {
  const _HeroOffline();

  @override
  Widget build(BuildContext context) {
    Widget row(String url, String title, String meta, Widget tail) => Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _Thumb(url),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(meta, style: _rowMeta),
                    const SizedBox(height: 7),
                    tail,
                  ],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _In(at: 0, child: _SecTitle('Unduhan', '3 episode · 1,1 GB')),
        _In(
          at: 60,
          child: Container(
            decoration: _cardDeco(),
            child: Column(
              children: [
                row(kLoginPosters[0], 'Sousou no Frieren', 'EP 28 · 1080p · 412 MB',
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: _Pop(at: 1600, child: ZChip('✓ Tersimpan', tone: ZTone.jade)),
                    )),
                _rowLine,
                row(kLoginPosters[3], 'JoJo: Steel Ball Run', 'EP 3 · 720p · 68%',
                    const _FillBar(at: 400, to: .68)),
                _rowLine,
                row(kLoginPosters[2], 'FMA Brotherhood', 'EP 12 · 720p · Antre',
                    const _FillBar(at: 400, to: .14)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _In(
          at: 300,
          child: Container(
            decoration: _cardDeco(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: const Row(
              children: [
                Icon(Icons.airplanemode_active_rounded, size: 16, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Mode pesawat aktif',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                ZChip('Bisa ditonton', tone: ZTone.jade, live: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 03 Komik & Donghua
// -----------------------------------------------------------------------------

class _HeroComic extends StatelessWidget {
  const _HeroComic();

  @override
  Widget build(BuildContext context) {
    Widget tab(String t, bool on) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: on ? AppColors.textWhite : AppColors.surfaceVariantDark,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(t,
              style: TextStyle(
                color: on ? AppColors.backgroundDark : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
        );

    BoxDecoration panel() => BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF111111), width: 2));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          at: 0,
          child: Row(children: [tab('Anime', false), const SizedBox(width: 6), tab('Komik', true), const SizedBox(width: 6), tab('Donghua', false)]),
        ),
        const SizedBox(height: 14),
        Container(
          height: 205,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: const Color(0xFFEDEAE3), borderRadius: BorderRadius.circular(14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: _Pop(
                  at: 150,
                  from: 1.15,
                  child: Container(
                    decoration: panel(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColorFiltered(colorFilter: _grayscale, child: NetImage(_kComicPoster)),
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF111111), width: 2),
                            ),
                            child: const Text('!?',
                                style: TextStyle(color: Color(0xFF111111), fontSize: 10, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Pop(
                        at: 450,
                        from: 1.15,
                        child: Container(
                          decoration: panel(),
                          child: const Stack(
                            fit: StackFit.expand,
                            children: [
                              _Halftone(),
                              Positioned(right: 6, bottom: 2, child: _Sfx()),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: _Pop(
                        at: 750,
                        from: 1.15,
                        child: Container(
                          decoration: panel(),
                          child: ColorFiltered(colorFilter: _grayscale, child: NetImage(_kDonghuaPoster)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _In(
          at: 1000,
          child: Container(
            decoration: _cardDeco(),
            padding: const EdgeInsets.all(10),
            child: const Row(
              children: [
                _Thumb(_kDonghuaPoster, w: 44, h: 58, r: 8),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chapter 142', style: _rowTitle),
                      SizedBox(height: 3),
                      Text('Lanjut baca · halaman 12/38', style: _rowMeta),
                    ],
                  ),
                ),
                ZChip('Baca', tone: ZTone.brand),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Titik screentone hitam rapat (panel manga).
class _Halftone extends StatelessWidget {
  const _Halftone();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _HalftonePainter());
}

class _HalftonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF111111);
    for (double y = 2.5; y < size.height; y += 5) {
      for (double x = 2.5; x < size.width; x += 5) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_HalftonePainter old) => false;
}

/// Tulisan efek suara "DOON" yang bergetar sebentar.
class _Sfx extends StatelessWidget {
  const _Sfx();

  @override
  Widget build(BuildContext context) {
    final a = _seg(_Enter.of(context), 1200, 700, Curves.linear);
    return AnimatedBuilder(
      animation: a,
      builder: (context, child) {
        final v = a.value;
        final shake = v > 0 && v < 1 ? ((v * 12).floor().isEven ? 2.0 : -2.0) : 0.0;
        return Transform.translate(
          offset: Offset(shake, -shake / 2),
          child: Transform.rotate(angle: -0.14, child: child),
        );
      },
      child: Stack(
        children: [
          Builder(builder: (context) {
            // TextStyle tidak boleh punya color DAN foreground sekaligus.
            final base = ZFont.display(size: 26, weight: FontWeight.w900, letterSpacing: 0);
            return Text(
              'DOON',
              style: TextStyle(
                fontFamily: base.fontFamily,
                fontFamilyFallback: base.fontFamilyFallback,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 4
                  ..color = Colors.white,
              ),
            );
          }),
          Text('DOON', style: ZFont.display(size: 26, weight: FontWeight.w900, color: const Color(0xFF111111), letterSpacing: 0)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 04 Clan & chat
// -----------------------------------------------------------------------------

class _HeroClan extends StatelessWidget {
  const _HeroClan();

  @override
  Widget build(BuildContext context) {
    Widget msg(String av, String name, NameDecoStyle deco, int lv, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Avatar(av),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NameDecoText(name: name, style: deco, fontSize: 11, maxWidth: 120),
                      const SizedBox(width: 4),
                      _LvTag(lv),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceVariantDark,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                    child: Text(text, style: const TextStyle(color: AppColors.textWhite, fontSize: 13, height: 1.35)),
                  ),
                ],
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          at: 0,
          child: Container(
            decoration: _cardDeco(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.accentViolet, borderRadius: BorderRadius.circular(10)),
                  child: Text('Z', style: ZFont.display(size: 16, weight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Akatsuki ID', style: _rowTitle),
                      SizedBox(height: 2),
                      Text('48 anggota · 12 online', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                const ZChip('Live', tone: ZTone.jade, live: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _In(at: 300, child: msg(kLoginPosters[2], 'Raka', NameDecoStyle.neonSign, 31, 'Frieren eps baru udah keluar woi 🔥')),
        _In(at: 1200, child: msg(kLoginPosters[3], 'Nadia', NameDecoStyle.royalGold, 18, 'Nobar jam 8 yuk, aku bikin room')),
        _In(
          at: 2000,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.accentViolet,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: const Text('Gas, aku join 🙌', style: TextStyle(color: Colors.white, fontSize: 13, height: 1.35)),
            ),
          ),
        ),
        const _In(
          at: 2400,
          child: Row(
            children: [
              ZChip('Nobar', icon: Icons.live_tv_rounded),
              SizedBox(width: 6),
              ZChip('DM', icon: Icons.chat_bubble_rounded),
              SizedBox(width: 6),
              ZChip('Teman', icon: Icons.group_rounded),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 05 Level & Leaderboard
// -----------------------------------------------------------------------------

class _HeroRank extends StatelessWidget {
  const _HeroRank();

  @override
  Widget build(BuildContext context) {
    Widget rk(int at, int n, Color c, String av, String name, String xp) => _In(
          at: at,
          dy: 0,
          dx: -20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(width: 30, child: ZRankNumber(n, size: 34, color: c)),
                const SizedBox(width: 12),
                _Avatar(av),
                const SizedBox(width: 12),
                Expanded(child: Text(name, style: _rowTitle)),
                Text(xp, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );

    const meta = TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _In(at: 0, child: _SecTitle('Top XP minggu ini', 'Reset tiap minggu')),
        Container(
          decoration: _cardDeco(),
          child: Column(
            children: [
              rk(150, 1, _gold, kLoginPosters[2], 'Raka', '12.480 XP'),
              _rowLine,
              rk(300, 2, const Color(0xFFC9D1DC), kLoginPosters[3], 'Nadia', '11.902 XP'),
              _rowLine,
              rk(450, 3, const Color(0xFFD38A5A), kLoginPosters[0], 'Dimas', '9.315 XP'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _In(
          at: 600,
          child: Container(
            decoration: _cardDeco(),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Level kamu', style: meta),
                    const Spacer(),
                    _CountUp(at: 800, to: 2140, dots: true, style: meta),
                    const Text(' / 3.000 XP', style: meta),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Lv ', style: ZFont.display(size: 26)),
                    _CountUp(at: 800, to: 24, style: ZFont.display(size: 26)),
                    const SizedBox(width: 8),
                    const Text('→ Lv 25', style: meta),
                  ],
                ),
                const SizedBox(height: 10),
                const _FillBar(at: 800, to: .71, height: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 06 Premium
// -----------------------------------------------------------------------------

class _HeroPremium extends StatelessWidget {
  const _HeroPremium();

  @override
  Widget build(BuildContext context) {
    const feats = ['Kualitas sampai 1080p', 'Tanpa iklan sama sekali', 'XP nonton 2×', 'Badge Premium di profil'];

    Widget cmp(String label, String value, bool premium) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: premium ? const Color(0x1AF6BE4F) : AppColors.surfaceVariantDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      color: premium ? _gold : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(value, style: ZFont.display(size: 17, color: premium ? _gold : AppColors.textWhite)),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          at: 0,
          child: ZSheen(
            radius: BorderRadius.circular(16),
            opacity: 0.16,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x59F6BE4F)),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: [0, 0.6],
                  colors: [Color(0xFF1F1A10), AppColors.surfaceDark],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ZChip('Premium', icon: Icons.workspace_premium_rounded, tone: ZTone.gold),
                  const SizedBox(height: 12),
                  Text('Zenime Premium', style: ZFont.display(size: 28)),
                  const SizedBox(height: 2),
                  const Text('Nonton lebih jernih, tanpa gangguan',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 12),
                  for (var i = 0; i < feats.length; i++)
                    _In(
                      at: 450 + i * 150,
                      dy: 0,
                      dx: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x0FFFFFFF)))),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(color: Color(0x29F6BE4F), shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 13, color: _gold),
                            ),
                            const SizedBox(width: 10),
                            Text(feats[i],
                                style: const TextStyle(
                                    color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _In(
          at: 1100,
          child: Row(children: [cmp('Gratis', '720p', false), const SizedBox(width: 8), cmp('Premium', '1080p', true)]),
        ),
      ],
    );
  }
}
