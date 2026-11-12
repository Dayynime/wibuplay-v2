import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/affinity_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../glass/glass.dart';
import '../../redesign/z_kit.dart';
import '../profile/profile_screen.dart' show ProfileAvatar;
import 'affinity_add_screen.dart';
import 'affinity_detail_screen.dart';
import 'affinity_fx.dart';
import 'affinity_providers.dart';
import 'affinity_requests_sheet.dart';
import 'affinity_tutorial.dart';

const _line = Color(0x14FFFFFF);
const _line2 = Color(0x0DFFFFFF);

String affinityDate(DateTime? d) {
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// Buka halaman Afinitas milik [uid].
Future<void> openAffinityScreen(BuildContext context, String uid, {String? name, bool canInvite = false}) {
  return Navigator.of(context).push<void>(fadeRoute(AffinityScreen(uid: uid, name: name, canInvite: canInvite)));
}

/// Halaman semua afinitas seorang user: Soulmate, ikatan 1 slot, grup 5 slot,
/// lalu peringkat terdekat. Profil sendiri bisa menambah; profil teman bisa
/// "Ajak afinitas" kalau [canInvite].
class AffinityScreen extends ConsumerStatefulWidget {
  const AffinityScreen({super.key, required this.uid, this.name, this.canInvite = false});

  final String uid;
  final String? name;
  final bool canInvite;

  @override
  ConsumerState<AffinityScreen> createState() => _AffinityScreenState();
}

class _AffinityScreenState extends ConsumerState<AffinityScreen> {
  String get uid => widget.uid;
  String? get name => widget.name;
  bool get canInvite => widget.canInvite;

  @override
  void initState() {
    super.initState();
    // Tutorial otomatis sekali saat pertama kali membuka halaman Afinitas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowAffinityTutorial(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final own = me.isNotEmpty && me == uid;
    final async = ref.watch(affinityListProvider(uid));
    final ownerProfile = ref.watch(chatProfileProvider(uid)).valueOrNull;
    final ownerName = (ownerProfile?.username.trim().isNotEmpty ?? false) ? ownerProfile!.username : (name ?? '');

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet),
            ),
          ),
          error: (e, _) => _ErrorView(
            message: errorMessage(e, 'Gagal memuat afinitas'),
            onRetry: () => ref.invalidate(affinityListProvider(uid)),
          ),
          data: (list) => RefreshIndicator(
            color: AppColors.accentViolet,
            backgroundColor: AppColors.surfaceDark,
            onRefresh: () async {
              ref.invalidate(affinityListProvider(uid));
              await ref.read(affinityListProvider(uid).future).catchError((_) => const AffinityList());
            },
            child: _AffinityBody(
              uid: uid,
              ownerName: ownerName,
              ownerAvatar: ownerProfile?.avatarUrl,
              own: own,
              canInvite: canInvite && !own,
              list: list,
            ),
          ),
        ),
      ),
    );
  }
}

class _AffinityBody extends ConsumerWidget {
  const _AffinityBody({
    required this.uid,
    required this.ownerName,
    required this.ownerAvatar,
    required this.own,
    required this.canInvite,
    required this.list,
  });

  final String uid;
  final String ownerName;
  final String? ownerAvatar;
  final bool own;
  final bool canInvite;
  final AffinityList list;

  void _openDetail(BuildContext context, AffinityItem it) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push<void>(fadeRoute(AffinityDetailScreen(id: it.id)));
  }

  Future<void> _openAdd(BuildContext context, WidgetRef ref, {AffinityType? type}) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<void>(fadeRoute(
      own ? AffinityAddScreen(presetType: type) : AffinityAddScreen(presetUid: uid, presetName: ownerName, presetAvatar: ownerAvatar, presetType: type),
    ));
    refreshAffinity(ref, uid: uid);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var i = 0;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final groups = [AffinityType.nakama, AffinityType.kin, AffinityType.senpai, AffinityType.rival];
    final closest = [...list.items]..sort((a, b) => b.points.compareTo(a.points));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(18, 4, 18, 30 + bottom),
      children: [
        // Bar atas
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Kembali',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textWhite),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => showAffinityTutorial(context),
              tooltip: 'Cara kerja Afinitas',
              icon: const Icon(Icons.help_outline_rounded, size: 22, color: AppColors.textWhite),
            ),
            if (own)
              IconButton(
                onPressed: () => showAffinityOutgoingSheet(context),
                tooltip: 'Permintaan terkirim',
                icon: Badge(
                  isLabelVisible: list.outgoing > 0,
                  label: Text('${list.outgoing}'),
                  backgroundColor: AppColors.accentViolet,
                  child: const Icon(Icons.outbox_rounded, size: 22, color: AppColors.textWhite),
                ),
              ),
          ],
        ),
        AffinityRise(index: i++, child: _Header(name: ownerName, total: list.items.length)),
        if (own && list.incoming > 0)
          AffinityRise(
            index: i++,
            child: _IncomingBanner(
              count: list.incoming,
              onTap: () async {
                await showAffinityIncomingSheet(context);
                refreshAffinity(ref, uid: uid);
              },
            ),
          ),
        AffinityRise(
          index: i,
          child: _SoulmateBlock(
            item: list.ofType(AffinityType.soulmate).firstOrNull,
            ownerUid: uid,
            ownerName: ownerName,
            ownerAvatar: ownerAvatar,
            levels: list.levels,
            sealDelay: Duration(milliseconds: 70 * i++ + 180),
            own: own,
            onOpen: (it) => _openDetail(context, it),
            onAdd: () => _openAdd(context, ref, type: AffinityType.soulmate),
          ),
        ),
        AffinityRise(
          index: i,
          child: _SinglesRow(
            list: list,
            sealDelay: Duration(milliseconds: 70 * i++ + 180),
            own: own,
            onOpen: (it) => _openDetail(context, it),
            onAdd: (t) => _openAdd(context, ref, type: t),
          ),
        ),
        for (final g in groups)
          AffinityRise(
            index: i,
            child: _GroupRow(
              type: g,
              items: list.ofType(g),
              max: list.slotsOf(g),
              levels: list.levels,
              delay: Duration(milliseconds: 70 * i++),
              own: own,
              onOpen: (it) => _openDetail(context, it),
              onAdd: () => _openAdd(context, ref, type: g),
            ),
          ),
        if (closest.isNotEmpty)
          AffinityRise(
            index: i,
            child: _Closest(
              items: closest.take(5).toList(),
              levels: list.levels,
              delay: Duration(milliseconds: 70 * i++),
              onOpen: (it) => _openDetail(context, it),
            ),
          ),
        if (own || canInvite)
          AffinityRise(
            index: i++,
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: ZPress(
                onTap: () => _openAdd(context, ref),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: own ? Colors.transparent : AppColors.accentViolet,
                    borderRadius: BorderRadius.circular(14),
                    border: own ? Border.all(color: _line) : null,
                  ),
                  child: Text(
                    own ? '+ Tambah afinitas' : '+ Ajak afinitas',
                    style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.total});

  final String name;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name.isNotEmpty)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 2),
                Text('Afinitas', style: ZFont.display(size: 27, height: 1.1)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AffinityCountUp(value: total, style: ZFont.display(size: 34, height: 1)),
              const SizedBox(height: 3),
              const Text('ikatan', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomingBanner extends StatelessWidget {
  const _IncomingBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ZPress(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: AppColors.accentViolet.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accentViolet.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.mark_email_unread_rounded, size: 18, color: AppColors.accentVioletLight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count permintaan afinitas menunggu',
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label jenis: cap kanji + nama + nama Jepang + teks kanan.
class AffinityLabel extends StatelessWidget {
  const AffinityLabel({
    super.key,
    required this.type,
    this.trailing,
    this.sealDelay = Duration.zero,
    this.beat = false,
    this.clash = false,
  });

  final AffinityType type;
  final String? trailing;
  final Duration sealDelay;
  final bool beat;
  final bool clash;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AffinitySeal(type: type, size: 22, delay: sealDelay, beat: beat, clash: clash),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            type.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 6),
        Text(type.jp, style: ZFont.jp(size: 11, weight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0)),
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.uid, required this.url, required this.name, required this.size});

  final String uid;
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) =>
      ProfileAvatar(url: url, seed: uid.isEmpty ? name : uid, label: name, size: size);
}

class _SoulmateBlock extends StatelessWidget {
  const _SoulmateBlock({
    required this.item,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerAvatar,
    required this.levels,
    required this.sealDelay,
    required this.own,
    required this.onOpen,
    required this.onAdd,
  });

  final AffinityItem? item;
  final String ownerUid;
  final String ownerName;
  final String? ownerAvatar;
  final List<int> levels;
  final Duration sealDelay;
  final bool own;
  final ValueChanged<AffinityItem> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return Container(
      padding: const EdgeInsets.only(top: 20, bottom: 18),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AffinityLabel(
            type: AffinityType.soulmate,
            trailing: it == null ? null : 'Lv ${it.level}',
            sealDelay: sealDelay,
            beat: it != null,
          ),
          const SizedBox(height: 14),
          if (it == null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: own ? onAdd : null,
              child: Row(
                children: [
                  const AffinityEmptySlot(size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      own ? 'Belum ada Soulmate. Ketuk untuk mengajak.' : 'Belum ada Soulmate',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            )
          else
            AffinityTap(
              onTap: () => onOpen(it),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    height: 58,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Positioned.fill(child: AffinityRedThread()),
                        Align(
                          alignment: Alignment.topLeft,
                          child: AffinityLean(
                            size: 52,
                            overlap: 14,
                            left: _Avatar(uid: ownerUid, url: ownerAvatar, name: ownerName, size: 52),
                            right: DecoratedBox(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: AppColors.backgroundDark, spreadRadius: 3)],
                              ),
                              child: _Avatar(uid: it.otherUid, url: it.avatarUrl, name: it.displayName, size: 52),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pasangan sejak ${affinityDate(it.since)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AffinityCountUp(value: it.days, style: ZFont.display(size: 22, height: 1)),
                      const SizedBox(height: 3),
                      const Text('hari', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SinglesRow extends StatelessWidget {
  const _SinglesRow({
    required this.list,
    required this.sealDelay,
    required this.own,
    required this.onOpen,
    required this.onAdd,
  });

  final AffinityList list;
  final Duration sealDelay;
  final bool own;
  final ValueChanged<AffinityItem> onOpen;
  final ValueChanged<AffinityType> onAdd;

  @override
  Widget build(BuildContext context) {
    const types = [AffinityType.partner, AffinityType.crush, AffinityType.twin];
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < types.length; k++) ...[
              if (k > 0) const VerticalDivider(width: 1, thickness: 1, color: _line2),
              Expanded(
                child: _SingleCell(
                  type: types[k],
                  item: list.ofType(types[k]).firstOrNull,
                  sealDelay: sealDelay + Duration(milliseconds: 60 * k),
                  own: own,
                  first: k == 0,
                  onOpen: onOpen,
                  onAdd: () => onAdd(types[k]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SingleCell extends StatelessWidget {
  const _SingleCell({
    required this.type,
    required this.item,
    required this.sealDelay,
    required this.own,
    required this.first,
    required this.onOpen,
    required this.onAdd,
  });

  final AffinityType type;
  final AffinityItem? item;
  final Duration sealDelay;
  final bool own;
  final bool first;
  final ValueChanged<AffinityItem> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: it != null ? () => onOpen(it) : (own ? onAdd : null),
      child: Padding(
        padding: EdgeInsets.fromLTRB(first ? 0 : 12, 16, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AffinitySeal(type: type, size: 18, delay: sealDelay),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    type.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textWhite, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: it == null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        own ? 'Belum ada · ajak' : 'Belum ada',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                    )
                  : Row(
                      children: [
                        _Avatar(uid: it.otherUid, url: it.avatarUrl, name: it.displayName, size: 34),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                it.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5, fontWeight: FontWeight.w700),
                              ),
                              Text('Lv ${it.level}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
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

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.type,
    required this.items,
    required this.max,
    required this.levels,
    required this.delay,
    required this.own,
    required this.onOpen,
    required this.onAdd,
  });

  final AffinityType type;
  final List<AffinityItem> items;
  final int max;
  final List<int> levels;
  final Duration delay;
  final bool own;
  final ValueChanged<AffinityItem> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var k = 0; k < max; k++) {
      final it = k < items.length ? items[k] : null;
      if (it == null) {
        cells.add(GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: own ? onAdd : null,
          child: const Column(
            children: [
              AffinityEmptySlot(size: 54),
              SizedBox(height: 6),
              Text('Kosong', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ));
        continue;
      }
      final role = affinityRoleLabel(it.otherRole);
      cells.add(AffinityTap(
        onTap: () => onOpen(it),
        child: Column(
          children: [
            AffinityLevelRing(
              color: type.color,
              progress: AffinityLevels.progress(it.points, it.level, levels),
              size: 54,
              delay: delay + const Duration(milliseconds: 300),
              child: _Avatar(uid: it.otherUid, url: it.avatarUrl, name: it.displayName, size: 46),
            ),
            const SizedBox(height: 6),
            Text(
              it.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 1),
            Text.rich(
              TextSpan(children: [
                if (role.isNotEmpty) TextSpan(text: '$role · ', style: TextStyle(color: type.color)),
                TextSpan(text: 'Lv ${it.level}'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ),
      ));
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AffinityLabel(
          type: type,
          trailing: '${items.length}/$max',
          sealDelay: delay + const Duration(milliseconds: 180),
          clash: type == AffinityType.rival,
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 4,
          childAspectRatio: 0.62,
          padding: EdgeInsets.zero,
          children: cells,
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: type == AffinityType.senpai
          ? Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                content,
                const Positioned.fill(child: AffinitySakura()),
              ],
            )
          : content,
    );
  }
}

class _Closest extends StatelessWidget {
  const _Closest({required this.items, required this.levels, required this.delay, required this.onOpen});

  final List<AffinityItem> items;
  final List<int> levels;
  final Duration delay;
  final ValueChanged<AffinityItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Paling dekat', style: TextStyle(color: AppColors.textWhite, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (var k = 0; k < items.length; k++)
            AffinityTap(
              onTap: () => onOpen(items[k]),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: k == 0 ? null : const Border(top: BorderSide(color: _line2)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(
                        '${k + 1}',
                        style: TextStyle(
                          color: k == 0 ? const Color(0xFFE8B04A) : AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _Avatar(uid: items[k].otherUid, url: items[k].avatarUrl, name: items[k].displayName, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: items[k].displayName,
                                style: const TextStyle(color: AppColors.textWhite, fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: '  ${items[k].type.label}',
                                style: TextStyle(color: items[k].type.color, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 7),
                          AffinitySheenBar(
                            value: AffinityLevels.overall(items[k].points, items[k].level, levels),
                            color: items[k].type.color,
                            delay: delay + Duration(milliseconds: 250 + 60 * k),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Lv ${items[k].level}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text('Coba lagi', style: TextStyle(color: AppColors.accentViolet)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Kembali', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
