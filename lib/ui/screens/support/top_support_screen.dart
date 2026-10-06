import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart';
import '../../../core/supabase_config.dart';
import '../../../data/models/support_models.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';
import '../profile/public_profile_screen.dart';

/// Halaman Top Support: podium 3 donatur teratas + daftar peringkat + ajakan
/// donasi lewat halaman donasi Zenime Store (QRIS). Dibuka dari slide TOP SUPPORT di carousel Beranda.
class TopSupportScreen extends ConsumerWidget {
  const TopSupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(topSupportersFullProvider);
    final uid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final code = uid.isEmpty
        ? null
        : ref.watch(profileIdentityProvider(uid)).valueOrNull?.zenimeCode;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top Support', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(
              'Donatur teratas',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Aura rose di belakang podium.
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            height: 380,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 0.9,
                    colors: [
                      _Tone.rose.withValues(alpha: 0.30),
                      _Tone.gold.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          ),
          board.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: _Tone.rose, strokeWidth: 3),
            ),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Gagal memuat Top Support',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(topSupportersFullProvider),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            ),
            data: (list) => RefreshIndicator(
              color: _Tone.rose,
              onRefresh: () async => ref.refresh(topSupportersFullProvider.future),
              child: _Body(supporters: list, zenimeCode: code),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tone {
  _Tone._();

  static const Color rose = Color(0xFFFF5C8A);
  static const Color magenta = Color(0xFFFF2E93);
  static const Color gold = Color(0xFFFFC83D);
  static const Color silver = Color(0xFFC9D1D9);
  static const Color bronze = Color(0xFFD08B4E);
  static const Color verified = Color(0xFF3897F0);
}

Color? _parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

String _rp(int v) => 'Rp ${formatZCoin(v)}';

// ─────────────────────────────────────────────────────────────────────────────
// ISI HALAMAN
// ─────────────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  const _Body({required this.supporters, required this.zenimeCode});

  final List<TopSupporter> supporters;
  final String? zenimeCode;

  @override
  Widget build(BuildContext context) {
    final top3 = supporters.take(3).toList();
    final rest = supporters.skip(3).toList();
    final maxAmount = supporters.fold<int>(1, (a, s) => math.max(a, s.totalAmount));
    final total = supporters.fold<int>(0, (a, s) => a + s.totalAmount);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (top3.isNotEmpty) ...[
          _SupportPodium(top3: top3),
          const SizedBox(height: 14),
          _StatsRow(count: supporters.length, total: total),
          const SizedBox(height: 14),
        ],
        _DonateCard(zenimeCode: zenimeCode),
        const SizedBox(height: 18),
        if (supporters.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Belum ada donatur tercatat.\nJadilah yang pertama!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        if (rest.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'PERINGKAT LAINNYA',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          for (var i = 0; i < rest.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FadeSlideIn(
                index: i,
                child: _SupporterRow(
                  rank: i + 4,
                  s: rest[i],
                  ratio: rest[i].totalAmount / maxAmount,
                  barDelayMs: 900 + math.min(i, 10) * 70,
                ),
              ),
            ),
        ],
        const SizedBox(height: 10),
        const Text(
          'Setiap dukungan, sekecil apa pun, sangat berarti. Terima kasih! ❤️',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PODIUM
// ─────────────────────────────────────────────────────────────────────────────

class _SupportPodium extends StatefulWidget {
  const _SupportPodium({required this.top3});

  final List<TopSupporter> top3;

  @override
  State<_SupportPodium> createState() => _SupportPodiumState();
}

class _SupportPodiumState extends State<_SupportPodium> with TickerProviderStateMixin {
  // Animasi masuk sekali jalan: podium naik, avatar turun halus, nominal menghitung.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..forward();

  // Loop 6 detik; semua gerak berulang memakai kelipatan bulat periode ini
  // supaya sambungannya mulus.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TopSupporter? at(int i) => i < widget.top3.length ? widget.top3[i] : null;

    Widget slot(TopSupporter? s, int rank) {
      if (s == null) return const Expanded(child: SizedBox.shrink());
      final cfg = switch (rank) {
        1 => (_Tone.gold, 78.0, 104.0, 0.20),
        2 => (_Tone.silver, 62.0, 78.0, 0.10),
        _ => (_Tone.bronze, 62.0, 58.0, 0.00),
      };
      return Expanded(
        child: _SupportSlot(
          s: s,
          rank: rank,
          color: cfg.$1,
          avatarSize: cfg.$2,
          pedestalHeight: cfg.$3,
          start: cfg.$4,
          intro: _intro,
          loop: _loop,
        ),
      );
    }

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4A1D38), Color(0xFF1A1220)],
          ),
          border: Border.all(color: _Tone.rose.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: _Tone.magenta.withValues(alpha: 0.26),
              blurRadius: 34,
              spreadRadius: -6,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _SupportBackdrop(_loop))),
              SizedBox(
                height: 372,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 18, 6, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [slot(at(1), 2), slot(at(0), 1), slot(at(2), 3)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportSlot extends StatelessWidget {
  const _SupportSlot({
    required this.s,
    required this.rank,
    required this.color,
    required this.avatarSize,
    required this.pedestalHeight,
    required this.start,
    required this.intro,
    required this.loop,
  });

  final TopSupporter s;
  final int rank;
  final Color color;
  final double avatarSize;
  final double pedestalHeight;
  final double start;
  final Animation<double> intro;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([intro, loop]),
      builder: (context, _) {
        final iv = intro.value;
        final ped = Interval(start, start + 0.40, curve: Curves.easeOutCubic).transform(iv);
        final pop = Interval(start + 0.20, start + 0.60, curve: Curves.easeOutBack).transform(iv);
        final info = Interval(start + 0.35, start + 0.75, curve: Curves.easeOut).transform(iv);
        final count = Interval(start + 0.20, 1.0, curve: Curves.easeOutCubic).transform(iv);

        final l = loop.value * 2 * math.pi;
        final bob = math.sin(l * 2 + rank) * (rank == 1 ? 3.0 : 2.0);
        final pulse = 0.5 + 0.5 * math.sin(l * 2 + rank);

        return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: (s.firebaseUid) == null || (s.firebaseUid)!.isEmpty ? null : () => openPublicProfile(context, s.firebaseUid!),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: pop.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - pop) * -34 + bob),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * pop,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (rank == 1)
                        Icon(
                          Icons.emoji_events,
                          color: color,
                          size: 28,
                          shadows: [
                            Shadow(color: color.withValues(alpha: 0.5 + 0.4 * pulse), blurRadius: 14),
                          ],
                        )
                      else
                        const SizedBox(height: 4),
                      const SizedBox(height: 2),
                      _avatar(l, pulse),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: info.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - info) * 10),
                child: _info((s.totalAmount * count).round()),
              ),
            ),
            const SizedBox(height: 10),
            _pedestal(pedestalHeight * ped, ped, loop.value),
          ],
        ),
    );
      },
    );
  }

  Widget _avatar(double l, double pulse) {
    const ring = 3.0;
    final outer = avatarSize + ring * 2 + 4;
    return SizedBox(
      width: outer + 14,
      height: outer + 14,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: outer,
            height: outer,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.22 + 0.30 * pulse),
                  blurRadius: 16 + 12 * pulse,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(ring),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                transform: GradientRotation(l),
                colors: [
                  color,
                  color.withValues(alpha: 0.10),
                  Colors.white,
                  color.withValues(alpha: 0.10),
                  color,
                ],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF1A1220),
              ),
              child: UserAvatar(username: s.name, url: s.avatarUrl, size: avatarSize),
            ),
          ),
          Positioned(
            bottom: 2,
            right: 4,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, color],
                ),
                border: Border.all(color: const Color(0xFF1A1220), width: 2),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
              ),
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(int shownAmount) {
    final nameColor = _parseHex(s.usernameColor) ?? Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: nameColor,
                    fontSize: rank == 1 ? 13.5 : 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (s.isLinked)
                const Padding(
                  padding: EdgeInsets.only(left: 3),
                  child: Icon(Icons.verified, size: 14, color: _Tone.verified),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${s.donationCount}x dukungan',
            maxLines: 1,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Text(
                _rp(shownAmount),
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pedestal(double height, double t, double loopV) {
    final glow = 0.5 + 0.5 * math.sin(loopV * 2 * math.pi * 2 + rank);
    const radius = BorderRadius.vertical(top: Radius.circular(16));
    final h = height < 0 ? 0.0 : height;
    return Container(
      height: h,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18 + 0.20 * glow),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0.42), color.withValues(alpha: 0.04)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-2.5 + 5 * loopV, -1),
                    end: Alignment(-1.5 + 5 * loopV, 1),
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: rank == 1 ? 0.16 : 0.09),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0),
                      color,
                      Colors.white,
                      color,
                      color.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            if (h > 36)
              Center(
                child: Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: rank == 1 ? 44 : 34,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white.withValues(alpha: 0.95), color.withValues(alpha: 0.25)],
                        ).createShader(const Rect.fromLTWH(0, 0, 40, 48)),
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

/// Latar podium: spotlight, sinar emas yang berputar pelan di belakang juara 1,
/// dan partikel hati/kilau yang naik. Semua periodik terhadap [t] (loop 6 detik).
class _SupportBackdrop extends CustomPainter {
  _SupportBackdrop(this.t) : super(repaint: t);

  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final v = t.value;
    final center = Offset(w / 2, h * 0.30);

    // Spotlight rose.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [_Tone.magenta.withValues(alpha: 0.36), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: w * 0.7)),
    );

    // Sinar berputar: 8 sinar simetris, putar 1/8 lingkaran per loop => mulus.
    final rayPaint = Paint()
      ..shader = RadialGradient(
        colors: [_Tone.gold.withValues(alpha: 0.20), _Tone.gold.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: w * 0.9));
    const rays = 8;
    final base = v * 2 * math.pi / rays;
    for (var i = 0; i < rays; i++) {
      final a = base + i * 2 * math.pi / rays;
      const half = 0.12;
      final r = w * 0.95;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + r * math.cos(a - half), center.dy + r * math.sin(a - half))
        ..lineTo(center.dx + r * math.cos(a + half), center.dy + r * math.sin(a + half))
        ..close();
      canvas.drawPath(path, rayPaint);
    }

    // Partikel naik pelan (lingkaran kecil + belah ketupat kilau).
    final pp = Paint();
    for (var i = 0; i < 18; i++) {
      final speed = 1 + (i % 3);
      final p = (i * 0.137 + v * speed) % 1.0;
      final x = ((i * 0.6180339887) % 1.0) * w + math.sin((p + i) * 2 * math.pi) * 7;
      final y = h * (1 - p);
      final a = math.sin(p * math.pi) * 0.75;
      pp.color = (i % 3 == 0 ? _Tone.gold : (i.isEven ? _Tone.rose : Colors.white))
          .withValues(alpha: a);
      if (i % 4 == 0) {
        final s = 3.0 + (i % 3);
        canvas.drawPath(
          Path()
            ..moveTo(x, y - s)
            ..lineTo(x + s * 0.6, y)
            ..lineTo(x, y + s)
            ..lineTo(x - s * 0.6, y)
            ..close(),
          pp,
        );
      } else {
        canvas.drawCircle(Offset(x, y), 0.8 + (i % 3) * 0.5, pp);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SupportBackdrop old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// STATISTIK + AJAKAN DONASI
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.count, required this.total});

  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.groups_rounded,
            label: 'Donatur',
            value: count,
            format: (v) => '$v',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.volunteer_activism_rounded,
            label: 'Total dukungan',
            value: total,
            format: _rp,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.format,
  });

  final IconData icon;
  final String label;
  final int value;
  final String Function(int) format;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceDark.withValues(alpha: 0.85),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _Tone.rose.withValues(alpha: 0.16),
            ),
            child: Icon(icon, size: 18, color: _Tone.rose),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
                const SizedBox(height: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: value.toDouble()),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      format(v.round()),
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
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

class _DonateCard extends StatefulWidget {
  const _DonateCard({required this.zenimeCode});

  final String? zenimeCode;

  @override
  State<_DonateCard> createState() => _DonateCardState();
}

class _DonateCardState extends State<_DonateCard> with SingleTickerProviderStateMixin {
  // Detak hati + kilau tombol, loop 3 detik.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _copyCode() async {
    final code = widget.zenimeCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _toast('Kode Zenime disalin');
  }

  Future<void> _donate() async {
    final code = widget.zenimeCode;
    final uri = Uri.parse(SupabaseConfig.donationStorefrontUrl).replace(
      queryParameters: (code != null && code.isNotEmpty) ? {'code': code} : null,
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast('Tidak bisa membuka halaman donasi');
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.zenimeCode;
    final hasCode = code != null && code.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Tone.rose.withValues(alpha: 0.16),
            AppColors.surfaceDark.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(color: _Tone.rose.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dukung Kami',
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Donasimu bantu jaga server tetap nyala, cepat, dan konten tetap update.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final l = _c.value * 2 * math.pi;
              // Dua denyut per loop: membesar sebentar lalu kembali.
              final beat = math.pow(math.max(0, math.sin(l * 2)), 6).toDouble();
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _donate,
                  child: Ink(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(colors: [_Tone.magenta, _Tone.rose]),
                      boxShadow: [
                        BoxShadow(
                          color: _Tone.magenta.withValues(alpha: 0.30 + 0.20 * beat),
                          blurRadius: 16 + 8 * beat,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Kilau yang lewat tiap loop.
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(-3 + 6 * _c.value, 0),
                                  end: Alignment(-2 + 6 * _c.value, 0.4),
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.22),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Transform.scale(
                                scale: 1 + 0.25 * beat,
                                child: const Icon(Icons.favorite, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Donasi via QRIS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'QRIS: semua e-wallet dan m-banking',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ),
          if (hasCode) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
            const SizedBox(height: 14),
            const Text(
              'Biar namamu tampil di Top Support',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Kode ini otomatis terisi di halaman donasi (kolom Kode Zenime) supaya username dan foto profilmu muncul di daftar.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.backgroundDarkSecondary,
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _Tone.rose,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _copyCode,
                    tooltip: 'Salin kode',
                    icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BARIS PERINGKAT 4+
// ─────────────────────────────────────────────────────────────────────────────

/// Fade + geser halus saat baris muncul (hanya ~10 baris pertama).
class _FadeSlideIn extends StatefulWidget {
  const _FadeSlideIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn> with SingleTickerProviderStateMixin {
  late final bool _animate = widget.index < 10;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.25),
    end: Offset.zero,
  ).animate(_curve);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_animate) {
      _timer = Timer(Duration(milliseconds: 900 + widget.index * 70), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _SupporterRow extends StatelessWidget {
  const _SupporterRow({
    required this.rank,
    required this.s,
    required this.ratio,
    required this.barDelayMs,
  });

  final int rank;
  final TopSupporter s;

  /// Nominal relatif terhadap donatur #1 (0..1), buat bar tipis di bawah baris.
  final double ratio;
  final int barDelayMs;

  @override
  Widget build(BuildContext context) {
    final nameColor = _parseHex(s.usernameColor) ?? AppColors.textWhite;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: (s.firebaseUid) == null || (s.firebaseUid)!.isEmpty ? null : () => openPublicProfile(context, s.firebaseUid!),
      child: Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppColors.surfaceDark,
            AppColors.surfaceDark.withValues(alpha: 0.72),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              UserAvatar(username: s.name, url: s.avatarUrl, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: nameColor,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (s.isLinked)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.verified, size: 15, color: _Tone.verified),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.donationCount}x dukungan',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _rp(s.totalAmount),
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Bar proporsi terhadap donatur #1, tumbuh halus saat muncul.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: ratio.clamp(0.0, 1.0)),
            duration: Duration(milliseconds: 700 + barDelayMs),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(height: 3, color: Colors.white.withValues(alpha: 0.06)),
                  FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      height: 3,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [_Tone.magenta, _Tone.rose, _Tone.gold]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
