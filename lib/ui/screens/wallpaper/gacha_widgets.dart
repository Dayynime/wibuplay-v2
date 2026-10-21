import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/wallpaper_models.dart';
import '../../components/rarity_chip.dart';

// =============================================================================
// Komponen layar Gacha Wallpaper (desain "banner gacha").
// Semua angka (peluang, harga, jam event) dari server; di sini cuma tampilan.
// =============================================================================

const Color _silverInk = Color(0xFF1C2230);
const Color _line = Color(0x14FFFFFF);

/// Rebuild tiap detik pakai jam server ([clockOffset]). [boundaries] = jam
/// mulai/selesai event: saat salah satunya terlewati, [onBoundary] dipanggil
/// sekali (dengan jeda 2 detik supaya server pasti sudah melewatinya juga).
class ServerClock extends StatefulWidget {
  const ServerClock({
    super.key,
    required this.clockOffset,
    required this.builder,
    this.boundaries = const [],
    this.onBoundary,
  });

  final Duration clockOffset;
  final List<DateTime> boundaries;
  final VoidCallback? onBoundary;
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<ServerClock> createState() => _ServerClockState();
}

class _ServerClockState extends State<ServerClock> {
  Timer? _t;
  final Set<DateTime> _fired = {};

  DateTime get _now => DateTime.now().toUtc().add(widget.clockOffset);

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = _now;
      for (final b in widget.boundaries) {
        final due = b.add(const Duration(seconds: 2));
        if (now.isAfter(due) && now.isBefore(due.add(const Duration(seconds: 5))) && _fired.add(b)) {
          widget.onBoundary?.call();
          break;
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}

/// Kilau yang menyapu (dipakai badge & bingkai Limited). Diam kalau
/// "kurangi animasi" aktif.
class _Sheen extends StatefulWidget {
  const _Sheen({required this.child, this.period = const Duration(milliseconds: 3200), this.opacity = 0.7});

  final Widget child;
  final Duration period;
  final double opacity;

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final t = (_c.value / 0.5).clamp(0.0, 1.0);
                final x = -1.8 + t * 3.6;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(x - 0.5, -1),
                      end: Alignment(x + 0.5, 1),
                      colors: [
                        const Color(0x00FFFFFF),
                        Colors.white.withValues(alpha: widget.opacity),
                        const Color(0x00FFFFFF),
                      ],
                      stops: const [0.42, 0.5, 0.58],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================ banner utama

/// Banner utama. Kalau ada event berjalan yang punya wallpaper di pool,
/// tampil sebagai banner Limited (bingkai silver + hitung mundur). Kalau tidak,
/// banner standar dengan wallpaper unggulan bergantian.
class GachaBanner extends StatelessWidget {
  const GachaBanner({
    super.key,
    required this.now,
    required this.featured,
    required this.index,
    required this.poolSize,
    required this.onOpen,
    this.event,
  });

  final DateTime now;

  /// Event yang sedang berjalan (null = banner standar).
  final WallpaperEvent? event;
  final List<WallpaperItem> featured;
  final int index;
  final int poolSize;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final w = featured.isEmpty ? null : featured[index % featured.length];
    final limited = e != null;

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(limited ? 22.5 : 24),
      child: ColoredBox(
        color: AppColors.surfaceDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 16 / 10, child: _art(w, limited)),
            if (e != null) _eventPanel(e) else _standardPanel(),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTap: onOpen,
      child: limited
          ? Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: WallpaperRarity.limited.gradient,
                boxShadow: const [BoxShadow(color: Color(0x40DDE3EC), blurRadius: 28, spreadRadius: -6)],
              ),
              child: card,
            )
          : Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x1AFFFFFF)),
                boxShadow: [
                  BoxShadow(
                    color: (w?.rarity.color ?? AppColors.surfaceElevated).withValues(alpha: 0.22),
                    blurRadius: 30,
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: card,
            ),
    );
  }

  Widget _art(WallpaperItem? w, bool limited) {
    if (w == null) {
      return const ColoredBox(
        color: AppColors.surfaceVariantDark,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined, color: AppColors.textMuted, size: 38),
              SizedBox(height: 10),
              Text(
                'Belum ada wallpaper yang bisa didapat.\nCek lagi nanti.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          switchInCurve: Curves.easeOut,
          child: CachedNetworkImage(
            key: ValueKey(w.id),
            imageUrl: w.url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, __) => CachedNetworkImage(imageUrl: w.previewUrl, fit: BoxFit.cover),
            errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceVariantDark),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Colors.transparent, Colors.transparent, Color(0xF0151A23)],
              stops: [0, 0.3, 0.55, 1],
            ),
          ),
        ),
        // badge kiri atas
        Positioned(
          top: 12,
          left: 12,
          child: limited
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _Sheen(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                      decoration: BoxDecoration(gradient: WallpaperRarity.limited.gradient),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 13, color: _silverInk),
                          SizedBox(width: 5),
                          Text(
                            'LIMITED EVENT',
                            style: TextStyle(
                              color: _silverInk,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const _GlassTag(icon: Icons.style_outlined, text: 'BANNER STANDAR'),
        ),
        // tombol isi banner
        Positioned(
          top: 12,
          right: 12,
          child: _GlassTag(text: 'Isi banner ($poolSize)', trailing: Icons.chevron_right_rounded),
        ),
        // nama wallpaper unggulan
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.bottomLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  child: Column(
                    key: ValueKey('n-${w.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RarityChip(rarity: w.rarity),
                      const SizedBox(height: 6),
                      Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (featured.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      for (var i = 0; i < featured.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(left: 4),
                          width: i == index % featured.length ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == index % featured.length ? Colors.white : Colors.white38,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _standardPanel() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariantDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.wallpaper_rounded, color: AppColors.textSecondary, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wallpaper Komentar',
                    style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$poolSize wallpaper animasi • pasang sebagai latar komentarmu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _eventPanel(WallpaperEvent e) {
    final left = e.endsAt.difference(now);
    final d = left.isNegative ? Duration.zero : left;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w900, fontSize: 20, height: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            '${e.itemCount} wallpaper Limited • hanya sampai ${formatEventTime(e.endsAt)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _TimeBox(value: d.inDays, label: 'HARI'),
              const _Colon(),
              _TimeBox(value: d.inHours % 24, label: 'JAM'),
              const _Colon(),
              _TimeBox(value: d.inMinutes % 60, label: 'MENIT'),
              const _Colon(),
              _TimeBox(value: d.inSeconds % 60, label: 'DETIK'),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassTag extends StatelessWidget {
  const _GlassTag({required this.text, this.icon, this.trailing});

  final String text;
  final IconData? icon;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 5, trailing == null ? 10 : 6, 5),
        decoration: BoxDecoration(
          color: const Color(0x8C0B0E14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x2EFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 5)],
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4),
            ),
            if (trailing != null) Icon(trailing, size: 15, color: Colors.white),
          ],
        ),
      );
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariantDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x33D7DCE4)),
          ),
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFF), Color(0xFFB4BCC8)],
                ).createShader(r),
                child: Text(
                  value.toString().padLeft(2, '0'),
                  style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.1),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8),
              ),
            ],
          ),
        ),
      );
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(':', style: TextStyle(color: AppColors.textMuted, fontSize: 18, fontWeight: FontWeight.w800)),
      );
}

// ============================================================ event akan datang

class GachaUpcomingEvents extends StatelessWidget {
  const GachaUpcomingEvents({super.key, required this.events, required this.now});

  final List<WallpaperEvent> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final list = events.where((e) => e.isUpcoming(now)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final e in list.take(2))
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x26D7DCE4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: WallpaperRarity.limited.gradient,
                  ),
                  child: const Icon(Icons.event_rounded, color: _silverInk, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SEGERA HADIR',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.9,
                        ),
                      ),
                      Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      Text(
                        'Mulai ${formatEventTime(e.startsAt)}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariantDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        formatEventCountdown(e.startsAt.difference(now)),
                        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ============================================================ judul seksi

class GachaSectionTitle extends StatelessWidget {
  const GachaSectionTitle({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(color: AppColors.accentViolet, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  visualDensity: VisualDensity.compact,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(action!, style: const TextStyle(fontSize: 12.5)),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
          ],
        ),
      );
}

// ============================================================ hadiah unggulan

class GachaFeaturedRow extends StatelessWidget {
  const GachaFeaturedRow({super.key, required this.items, required this.ownedIds, required this.onTap});

  final List<WallpaperItem> items;
  final Set<String> ownedIds;
  final ValueChanged<WallpaperItem> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 156,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final w = items[i];
          final r = w.rarity;
          final owned = ownedIds.contains(w.id);
          return GestureDetector(
            onTap: () => onTap(w),
            child: Container(
              width: 128,
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: r.color.withValues(alpha: r.isShiny ? 0.8 : 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: w.previewUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceVariantDark),
                          ),
                          Positioned(top: 6, left: 6, child: RarityChip(rarity: r, fontSize: 9)),
                          if (owned)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: AppColors.successGreen,
                                child: Icon(Icons.check_rounded, size: 12, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${(w.chancePercent ?? 0).toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: r.isShiny ? AppColors.textSecondary : r.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
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
    );
  }
}

// ============================================================ peluang

class GachaOddsPanel extends StatelessWidget {
  const GachaOddsPanel({super.key, required this.state, required this.onShowAll});

  final WallpaperState state;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final by = state.chanceByRarity;
    final rarities = WallpaperRarity.values.reversed.where((r) => (by[r] ?? 0) > 0).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rarities.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in rarities.reversed)
                      Expanded(
                        flex: math.max(1, ((by[r] ?? 0) * 100).round()),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: r.gradient == null ? r.color : null, gradient: r.gradient),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          // grid 2 kolom: rarity + persen
          LayoutBuilder(
            builder: (_, c) {
              final w = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final r in rarities)
                    Container(
                      width: w,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariantDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: r.gradient == null ? r.color : null,
                              gradient: r.gradient,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.label,
                              style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${(by[r] ?? 0).toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: r.isShiny ? AppColors.textWhite : r.color,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (state.dupRefundPercent > 0)
            _InfoLine(
              icon: Icons.autorenew_rounded,
              text: 'Dapat yang sudah dimiliki? ${state.dupRefundPercent}% ZCoin kembali otomatis.',
            ),
          const _InfoLine(
            icon: Icons.verified_user_outlined,
            text: 'Hasil diacak di server, peluang di atas adalah angka asli.',
          ),
          const Divider(color: _line, height: 18),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onShowAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Peluang tiap wallpaper (${state.pool.length})',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
            ),
          ],
        ),
      );
}

/// Isi bottom sheet "peluang tiap wallpaper".
class GachaOddsList extends StatelessWidget {
  const GachaOddsList({super.key, required this.pool, required this.controller});

  final List<WallpaperItem> pool;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final list = [...pool]
      ..sort((a, b) {
        final r = b.rarity.index.compareTo(a.rarity.index);
        return r != 0 ? r : (a.chancePercent ?? 0).compareTo(b.chancePercent ?? 0);
      });
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: list.length + 1,
      separatorBuilder: (_, i) => i == 0 ? const SizedBox(height: 4) : const Divider(color: _line, height: 1),
      itemBuilder: (_, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Peluang tiap wallpaper',
              style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 17),
            ),
          );
        }
        final w = list[i - 1];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 60,
                  height: 38,
                  child: CachedNetworkImage(
                    imageUrl: w.previewUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surfaceVariantDark),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        RarityChip(rarity: w.rarity, fontSize: 9),
                        if (w.eventEndsAt != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              's/d ${formatEventTime(w.eventEndsAt!)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(w.chancePercent ?? 0).toStringAsFixed(2)}%',
                style: const TextStyle(color: AppColors.textWhite, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      },
    );
  }
}
