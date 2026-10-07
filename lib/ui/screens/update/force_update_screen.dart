import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/apk_downloader.dart';
import '../../../core/theme/app_colors.dart';

/// Layar SATU-SATUNYA yang tampil kalau ada release GitHub lebih baru dari
/// versi app yang berjalan (lihat UpdateGate). Tidak ada tombol back/skip.
///
/// Tombol bawah mengikuti [downloadState]:
/// - DownloadIdle -> "Update Sekarang"
/// - Downloading -> bar progres + persen + ukuran
/// - Downloaded -> "Install Sekarang"
/// - DownloadFailed -> pesan error + "Coba Lagi"
class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadState,
    required this.onDownload,
    required this.onInstall,
    required this.onRetry,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final DownloadState downloadState;
  final VoidCallback onDownload;
  final VoidCallback onInstall;
  final VoidCallback onRetry;

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
        ..forward();
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
        ..repeat();

  Animation<double> _iv(double a, double b, [Curve c = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  late final Animation<double> _logoIn = _iv(0.0, 0.5, Curves.easeOutBack);
  late final List<Animation<double>> _items = [
    for (var i = 0; i < 6; i++) _iv(0.18 + i * 0.09, 0.62 + i * 0.09),
  ];

  bool _notesOpen = false;

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    _shine.dispose();
    super.dispose();
  }

  Widget _reveal(int i, Widget child) => FadeTransition(
        opacity: _items[i],
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
              .animate(_items[i]),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final failed = widget.downloadState is DownloadFailed;
    return PopScope(
      canPop: false, // wajib update: tombol back tidak melakukan apa-apa
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(child: _Aurora(t: _loop)),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 24),
                        ScaleTransition(
                          scale: _logoIn,
                          child: FadeTransition(
                            opacity: _items[0],
                            child: _Logo(loop: _loop),
                          ),
                        ),
                        const SizedBox(height: 26),
                        _reveal(1, const _Eyebrow()),
                        const SizedBox(height: 14),
                        _reveal(
                          2,
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (r) => const LinearGradient(
                              colors: [Colors.white, Color(0xFFFFD3D8)],
                            ).createShader(r),
                            child: const Text(
                              'Update Tersedia',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 31,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _reveal(
                          3,
                          Column(
                            children: [
                              _VersionChip(
                                current: widget.currentVersion,
                                latest: widget.latestVersion,
                                loop: _loop,
                              ),
                              const SizedBox(height: 16),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  failed
                                      ? (widget.downloadState as DownloadFailed).message
                                      : 'Wibuplay tidak bisa dipakai sebelum diperbarui ke versi terbaru.',
                                  key: ValueKey(failed),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: failed
                                        ? AppColors.errorRed
                                        : AppColors.textSecondary,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.releaseNotes.trim().isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _reveal(4, _buildNotes()),
                        ],
                        const SizedBox(height: 28),
                        _reveal(5, _buildAction()),
                        const SizedBox(height: 24),
                      ],
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

  // ------------------------------------------------------------ changelog

  Widget _buildNotes() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _notesOpen = !_notesOpen);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 18, color: AppColors.accentVioletLight),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Yang baru di versi ini',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _notesOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _notesOpen
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _NotesBody(notes: widget.releaseNotes),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- action

  Widget _buildAction() {
    final s = widget.downloadState;
    final Widget child;
    if (s is Downloading) {
      child = _ProgressPanel(key: const ValueKey('dl'), state: s, shine: _shine);
    } else if (s is Downloaded) {
      child = Column(
        key: const ValueKey('done'),
        children: [
          if (s.note != null) ...[
            Text(
              s.note!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.warningAmber,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
          ],
          _ActionButton(
            label: 'Install Sekarang',
            icon: Icons.system_update_alt_rounded,
            shine: _shine,
            onTap: widget.onInstall,
          ),
        ],
      );
    } else if (s is DownloadFailed) {
      child = _ActionButton(
        key: const ValueKey('fail'),
        label: 'Coba Lagi',
        icon: Icons.refresh_rounded,
        shine: _shine,
        onTap: widget.onRetry,
      );
    } else {
      child = _ActionButton(
        key: const ValueKey('idle'),
        label: 'Update Sekarang',
        icon: Icons.download_rounded,
        shine: _shine,
        onTap: widget.onDownload,
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(a),
            child: c,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, if (current != null) current],
        ),
        child: child,
      ),
    );
  }
}

// ================================================================ pieces

/// Logo dengan cincin gradien yang berputar pelan + glow yang berdenyut.
class _Logo extends StatelessWidget {
  const _Logo({required this.loop});

  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final t = loop.value * 2 * math.pi;
          final glow = 0.5 + 0.5 * math.sin(t * 8); // 0..1, tersambung mulus
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accentViolet.withValues(alpha: 0.26 + 0.14 * glow),
                      AppColors.accentViolet.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Transform.rotate(
                angle: t * 2,
                child: Container(
                  width: 116,
                  height: 116,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Color(0x00EE5B6D),
                        Color(0xFFEE5B6D),
                        Color(0xFFFFA38F),
                        Color(0x00FFA38F),
                      ],
                      stops: [0.0, 0.45, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
              Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.backgroundDark,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentViolet.withValues(alpha: 0.35 + 0.25 * glow),
                      blurRadius: 28,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset('assets/images/logo.jpg', width: 82, height: 82),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Eyebrow extends StatefulWidget {
  const _Eyebrow();

  @override
  State<_Eyebrow> createState() => _EyebrowState();
}

class _EyebrowState extends State<_Eyebrow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.accentViolet.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.accentVioletLight.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentVioletLight,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentVioletLight.withValues(alpha: 0.3 + 0.5 * _c.value),
                    blurRadius: 4 + 6 * _c.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'PEMBARUAN WAJIB',
            style: TextStyle(
              color: Color(0xFFFFD3D8),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip "v1.0.0 → v1.0.1" dengan panah yang bergeser pelan.
class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.current, required this.latest, required this.loop});

  final String current;
  final String latest;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'v$current',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          AnimatedBuilder(
            animation: loop,
            builder: (context, child) {
              final dx = 3 * math.sin(loop.value * 2 * math.pi * 12);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 17, color: AppColors.accentVioletLight),
            ),
          ),
          Text(
            'v$latest',
            style: const TextStyle(
              color: Color(0xFFFFB3BB),
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Render markdown minimal dari body release GitHub: heading (##/###),
/// bullet (- / *), bold (**), pemisah (---).
class _NotesBody extends StatelessWidget {
  const _NotesBody({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final raw in notes.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('### ') || line.startsWith('## ') || line.startsWith('# ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 3),
          child: Text(
            line.replaceFirst(RegExp(r'^#{1,3}\s+'), '').replaceAll('**', ''),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 7, right: 9),
                child: CircleAvatar(radius: 2.2, backgroundColor: AppColors.accentVioletLight),
              ),
              Expanded(
                child: Text(
                  line.substring(2).replaceAll('**', ''),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ));
      } else if (line.startsWith('---')) {
        children.add(const SizedBox(height: 6));
      } else if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 4));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            line.replaceAll('**', ''),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({super.key, required this.state, required this.shine});

  final Downloading state;
  final Animation<double> shine;

  static String _mb(int bytes) =>
      (bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final known = state.total > 0;
    final target = known ? state.progress / 100 : 0.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mengunduh pembaruan…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                known ? '${state.progress}%' : '',
                style: const TextStyle(
                  color: Color(0xFFFFB3BB),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Bar progres: isi bergradien yang naik halus + kilau yang menyapu.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: target),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: SizedBox(
                height: 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: Colors.white.withValues(alpha: 0.08)),
                    if (known)
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: v.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFEE5B6D), Color(0xFFFFA38F)],
                            ),
                          ),
                          child: ClipRect(
                            child: AnimatedBuilder(
                              animation: shine,
                              builder: (context, _) => Align(
                                alignment: Alignment((shine.value * 3) - 1.5, 0),
                                child: FractionallySizedBox(
                                  widthFactor: 0.3,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0),
                                          Colors.white.withValues(alpha: 0.45),
                                          Colors.white.withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      // Ukuran total belum diketahui: bar bergerak bolak-balik.
                      AnimatedBuilder(
                        animation: shine,
                        builder: (context, _) => Align(
                          alignment: Alignment((shine.value * 2.4) - 1.2, 0),
                          child: FractionallySizedBox(
                            widthFactor: 0.35,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFFEE5B6D), Color(0xFFFFA38F)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (known) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_mb(state.received)} / ${_mb(state.total)} MB',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.shine,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Animation<double> shine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Press(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: const LinearGradient(colors: [Color(0xFFEE5B6D), Color(0xFFC42A3E)]),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentViolet.withValues(alpha: 0.45),
              blurRadius: 26,
              offset: const Offset(0, 11),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, box) => AnimatedBuilder(
                    animation: shine,
                    builder: (context, _) {
                      final p = Curves.easeInOut
                          .transform((shine.value / 0.42).clamp(0.0, 1.0));
                      final x = -90 + p * (box.maxWidth + 180);
                      return Transform.translate(
                        offset: Offset(x, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Transform(
                            transform: Matrix4.skewX(-0.35),
                            child: Container(
                              width: 64,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.28),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Press extends StatefulWidget {
  const _Press({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
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
        scale: _down ? 0.96 : 1,
        duration: Duration(milliseconds: _down ? 110 : 260),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Dua blob cahaya ungu/pink yang bergerak pelan di latar.
class _Aurora extends StatelessWidget {
  const _Aurora({required this.t});

  final Animation<double> t;

  Widget _blob(Alignment at, Color c, double size, double alpha) => Align(
        alignment: at,
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final a = t.value * 2 * math.pi * 3;
        return Stack(
          fit: StackFit.expand,
          children: [
            _blob(
              Alignment(-0.9 + 0.25 * math.sin(a), -0.75 + 0.18 * math.cos(a)),
              AppColors.accentViolet,
              560,
              0.34,
            ),
            _blob(
              Alignment(1.0 + 0.2 * math.cos(a + 1), 0.8 + 0.2 * math.sin(a)),
              const Color(0xFFFF8A5C),
              480,
              0.18,
            ),
          ],
        );
      },
    );
  }
}
