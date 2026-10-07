import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/xp_models.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';
import '../../components/role_badges.dart';
import '../profile/public_profile_screen.dart';

/// Leaderboard XP: podium top-3 futuristik + daftar peringkat, lengkap dengan
/// badge clan & level (setara tampilan Zenime). XP yang tampil adalah XP nonton
/// BULAN BERJALAN (reset tiap tanggal 1 WIB); level tetap kumulatif.
class XpLeaderboardScreen extends ConsumerWidget {
  const XpLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(xpLeaderboardProvider);
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid;

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
            Text('Leaderboard XP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(
              'Bulan ini • reset tiap tanggal 1',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Aura ungu-cyan di belakang podium.
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
                      AppColors.accentViolet.withValues(alpha: 0.32),
                      _Neon.cyan.withValues(alpha: 0.05),
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
              child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
            ),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Gagal ambil leaderboard',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(xpLeaderboardProvider),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return const Center(
                  child: Text(
                    'Belum ada yang nonton bulan ini.\nJadi yang pertama naik XP!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                );
              }
              final top3 = entries.take(3).toList();
              final rest = entries.skip(3).toList();
              return RefreshIndicator(
                color: AppColors.accentViolet,
                onRefresh: () async => ref.refresh(xpLeaderboardProvider.future),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: 1 + rest.length,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _Podium(top3: top3, myUid: myUid),
                      );
                    }
                    final e = rest[i - 1];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StaggerIn(
                        index: i - 1,
                        child: _RankRow(rank: i + 3, entry: e, isMe: e.firebaseUid == myUid),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Warna aksen neon + medali.
class _Neon {
  _Neon._();

  static const Color cyan = Color(0xFF00E5FF);
  static const Color gold = Color(0xFFFFD54A);
  static const Color silver = Color(0xFFC9D6EA);
  static const Color bronze = Color(0xFFE08A4B);
  static const Color xp = Color(0xFFFFC107);
}

String _fmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// PODIUM
// ─────────────────────────────────────────────────────────────────────────────

class _Podium extends StatefulWidget {
  const _Podium({required this.top3, required this.myUid});

  final List<UserXpDisplay> top3;
  final String? myUid;

  @override
  State<_Podium> createState() => _PodiumState();
}

class _PodiumState extends State<_Podium> with TickerProviderStateMixin {
  // Animasi masuk sekali jalan (podium naik, avatar jatuh halus, XP menghitung).
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..forward();

  // Loop 6 detik: semua gerak berulang memakai kelipatan bulat dari periode ini
  // supaya sambungan loop-nya mulus (tanpa loncat).
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
    UserXpDisplay? at(int i) => i < widget.top3.length ? widget.top3[i] : null;
    final first = at(0), second = at(1), third = at(2);

    Widget slot(UserXpDisplay? e, int rank) {
      if (e == null) return const Expanded(child: SizedBox.shrink());
      final cfg = switch (rank) {
        1 => (_Neon.gold, 78.0, 104.0, 0.20),
        2 => (_Neon.silver, 62.0, 78.0, 0.10),
        _ => (_Neon.bronze, 62.0, 58.0, 0.00),
      };
      return Expanded(
        child: _PodiumSlot(
          entry: e,
          rank: rank,
          isMe: e.firebaseUid == widget.myUid,
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
            colors: [Color(0xFF3A1520), Color(0xFF0D1017)],
          ),
          border: Border.all(color: _Neon.cyan.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentViolet.withValues(alpha: 0.30),
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
              Positioned.fill(child: CustomPaint(painter: _BackdropPainter(_loop))),
              SizedBox(
                height: 360,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 18, 6, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [slot(second, 2), slot(first, 1), slot(third, 3)],
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

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({
    required this.entry,
    required this.rank,
    required this.isMe,
    required this.color,
    required this.avatarSize,
    required this.pedestalHeight,
    required this.start,
    required this.intro,
    required this.loop,
  });

  final UserXpDisplay entry;
  final int rank;
  final bool isMe;
  final Color color;
  final double avatarSize;
  final double pedestalHeight;

  /// Awal jendela animasi masuk (0..0.2) supaya muncul berurutan 3 → 2 → 1.
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
      onTap: () => openPublicProfile(context, entry.firebaseUid),
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
                child: _info((entry.xp * count).round()),
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
          // Halo berdenyut.
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
          // Ring gradient yang berputar.
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
                color: AppColors.backgroundDarkSecondary,
              ),
              child: UserAvatar(username: entry.username, url: entry.avatarUrl, size: avatarSize),
            ),
          ),
          // Chip nomor peringkat.
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
                border: Border.all(color: AppColors.backgroundDarkSecondary, width: 2),
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

  Widget _info(int shownXp) {
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
                  entry.username + (isMe ? ' (Kamu)' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: rank == 1 ? 13.5 : 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: UserCheckBadge(
                  firebaseUid: entry.firebaseUid,
                  isPremium: entry.isPremium,
                  size: 14,
                ),
              ),
            ],
          ),
          if (entry.clanTag != null && entry.clanTag!.isNotEmpty) ...[
            const SizedBox(height: 5),
            FittedBox(fit: BoxFit.scaleDown, child: ClanRainbowBadge(text: entry.clanTag!)),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${_fmt(shownXp)} XP',
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pedestal(double height, double t, double loopV) {
    final glow = 0.5 + 0.5 * math.sin(loopV * 2 * math.pi * 2 + rank);
    final radius = const BorderRadius.vertical(top: Radius.circular(16));
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
                    colors: [color.withValues(alpha: 0.40), color.withValues(alpha: 0.04)],
                  ),
                ),
              ),
            ),
            // Kilau diagonal yang lewat berkala (khusus juara 1 lebih terang).
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
            // Garis neon di sisi atas.
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

/// Latar podium: spotlight, grid perspektif yang bergerak pelan, partikel naik,
/// dan garis scan. Semua periodik terhadap [t] (loop 6 detik).
class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final v = t.value;

    // Spotlight di belakang juara 1.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accentViolet.withValues(alpha: 0.38),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: Offset(w / 2, h * 0.30), radius: w * 0.65)),
    );

    // Grid perspektif.
    final horizon = h * 0.46;
    final gridPaint = Paint()..strokeWidth = 1;
    const rows = 9;
    for (var i = 0; i < rows; i++) {
      final p = (i + v) / rows;
      final y = horizon + (h - horizon) * p * p;
      gridPaint.color = _Neon.cyan.withValues(alpha: 0.03 + 0.11 * p);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
    const cols = 7;
    for (var k = -cols; k <= cols; k++) {
      final x = w / 2 + k * (w / 6.5);
      gridPaint.color = _Neon.cyan.withValues(alpha: 0.09);
      canvas.drawLine(Offset(w / 2 + k * (w / 60), horizon), Offset(x, h), gridPaint);
    }

    // Garis scan turun sekali per loop.
    final sy = h * v;
    canvas.drawRect(
      Rect.fromLTWH(0, sy - 26, w, 52),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _Neon.cyan.withValues(alpha: 0),
            _Neon.cyan.withValues(alpha: 0.10),
            _Neon.cyan.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, sy - 26, w, 52)),
    );

    // Partikel naik pelan.
    final pp = Paint();
    for (var i = 0; i < 16; i++) {
      final speed = 1 + (i % 3); // bulat => loop mulus
      final p = (i * 0.137 + v * speed) % 1.0;
      final x = ((i * 0.6180339887) % 1.0) * w + math.sin((p + i) * 2 * math.pi) * 6;
      final y = h * (1 - p);
      final a = math.sin(p * math.pi) * 0.7;
      pp.color = (i.isEven ? _Neon.cyan : Colors.white).withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), 0.8 + (i % 3) * 0.5, pp);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// BARIS PERINGKAT 4+
// ─────────────────────────────────────────────────────────────────────────────

/// Fade + geser halus saat baris pertama kali muncul (hanya ~10 baris pertama,
/// sisanya langsung tampil supaya scroll tetap ringan).
class _StaggerIn extends StatefulWidget {
  const _StaggerIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
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
      // Mulai setelah podium hampir selesai naik.
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

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.entry, required this.isMe});

  final int rank;
  final UserXpDisplay entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final hasClan = entry.clanTag != null && entry.clanTag!.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openPublicProfile(context, entry.firebaseUid),
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: isMe
              ? [
                  AppColors.accentViolet.withValues(alpha: 0.30),
                  _Neon.cyan.withValues(alpha: 0.10),
                ]
              : [
                  AppColors.surfaceDark,
                  AppColors.surfaceDark.withValues(alpha: 0.72),
                ],
        ),
        border: Border.all(
          color: isMe
              ? _Neon.cyan.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.05),
        ),
        boxShadow: isMe
            ? [BoxShadow(color: _Neon.cyan.withValues(alpha: 0.16), blurRadius: 14)]
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: isMe ? _Neon.cyan : AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          UserAvatar(username: entry.username, url: entry.avatarUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.username + (isMe ? ' (Kamu)' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: UserCheckBadge(
                        firebaseUid: entry.firebaseUid,
                        isPremium: entry.isPremium,
                        size: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LevelBadge(level: entry.level),
                    if (hasClan) ClanRainbowBadge(text: entry.clanTag!),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(entry.xp),
                style: const TextStyle(
                  color: _Neon.xp,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Text(
                'XP',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }
}
