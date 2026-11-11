import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/affinity_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/app_toast.dart';
import '../../glass/glass.dart';
import '../../redesign/z_kit.dart';
import '../profile/profile_screen.dart' show ProfileAvatar;
import '../profile/public_profile_screen.dart' show openPublicProfile;
import 'affinity_add_screen.dart';
import 'affinity_fx.dart';
import 'affinity_providers.dart';
import 'affinity_screen.dart' show affinityDate;

/// Detail satu ikatan: avatar berdua + cap, level 5 tahap, statistik, momen.
class AffinityDetailScreen extends ConsumerWidget {
  const AffinityDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(affinityDetailProvider(id));
    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet)),
        error: (e, _) => _Message(
          text: errorMessage(e, 'Gagal memuat ikatan'),
          onRetry: () => ref.invalidate(affinityDetailProvider(id)),
        ),
        data: (d) => d == null
            ? const _Message(text: 'Ikatan ini sudah tidak ada')
            : _DetailBody(detail: d),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.detail});

  final AffinityDetail detail;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _busy = false;

  Future<void> _break(AffinityPerson other) async {
    final d = widget.detail;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        title: Text('Putuskan ikatan ${d.type.label}?', style: const TextStyle(color: AppColors.textWhite)),
        content: Text(
          'Poin, level, dan momen bersama ${other.displayName} akan hilang. ${other.displayName} akan diberi tahu.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Putuskan', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(affinityRepositoryProvider).breakBond(d.id);
      HapticFeedback.mediumImpact();
      refreshAffinity(ref, uid: d.a.uid, otherUid: d.b.uid);
      if (!mounted) return;
      showAppToast(context, 'Ikatan diputuskan');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppToast(context, errorMessage(e, 'Gagal memutuskan ikatan'), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final me = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final (left, right) = d.ordered(me);
    final c = d.type.color;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final mine = d.viewerIn;
    final other = left.uid == me ? right : left;
    final progress = AffinityLevels.progress(d.points, d.level, d.levels);
    final next = d.level < d.levels.length ? d.levels[d.level] : null;

    Widget person(AffinityPerson p) => AffinityTap(
          onTap: () => openPublicProfile(context, p.uid),
          child: ProfileAvatar(url: p.avatarUrl, seed: p.uid, label: p.displayName, size: 62),
        );

    Widget thread() => Container(
          width: 30,
          height: 2,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, c, Colors.transparent])),
        );

    String nameWithRole(AffinityPerson p) {
      final r = affinityRoleLabel(p.role);
      return r.isEmpty ? p.displayName : '${p.displayName} ($r)';
    }

    return RefreshIndicator(
      color: AppColors.accentViolet,
      onRefresh: () async => ref.invalidate(affinityDetailProvider(d.id)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.only(bottom: 28 + bottom),
        children: [
          // Hero
          Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.2),
                      radius: 0.8,
                      colors: [c.withValues(alpha: 0.26), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Text(
                    d.type.kanji,
                    style: affinityKanjiStyle(color: c.withValues(alpha: 0.06), size: 210),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, top + 56, 16, 18),
                child: Column(
                  children: [
                    AffinityRise(
                      index: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          person(left),
                          thread(),
                          AffinitySeal(
                            type: d.type,
                            size: 64,
                            delay: const Duration(milliseconds: 200),
                            beat: d.type == AffinityType.soulmate,
                            clash: d.type == AffinityType.rival,
                          ),
                          thread(),
                          person(right),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: nameWithRole(left), style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
                        const TextSpan(text: '  ×  '),
                        TextSpan(text: nameWithRole(right), style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
                      ]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Text(d.type.jp, style: ZFont.jp(size: 12.5, color: c, letterSpacing: 4)),
                    const SizedBox(height: 2),
                    Text(d.type.label.toUpperCase(), style: ZFont.display(size: 24, letterSpacing: 2.4)),
                    const SizedBox(height: 4),
                    Text(
                      'Bersama sejak ${affinityDate(d.since)} · ${d.days} hari',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: top + 6,
                left: 6,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'Kembali',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textWhite),
                ),
              ),
            ],
          ),
          // Level
          AffinityRise(
            index: 1,
            child: _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('Lv ${d.level}', style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Text('${AffinityLevels.jpName(d.level)} ${AffinityLevels.name(d.level)}',
                          style: ZFont.jp(size: 12, color: c, letterSpacing: 0)),
                      const Spacer(),
                      Text(
                        next == null ? '${d.points} poin · maks' : '${d.points} / $next',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AffinitySheenBar(value: progress, color: c, height: 6, delay: const Duration(milliseconds: 300)),
                  const SizedBox(height: 14),
                  _Steps(level: d.level, color: c),
                ],
              ),
            ),
          ),
          // Statistik
          AffinityRise(
            index: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  for (final (k, label) in const [('chess', 'Catur bareng'), ('nobar', 'Nobar'), ('chat', 'Pesan')]) ...[
                    if (k != 'chess') const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x12FFFFFF)),
                        ),
                        child: Column(
                          children: [
                            AffinityCountUp(value: d.stats[k] ?? 0, style: ZFont.display(size: 18, height: 1.1)),
                            const SizedBox(height: 2),
                            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if ((d.stats['gift'] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('🎁 ${d.stats['gift']} hari Premium sudah dihadiahkan',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
            ),
          // Momen
          AffinityRise(
            index: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('思い出', style: ZFont.jp(size: 10.5, color: AppColors.accentVioletLight)),
                  Text('Momen', style: ZFont.display(size: 15)),
                  const SizedBox(height: 10),
                  if (d.moments.isEmpty)
                    const Text('Belum ada momen', style: TextStyle(color: AppColors.textMuted, fontSize: 12))
                  else
                    for (final m in d.moments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: c.withValues(alpha: 0.25), spreadRadius: 3)],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.text(d.type), style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5)),
                                  Text(affinityDate(m.createdAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
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
          if (mine) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                await Navigator.of(context).push<void>(fadeRoute(AffinityAddScreen(
                                  presetUid: other.uid,
                                  presetName: other.displayName,
                                  presetAvatar: other.avatarUrl,
                                )));
                                ref.invalidate(affinityDetailProvider(d.id));
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textWhite,
                          side: const BorderSide(color: Color(0x1FFFFFFF)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text('Ganti jenis', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _break(other),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.errorRed,
                          side: BorderSide(color: AppColors.errorRed.withValues(alpha: 0.35)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.link_off_rounded, size: 18),
                        label: const Text('Putuskan', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
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

class _Steps extends StatelessWidget {
  const _Steps({required this.level, required this.color});

  final int level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 20,
          right: 20,
          top: 12,
          child: Container(height: 2, color: const Color(0x14FFFFFF)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var k = 1; k <= 5; k++)
              SizedBox(
                width: 52,
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: Duration(milliseconds: 300 + 120 * k),
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: k <= level ? Color.alphaBlend(color.withValues(alpha: 0.25), AppColors.backgroundDark) : AppColors.surfaceCard,
                        border: Border.all(color: k <= level ? color : const Color(0x1AFFFFFF), width: 1.5),
                        boxShadow: k == level ? [BoxShadow(color: color.withValues(alpha: 0.25), spreadRadius: 4)] : null,
                      ),
                      child: Text(
                        AffinityLevels.short[k - 1],
                        style: affinityKanjiStyle(color: k <= level ? color : AppColors.textMuted, size: 11),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(AffinityLevels.names[k - 1],
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: child,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Coba lagi', style: TextStyle(color: AppColors.accentViolet))),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Kembali', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
