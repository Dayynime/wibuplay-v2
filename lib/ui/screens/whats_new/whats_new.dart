import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers.dart';
import '../../components/name_deco_styles.dart';
import '../../redesign/z_kit.dart';
import '../name_deco/name_deco_shop_screen.dart';

// -----------------------------------------------------------------------------
// "Yang baru" — tutorial singkat fitur baru, muncul SEKALI setelah update.
//
// Cara pakai di update berikutnya: ganti [kWhatsNewId] (mis. '3.2.5') dan isi
// halaman di [_WhatsNewScreen]. User yang id tersimpannya beda akan melihatnya
// sekali; install baru langsung ditandai sudah lihat (lewat OnboardingGate).
// -----------------------------------------------------------------------------

const String kWhatsNewId = '3.2.4';

const Color _gold = Color(0xFFF6BE4F);

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
  _Page('新しい名前', 'Dekorasi Nama', 'Seri 2.',
      '12 gaya baru tanpa latar: cuma huruf dan efek, tampil bersih di mana pun.'),
  _Page('フォント', 'Tiap gaya,', 'font sendiri.',
      'Dari huruf pixel arcade, komik, horor, sampai emas bangsawan. Semua beranimasi.'),
  _Page('使い方', 'Cara', 'pakainya.',
      'Beli pakai ZCoin, pasang, dan namamu langsung tampil keren di seluruh app.'),
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
    // Halaman terakhir: langsung ke toko Dekorasi Nama.
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute<void>(builder: (_) => const NameDecoShopScreen()));
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
                              Icon(isLast ? Icons.storefront_rounded : Icons.arrow_forward_rounded,
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
                      0 => const _HeroGrid(),
                      1 => _HeroFonts(running: widget.active && !_still),
                      _ => const _HeroSteps(),
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

const List<NameDecoStyle> _seri2 = [
  NameDecoStyle.terminal,
  NameDecoStyle.arcade,
  NameDecoStyle.streetComic,
  NameDecoStyle.neonSign,
  NameDecoStyle.horrorDrip,
  NameDecoStyle.stencilOps,
  NameDecoStyle.racer,
  NameDecoStyle.rgbGlitch,
  NameDecoStyle.royalGold,
  NameDecoStyle.zenSpace,
  NameDecoStyle.auroraFlow,
  NameDecoStyle.rainbowWave,
];

BoxDecoration _card([Color? border]) => BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: border ?? const Color(0x0FFFFFFF)),
    );

/// 01: 12 gaya baru, tiap kartu menampilkan namanya dengan gaya itu sendiri.
class _HeroGrid extends StatelessWidget {
  const _HeroGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < _seri2.length; i++)
            _In(
              at: 120 + i * 70,
              child: Container(
                width: w,
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: _card(),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: NameDecoText(
                          name: _seri2[i].label,
                          style: _seri2[i],
                          fontSize: 14,
                          maxWidth: w - 34,
                        ),
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: _seri2[i].tier.color, shape: BoxShape.circle),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// 02: satu nama besar yang berganti gaya tiap 1,8 detik.
class _HeroFonts extends StatefulWidget {
  const _HeroFonts({required this.running});

  final bool running;

  @override
  State<_HeroFonts> createState() => _HeroFontsState();
}

class _HeroFontsState extends State<_HeroFonts> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_HeroFonts old) {
    super.didUpdateWidget(old);
    if (old.running != widget.running) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (widget.running) {
      _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
        if (mounted) setState(() => _i = (_i + 1) % _seri2.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = _seri2[_i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          at: 0,
          child: Container(
            height: 190,
            decoration: _card(),
            child: Stack(
              children: [
                const Positioned.fill(child: ZScreentone(opacity: 0.1)),
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
                    ),
                    child: NameDecoText(
                      key: ValueKey(st),
                      name: 'Namamu',
                      style: st,
                      fontSize: 28,
                      maxWidth: 280,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Row(
                      key: ValueKey(st),
                      children: [
                        ZChip(st.label, tone: ZTone.glass),
                        const SizedBox(width: 6),
                        ZChip(st.font, tone: ZTone.ghost),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Text(
                    st.tier.label.toUpperCase(),
                    style: TextStyle(color: st.tier.color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _In(
          at: 250,
          child: Row(
            children: [
              for (final t in NameDecoTier.values) ...[
                if (t != NameDecoTier.biasa) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariantDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: st.tier == t ? t.color.withValues(alpha: 0.7) : Colors.transparent),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(height: 6),
                        Text(t.label,
                            style: const TextStyle(
                                color: AppColors.textWhite, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 03: langkah memakai + contoh nama di chat.
class _HeroSteps extends StatelessWidget {
  const _HeroSteps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.menu_rounded, 'Buka Menu → Decor'),
      (Icons.text_fields_rounded, 'Pilih Dekorasi Nama'),
      (Icons.toll_rounded, 'Beli pakai ZCoin, lalu Pasang'),
      (Icons.forum_rounded, 'Tampil di chat, komentar, clan & profil'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: _card(),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                _In(
                  at: 120 + i * 160,
                  dy: 0,
                  dx: -16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: i == 0
                        ? null
                        : const BoxDecoration(border: Border(top: BorderSide(color: Color(0x0DFFFFFF)))),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: ZRankNumber(i + 1, size: 24, color: i == 3 ? _gold : AppColors.textMuted),
                        ),
                        const SizedBox(width: 8),
                        Icon(steps[i].$1, size: 18, color: AppColors.accentVioletLight),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(steps[i].$2,
                              style: const TextStyle(
                                  color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _In(
          at: 900,
          child: Container(
            decoration: _card(),
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.accentViolet, shape: BoxShape.circle),
                  child: Text('N', style: ZFont.display(size: 13)),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const NameDecoText(name: 'Namamu', style: NameDecoStyle.auroraFlow, fontSize: 11, maxWidth: 140),
                      const SizedBox(height: 3),
                      Container(
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
                        child: const Text('Nama baru, siapa takut 😎',
                            style: TextStyle(color: AppColors.textWhite, fontSize: 13, height: 1.35)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
