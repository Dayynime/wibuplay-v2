import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers.dart';
import '../../components/net_image.dart';
import '../../components/top_giver_badge.dart';
import '../../components/zenime_mascot.dart';
import '../auth/login_posters.dart';
import '../../redesign/z_kit.dart';
import '../wallpaper/wallpaper_screen.dart';

// -----------------------------------------------------------------------------
// "Yang baru" — tutorial singkat fitur baru, muncul SEKALI setelah update.
//
// Cara pakai di update berikutnya: ganti [kWhatsNewId] (mis. '3.2.5') dan isi
// halaman di [_WhatsNewScreen]. User yang id tersimpannya beda akan melihatnya
// sekali; install baru langsung ditandai sudah lihat (lewat OnboardingGate).
// -----------------------------------------------------------------------------

const String kWhatsNewId = '3.2.5';


/// Dipasang di dalam AuthGate (user sudah login), membungkus AppShell.
class WhatsNewHost extends ConsumerStatefulWidget {
  const WhatsNewHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WhatsNewHost> createState() => _WhatsNewHostState();
}

class _WhatsNewHostState extends ConsumerState<WhatsNewHost> {
  @override
  void initState() {
    super.initState();
    final store = ref.read(localStoreProvider);
    if (store.whatsNewSeenId == kWhatsNewId) return;
    // Tandai dulu, jadi tetap sekali walau app ditutup di tengah tutorial.
    unawaited(store.setWhatsNewSeenId(kWhatsNewId));
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (_, __, ___) => const _WhatsNewScreen(),
          transitionsBuilder: (_, a, __, child) {
            final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: c,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(c),
                child: child,
              ),
            );
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// -----------------------------------------------------------------------------
// Layar
// -----------------------------------------------------------------------------

class _Page {
  const _Page(this.jp, this.line1, this.line2, this.desc);

  final String jp;
  final String line1;
  final String line2;
  final String desc;
}

const List<_Page> _pages = [
  _Page('新しい見た目', 'Tampilan', 'baru.',
      'Navbar kaca, poster "terbang" ke detail, kredit ala opening anime, dan kenalan sama maskot Zenime!'),
  _Page('トップギバー', 'Top Giver', 'makin keren.',
      'Peringkat 1 sampai 10 punya badge & animasi sendiri. Masuk 10 besar dan pamerkan badge-mu di chat.'),
  _Page('チャット', 'Wallpaper', 'di chat.',
      'Pasang wallpaper koleksimu di bubble chat (dilihat semua orang) atau jadikan latar halaman chat.'),
];

class _WhatsNewScreen extends StatefulWidget {
  const _WhatsNewScreen();

  @override
  State<_WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<_WhatsNewScreen> {
  final PageController _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _next() {
    if (_page < _pages.length - 1) {
      _pc.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      return;
    }
    // Halaman terakhir: langsung ke halaman Wallpaper.
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute<void>(builder: (_) => const WallpaperScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          const Positioned(top: 0, right: 0, width: 230, height: 300, child: ZScreentone()),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 60,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const ZChip('BARU · v$kWhatsNewId', tone: ZTone.brand),
                        const Spacer(),
                        GestureDetector(
                          onTap: _close,
                          behavior: HitTestBehavior.opaque,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                            child: Text(
                              'Tutup',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => _PageView(index: i, active: _page == i),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: Column(
                    children: [
                      _Progress(page: _page, count: _pages.length),
                      const SizedBox(height: 16),
                      ZPress(
                        onTap: _next,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          height: 52,
                          width: double.infinity,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accentViolet,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isLast ? 'Coba Sekarang' : 'Lanjut',
                                style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(width: 8),
                              Icon(isLast ? Icons.wallpaper_rounded : Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Animasi masuk (sama dengan intro)
// -----------------------------------------------------------------------------

const Duration _enterDur = Duration(milliseconds: 2400);

class _Enter extends InheritedWidget {
  const _Enter({required this.t, required super.child});

  final Animation<double> t;

  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Enter>()!.t;

  @override
  bool updateShouldNotify(_Enter old) => old.t != t;
}

class _Part extends Animation<double> with AnimationWithParentMixin<double> {
  _Part(this.parent, this.curve);

  @override
  final Animation<double> parent;
  final Curve curve;

  @override
  double get value => curve.transform(parent.value);
}

Animation<double> _seg(Animation<double> t, int atMs, int durMs) {
  final total = _enterDur.inMilliseconds;
  final a = (atMs / total).clamp(0.0, 1.0);
  final b = ((atMs + durMs) / total).clamp(a, 1.0);
  return _Part(t, Interval(a, b, curve: Curves.easeOutCubic));
}

class _In extends StatelessWidget {
  const _In({required this.at, required this.child, this.dy = 14, this.dx = 0});

  final int at;
  final double dy;
  final double dx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = _seg(_Enter.of(context), at, 500);
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

class _PageView extends StatefulWidget {
  const _PageView({required this.index, required this.active});

  final int index;
  final bool active;

  @override
  State<_PageView> createState() => _PageViewState();
}

class _PageViewState extends State<_PageView> with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(_PageView old) {
    super.didUpdateWidget(old);
    if (!_still && widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pages[widget.index];
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
                    child: switch (widget.index) {
                      0 => const _HeroLook(),
                      1 => const _HeroGiver(),
                      _ => const _HeroChat(),
                    },
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
                      Text('0${widget.index + 1}', style: ZFont.display(size: 11, letterSpacing: 0.5)),
                      Container(
                        width: 16,
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: AppColors.textMuted,
                      ),
                      Text(p.jp, style: ZFont.jp()),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _MaskLine(at: 100, child: Text(p.line1, style: title)),
                _MaskLine(at: 180, child: Text(p.line2, style: title.copyWith(color: AppColors.accentViolet))),
                const SizedBox(height: 10),
                _In(
                  at: 280,
                  child: SizedBox(
                    height: 44,
                    child: Text(
                      p.desc,
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
}

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
                      child: ColoredBox(color: AppColors.accentViolet.withValues(alpha: i == page ? 1 : 0.45)),
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

// -----------------------------------------------------------------------------
// Isi halaman
// -----------------------------------------------------------------------------

BoxDecoration _card([Color? border]) => BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: border ?? const Color(0x0FFFFFFF)),
    );

/// Baris fitur: ikon + judul + keterangan.
class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.title, this.desc);

  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentViolet.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.accentVioletLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 01: maskot + daftar tampilan baru.
class _HeroLook extends StatelessWidget {
  const _HeroLook();

  @override
  Widget build(BuildContext context) {
    const feats = [
      (Icons.space_dashboard_rounded, 'Navbar kaca', 'Ikon beranimasi + titik merah di tab aktif'),
      (Icons.open_in_full_rounded, 'Poster terbang', 'Poster yang diketuk melayang ke halaman detail'),
      (Icons.movie_filter_rounded, 'Kredit opening', 'Studio, tahun & genre muncul ala opening anime'),
      (Icons.palette_rounded, 'Warna ikut poster', 'Latar Beranda & detail berubah sesuai anime'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          at: 0,
          child: Container(
            height: 118,
            decoration: _card(),
            child: Stack(
              children: [
                const Positioned.fill(child: ZScreentone(opacity: 0.08)),
                // Maskot dibesarkan, "mengintip" dari tepi bawah kartu.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(
                    child: Transform.scale(
                      scale: 1.45,
                      alignment: Alignment.bottomCenter,
                      child: const ZenimeMascot(),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 10,
                  child: Text('Hai! 👋', style: ZFont.display(size: 13)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: _card(),
          child: Column(
            children: [
              for (var i = 0; i < feats.length; i++)
                _In(
                  at: 200 + i * 140,
                  dy: 0,
                  dx: -14,
                  child: _Feature(feats[i].$1, feats[i].$2, feats[i].$3),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 02: badge Top Giver asli (peringkat 1, 2, 3, 6, 10 dan umum).
class _HeroGiver extends StatelessWidget {
  const _HeroGiver();

  @override
  Widget build(BuildContext context) {
    const ranks = [1, 2, 3, 6, 10, 14];
    const labels = ['Kaisar Matahari', 'Ksatria Perak', 'Ronin Perunggu', 'Petir Ungu', 'Sayap Serangga', 'Peringkat 11+'];
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < ranks.length; i++)
            _In(
              at: 120 + i * 130,
              dy: 0,
              dx: -16,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        ranks[i] > 10 ? '11+' : '#${ranks[i]}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          // Ruang untuk antena/lingkar sinar #1 yang keluar dari kotak.
                          padding: const EdgeInsets.only(left: 6),
                          child: TopGiverChip(rank: ranks[i], height: 20),
                        ),
                      ),
                    ),
                    Text(
                      labels[i],
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w700),
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

/// 03: contoh bubble chat berwallpaper + dua cara pakai.
class _HeroChat extends StatelessWidget {
  const _HeroChat();

  @override
  Widget build(BuildContext context) {
    const rc = Color(0xFFF59E0B); // warna rarity Legendary
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          at: 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.accentViolet, shape: BoxShape.circle),
                child: Text('K', style: ZFont.display(size: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: rc.withValues(alpha: 0.85)),
                    boxShadow: [BoxShadow(color: rc.withValues(alpha: 0.28), blurRadius: 18, spreadRadius: -6, offset: const Offset(0, 6))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        Positioned.fill(child: NetImage(kLoginPosters[0])),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xE00B0E14), Color(0x9E0B0E14), Color(0x470B0E14)],
                                stops: [0, 0.55, 1],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 9, 12, 34),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Kamu', style: ZFont.display(size: 12.5)),
                              const SizedBox(height: 5),
                              const Text('Bubble-ku sekarang pakai wallpaper ✨',
                                  style: TextStyle(color: Colors.white, fontSize: 13.5, height: 1.3)),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 7,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 3, 9, 3),
                            decoration: BoxDecoration(
                              color: const Color(0xB80B0E14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: rc.withValues(alpha: 0.9)),
                            ),
                            child: const Text('Legendary',
                                style: TextStyle(color: rc, fontSize: 9.5, fontWeight: FontWeight.w800)),
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
        const SizedBox(height: 14),
        Container(
          decoration: _card(),
          child: const Column(
            children: [
              _In(at: 350, dy: 0, dx: -14, child: _Feature(Icons.chat_bubble_rounded, 'Bubble chat', 'Dilihat semua orang di Chat Global & Clan')),
              _In(at: 500, dy: 0, dx: -14, child: _Feature(Icons.forum_rounded, 'Latar chat', 'Wallpaper jadi latar halaman chat, cuma di HP-mu')),
              _In(at: 650, dy: 0, dx: -14, child: _Feature(Icons.touch_app_rounded, 'Caranya', 'Wallpaper → ketuk koleksimu → Bubble chat / Latar chat')),
            ],
          ),
        ),
      ],
    );
  }
}
