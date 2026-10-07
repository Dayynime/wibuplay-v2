import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/remote_config_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../providers.dart';

// ============================================================== state

/// Popup aktif dari Remote Config. Dibaca saat app start dan diperbarui
/// real-time begitu kamu Publish perubahan `popup_*` di Firebase Console.
class AnnouncementNotifier extends Notifier<AnnouncementData?> {
  StreamSubscription<dynamic>? _sub;

  @override
  AnnouncementData? build() {
    _sub = RemoteConfigManager.listenUpdates(
      () => state = RemoteConfigManager.currentPopup(),
    );
    ref.onDispose(() => _sub?.cancel());
    return RemoteConfigManager.currentPopup();
  }
}

final announcementPopupProvider =
    NotifierProvider<AnnouncementNotifier, AnnouncementData?>(AnnouncementNotifier.new);

/// popup_id yang sudah ditutup di sesi ini (dipakai popup_repeat = true).
/// Level proses: kereset begitu app di-kill, jadi popup muncul lagi saat dibuka.
final _sessionSeenProvider = StateProvider<String>((ref) => '');

/// popup_id terakhir yang ditutup, permanen (dipakai popup_repeat = false).
final _persistedSeenProvider =
    StateProvider<String>((ref) => ref.read(localStoreProvider).lastSeenPopupId);

// ============================================================== host

/// Taruh membungkus konten app. Menampilkan popup sebagai overlay di atas
/// [child] (scrim ikut beranimasi). Tampil kalau popup aktif dan id-nya beda
/// dari id terakhir yang ditutup. Kalau saklar di-OFF-kan dari Console saat
/// popup terbuka, popup ikut animasi keluar sendiri.
///
/// Hanya tombol X / tombol di kartu yang menutup. Tap area gelap dan tombol
/// back sengaja tidak menutup (sama seperti Zenime).
class AnnouncementHost extends ConsumerStatefulWidget {
  const AnnouncementHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AnnouncementHost> createState() => _AnnouncementHostState();
}

class _AnnouncementHostState extends ConsumerState<AnnouncementHost>
    with TickerProviderStateMixin {
  // Masuk 900ms (berurutan), keluar 240ms.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    reverseDuration: const Duration(milliseconds: 240),
  );
  // Cincin berdenyut di belakang lencana lonceng.
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  // Lonceng goyang sekali.
  late final AnimationController _wiggle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  Animation<double> _curve(double a, double b, Curve c) => CurvedAnimation(
        parent: _c,
        curve: Interval(a, b, curve: c),
        reverseCurve: Curves.easeInCubic,
      );

  late final Animation<double> _scrim = _curve(0.0, 0.35, Curves.easeOut);
  late final Animation<double> _card = _curve(0.0, 0.62, Curves.easeOutBack);
  late final Animation<double> _badge = _curve(0.14, 0.68, Curves.easeOutBack);
  late final List<Animation<double>> _items = [
    for (var i = 0; i < 4; i++)
      _curve(0.3 + i * 0.07, 0.78 + i * 0.07, Curves.easeOutCubic),
  ];
  late final Animation<double> _bellAngle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.30), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.30, end: -0.26), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.26, end: 0.18), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 0.18, end: -0.09), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.09, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _wiggle, curve: Curves.easeInOut));

  AnnouncementData? _displayed; // yang sedang dirender (ditahan sampai animasi keluar selesai)
  bool _visible = false; // target animasi

  @override
  void dispose() {
    _c.dispose();
    _pulse.dispose();
    _wiggle.dispose();
    super.dispose();
  }

  void _show(AnnouncementData d) {
    _visible = true;
    setState(() => _displayed = d);
    HapticFeedback.selectionClick();
    _c.forward();
    _pulse.repeat();
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (mounted && _visible) _wiggle.forward(from: 0);
    });
  }

  void _hide() {
    if (!_visible) return;
    setState(() => _visible = false);
    _c.reverse().whenComplete(() {
      if (!mounted || _visible) return;
      _pulse.stop();
      setState(() => _displayed = null);
    });
  }

  void _dismiss() {
    final d = _displayed;
    if (d == null || !_visible) return;
    _hide();
    ref.read(_sessionSeenProvider.notifier).state = d.id;
    ref.read(_persistedSeenProvider.notifier).state = d.id;
    unawaited(ref.read(localStoreProvider).setLastSeenPopupId(d.id));
  }

  Future<void> _openAction() async {
    final d = _displayed;
    if (d == null) return;
    final uri = Uri.tryParse(d.buttonUrl);
    _dismiss();
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Tidak ada app yang bisa buka link: abaikan, popup tetap tertutup.
    }
  }

  /// Sinkronkan UI dengan state (dipanggil setelah frame, bukan saat build).
  void _sync(AnnouncementData? popup, bool active) {
    if (!mounted) return;
    if (active && popup != null) {
      if (!_visible) {
        _show(popup);
      } else if (_displayed != popup) {
        setState(() => _displayed = popup); // isi diperbarui real-time
      }
    } else if (_visible) {
      _hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final popup = ref.watch(announcementPopupProvider);
    final seen = popup?.repeat == true
        ? ref.watch(_sessionSeenProvider)
        : ref.watch(_persistedSeenProvider);
    final active = popup != null && popup.id != seen;

    if (active != _visible || (active && _displayed != popup)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync(popup, active));
    }

    final d = _displayed;
    return PopScope(
      // Selama popup terbuka tombol back diserap (tidak menutup app/layar).
      canPop: !_visible,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (d != null) Positioned.fill(child: _buildOverlay(d)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- overlay

  Widget _buildOverlay(AnnouncementData d) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Scrim: gelap + blur yang naik bertahap. Menyerap tap supaya tidak
        // tembus ke konten di belakang.
        AnimatedBuilder(
          animation: _scrim,
          builder: (context, _) {
            final s = _scrim.value.clamp(0.0, 1.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0.01 + 7 * s, sigmaY: 0.01 + 7 * s),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.6 * s)),
              ),
            );
          },
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: AnimatedBuilder(
                animation: _card,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _buildCard(d),
                ),
                builder: (context, child) {
                  final p = _card.value;
                  final o = p.clamp(0.0, 1.0);
                  return Opacity(
                    opacity: o,
                    child: Transform.translate(
                      offset: Offset(0, (1 - o) * 34),
                      child: Transform.scale(scale: 0.86 + 0.14 * p, child: child),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reveal(int i, Widget child) => FadeTransition(
        opacity: _items[i],
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.28), end: Offset.zero)
              .animate(_items[i]),
          child: child,
        ),
      );

  Widget _buildCard(AnnouncementData d) {
    const radius = 30.0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // Kartu dengan border gradien + glow ungu.
        Padding(
          padding: const EdgeInsets.only(top: 42),
          child: Container(
            padding: const EdgeInsets.all(1.3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accentVioletLight.withValues(alpha: 0.9),
                  AppColors.accentViolet.withValues(alpha: 0.18),
                  const Color(0xFFFFA38F).withValues(alpha: 0.45),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentViolet.withValues(alpha: 0.30),
                  blurRadius: 56,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1.3),
              child: ColoredBox(
                color: const Color(0xFF151A23),
                child: Stack(
                  children: [
                    // Cahaya lembut di bagian atas kartu.
                    Positioned(
                      top: -70,
                      left: 0,
                      right: 0,
                      height: 220,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.topCenter,
                            radius: 0.9,
                            colors: [
                              AppColors.accentViolet.withValues(alpha: 0.30),
                              AppColors.accentViolet.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 62, 22, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (d.title.isNotEmpty)
                            _reveal(
                              0,
                              Text(
                                d.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  height: 1.25,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          if (d.message.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _reveal(
                              1,
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 240),
                                child: SingleChildScrollView(
                                  child: Text(
                                    d.message,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.86),
                                      fontSize: 14.5,
                                      height: 1.55,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (d.footnote.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _reveal(2, _FootnoteChip(text: d.footnote)),
                          ],
                          const SizedBox(height: 22),
                          _reveal(
                            3,
                            Column(
                              children: [
                                _PrimaryButton(
                                  label: d.hasAction ? d.buttonText : 'Oke, mengerti',
                                  icon: d.hasAction ? Icons.arrow_outward_rounded : null,
                                  onTap: d.hasAction ? _openAction : _dismiss,
                                ),
                                if (d.hasAction) ...[
                                  const SizedBox(height: 4),
                                  TextButton(
                                    onPressed: _dismiss,
                                    child: Text(
                                      'Nanti saja',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
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
        // Tombol X.
        Positioned(
          top: 56,
          right: 14,
          child: FadeTransition(
            opacity: _items[0],
            child: _CloseButton(onTap: _dismiss),
          ),
        ),
        // Lencana lonceng yang menjuntai di atas kartu.
        Positioned(top: 0, child: _buildBadge()),
      ],
    );
  }

  Widget _buildBadge() {
    return ScaleTransition(
      scale: _badge,
      child: SizedBox(
        width: 104,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dua cincin yang memuai dan memudar bergantian.
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Stack(
                alignment: Alignment.center,
                children: [
                  for (final k in [0.0, 0.5])
                    () {
                      final t = (_pulse.value + k) % 1.0;
                      final size = 60 + t * 44;
                      return Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.accentVioletLight
                                .withValues(alpha: (1 - t) * 0.42),
                            width: 1.6,
                          ),
                        ),
                      );
                    }(),
                ],
              ),
            ),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF8896), Color(0xFFC42A3E)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentViolet.withValues(alpha: 0.6),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _bellAngle,
                builder: (context, child) => Transform.rotate(
                  angle: _bellAngle.value,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
                child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================== widgets

class _FootnoteChip extends StatelessWidget {
  const _FootnoteChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentViolet.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentVioletLight.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.accentVioletLight),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFFFD3D8),
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: 0.85)),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: const LinearGradient(
            colors: [Color(0xFFEE5B6D), Color(0xFFC42A3E)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentViolet.withValues(alpha: 0.42),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, size: 18, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

/// Efek tekan: mengecil sedikit dengan pantulan halus + haptic ringan.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: Duration(milliseconds: _down ? 110 : 260),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
