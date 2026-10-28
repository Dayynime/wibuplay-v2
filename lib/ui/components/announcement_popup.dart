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
    with SingleTickerProviderStateMixin {
  // Masuk 320ms, keluar 200ms. Sederhana: fade + geser halus.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  AnnouncementData? _displayed; // yang sedang dirender (ditahan sampai animasi keluar selesai)
  bool _visible = false; // target animasi

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _show(AnnouncementData d) {
    _visible = true;
    setState(() => _displayed = d);
    HapticFeedback.selectionClick();
    _c.forward();
  }

  void _hide() {
    if (!_visible) return;
    setState(() => _visible = false);
    _c.reverse().whenComplete(() {
      if (!mounted || _visible) return;
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
    // Overlay ini di luar Scaffold: tanpa Material, Text tampil bergaris
    // kuning dengan font debug. Material transparan memperbaikinya.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Scrim gelap + blur ringan; menyerap tap supaya tidak tembus.
          AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final s = _t.value.clamp(0.0, 1.0);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0.01 + 4 * s, sigmaY: 0.01 + 4 * s),
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.55 * s)),
                ),
              );
            },
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: AnimatedBuilder(
                  animation: _t,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _buildCard(d),
                  ),
                  builder: (context, child) {
                    final v = _t.value.clamp(0.0, 1.0);
                    return Opacity(
                      opacity: v,
                      child: Transform.translate(
                        offset: Offset(0, (1 - v) * 16),
                        child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(AnnouncementData d) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: ikon kecil + judul (rata kiri) + tombol tutup.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentViolet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.campaign_rounded,
                    size: 20, color: AppColors.accentVioletLight),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  d.title.isNotEmpty ? d.title : 'Pengumuman',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              _CloseButton(onTap: _dismiss),
            ],
          ),
          if (d.message.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(child: _MessageBody(text: d.message)),
              ),
            ),
          ],
          if (d.footnote.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Footnote(text: d.footnote),
            ),
          ],
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: d.hasAction
                ? Row(
                    children: [
                      Expanded(
                        child: _Button(
                          label: 'Nanti saja',
                          onTap: _dismiss,
                          primary: false,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Button(
                          label: d.buttonText,
                          icon: Icons.arrow_outward_rounded,
                          onTap: _openAction,
                        ),
                      ),
                    ],
                  )
                : _Button(label: 'Oke, mengerti', onTap: _dismiss),
          ),
        ],
      ),
    );
  }
}

// ============================================================== widgets

const Color _kCardBg = Color(0xFF161B24);

/// Isi pesan rata kiri. Baris "- teks" / "• teks" jadi daftar berpoin,
/// baris yang diakhiri ":" jadi label bagian kecil, sisanya paragraf.
class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.text});

  final String text;

  static final _bullet = RegExp(r'^\s*[-•*]\s+');

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(
      color: Colors.white.withValues(alpha: 0.78),
      fontSize: 14,
      height: 1.5,
    );
    final children = <Widget>[];
    var lastBlank = false;
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty && !lastBlank) children.add(const SizedBox(height: 10));
        lastBlank = true;
        continue;
      }
      lastBlank = false;
      if (_bullet.hasMatch(line)) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, right: 10),
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.accentVioletLight,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(child: Text(line.replaceFirst(_bullet, ''), style: body)),
            ],
          ),
        ));
      } else if (line.trim().endsWith(':')) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            line.trim().substring(0, line.trim().length - 1).toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line.trim(), style: body.copyWith(color: Colors.white.withValues(alpha: 0.9))),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded,
                size: 15, color: Colors.white.withValues(alpha: 0.5)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
                height: 1.4,
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
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(Icons.close_rounded, size: 20, color: Colors.white.withValues(alpha: 0.5)),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : Colors.white.withValues(alpha: 0.75);
    return _PressScale(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: primary ? AppColors.accentViolet : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 6),
              Icon(icon, size: 16, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}

/// Efek tekan: mengecil sedikit + haptic ringan.
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
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
