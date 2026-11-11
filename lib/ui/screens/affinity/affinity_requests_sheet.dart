import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/affinity_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/app_toast.dart';
import '../../redesign/z_kit.dart';
import '../profile/profile_screen.dart' show ProfileAvatar;
import 'affinity_fx.dart';
import 'affinity_providers.dart';

/// Permintaan afinitas yang masuk (dari banner halaman Afinitas).
Future<void> showAffinityIncomingSheet(BuildContext context, {String? focusId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _IncomingSheet(focusId: focusId),
  );
}

/// Permintaan yang saya kirim (bisa dibatalkan).
Future<void> showAffinityOutgoingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const _OutgoingSheet(),
  );
}

/// Tap notif `affinity_request` (lonceng / push).
Future<void> handleAffinityRequestNotification(WidgetRef ref, Map<String, dynamic> data) async {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  final ctx = nav.context;
  if (data['expired'] == true) {
    showAppToast(ctx, 'Permintaan afinitas ini sudah tidak berlaku', kind: ToastKind.info);
    return;
  }
  ref.invalidate(affinityIncomingProvider);
  await showAffinityIncomingSheet(ctx, focusId: data['request_id']?.toString());
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? AppColors.accentViolet;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: c.withValues(alpha: 0.22)),
        gradient: RadialGradient(
          center: const Alignment(0, -1.3),
          radius: 0.9,
          colors: [c.withValues(alpha: 0.22), AppColors.surfaceDark],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(4)),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _IncomingSheet extends ConsumerStatefulWidget {
  const _IncomingSheet({this.focusId});

  final String? focusId;

  @override
  ConsumerState<_IncomingSheet> createState() => _IncomingSheetState();
}

class _IncomingSheetState extends ConsumerState<_IncomingSheet> {
  final Set<String> _busy = {};

  Future<void> _respond(AffinityRequest r, bool accept) async {
    if (_busy.contains(r.id)) return;
    setState(() => _busy.add(r.id));
    try {
      final ok = await ref.read(affinityRepositoryProvider).respond(r.id, accept: accept);
      HapticFeedback.mediumImpact();
      final me = ref.read(authUserProvider).valueOrNull?.uid;
      refreshAffinity(ref, uid: me, otherUid: r.fromUid);
      if (!mounted) return;
      showAppToast(
        context,
        accept && ok ? 'Kalian sekarang ${r.type.label} 💞' : 'Permintaan ditolak',
        kind: accept ? ToastKind.success : ToastKind.info,
      );
    } catch (e) {
      if (mounted) showAppToast(context, errorMessage(e, 'Gagal memproses permintaan'), kind: ToastKind.error);
      ref.invalidate(affinityIncomingProvider);
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(affinityIncomingProvider);
    final me = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final myProfile = ref.watch(chatProfileProvider(me)).valueOrNull;
    final list = async.valueOrNull ?? const <AffinityRequest>[];
    final sorted = [...list];
    final f = widget.focusId;
    if (f != null) sorted.sort((a, b) => (a.id == f ? 0 : 1).compareTo(b.id == f ? 0 : 1));
    final accent = sorted.isNotEmpty ? sorted.first.type.color : null;

    Widget body;
    if (async.isLoading && list.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet)),
      );
    } else if (async.hasError && list.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(32),
        child: Text(errorMessage(async.error!, 'Gagal memuat permintaan'),
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
      );
    } else if (sorted.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(36),
        child: Text('Tidak ada permintaan afinitas', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
      );
    } else {
      body = ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const Divider(color: Color(0x14FFFFFF), height: 28),
        itemBuilder: (_, i) => _RequestCard(
          request: sorted[i],
          myUid: me,
          myName: myProfile?.username ?? '',
          myAvatar: myProfile?.avatarUrl,
          busy: _busy.contains(sorted[i].id),
          onAccept: () => _respond(sorted[i], true),
          onDecline: () => _respond(sorted[i], false),
        ),
      );
    }
    return _SheetFrame(accent: accent, child: body);
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.myUid,
    required this.myName,
    required this.myAvatar,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final AffinityRequest request;
  final String myUid;
  final String myName;
  final String? myAvatar;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final c = r.type.color;
    final fromRole = affinityRoleLabel(r.fromRole);
    final toRole = affinityRoleLabel(r.toRole);
    final title = fromRole.isNotEmpty ? '$fromRole-mu' : '${r.type.label}-mu';

    Widget thread() => Container(
          width: 28,
          height: 2,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, c, Colors.transparent])),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ProfileAvatar(url: r.avatarUrl, seed: r.fromUid, label: r.displayName, size: 52),
            thread(),
            AffinitySeal(type: r.type, size: 60, beat: r.type == AffinityType.soulmate, clash: r.type == AffinityType.rival),
            thread(),
            ProfileAvatar(url: myAvatar, seed: myUid, label: myName, size: 52),
          ],
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: r.displayName, style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
            TextSpan(text: r.currentType != null ? ' ingin mengganti ikatan jadi' : ' ingin menjadi'),
          ]),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '$title '),
            TextSpan(text: r.type.jp, style: ZFont.jp(size: 16, color: c, letterSpacing: 0)),
          ]),
          textAlign: TextAlign.center,
          style: ZFont.display(size: 18),
        ),
        if (toRole.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('kamu jadi $toRole-nya',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        if (r.currentType != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Sekarang: ${r.currentType!.label} · poin & level tetap dibawa',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ),
        if (r.message != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: AppColors.backgroundDark, borderRadius: BorderRadius.circular(12)),
            child: Text('"${r.message}"',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: Color(0x1FFFFFFF)),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Tolak', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet, shape: const StadiumBorder()),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Text('Terima', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Kedaluwarsa dalam ${r.daysLeft} hari', style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
      ],
    );
  }
}

class _OutgoingSheet extends ConsumerStatefulWidget {
  const _OutgoingSheet();

  @override
  ConsumerState<_OutgoingSheet> createState() => _OutgoingSheetState();
}

class _OutgoingSheetState extends ConsumerState<_OutgoingSheet> {
  final Set<String> _busy = {};

  Future<void> _cancel(AffinityRequest r) async {
    setState(() => _busy.add(r.id));
    try {
      await ref.read(affinityRepositoryProvider).cancel(r.id);
      refreshAffinity(ref, uid: ref.read(authUserProvider).valueOrNull?.uid);
      if (mounted) showAppToast(context, 'Permintaan dibatalkan');
    } catch (e) {
      if (mounted) showAppToast(context, errorMessage(e, 'Gagal membatalkan'), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(affinityOutgoingProvider);
    final list = async.valueOrNull ?? const <AffinityRequest>[];
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Text('Permintaan terkirim', style: ZFont.display(size: 17)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text('Maksimal 3 yang menunggu jawaban sekaligus',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ),
          if (async.isLoading && list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet)),
            )
          else if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Belum ada permintaan yang menunggu',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final r = list[i];
                  final role = affinityRoleLabel(r.fromRole);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        ProfileAvatar(url: r.avatarUrl, seed: r.toUid, label: r.displayName, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
                              Text(
                                '${r.type.label}${role.isNotEmpty ? ' · kamu $role' : ''} · ${r.daysLeft} hari lagi',
                                style: TextStyle(color: r.type.color, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _busy.contains(r.id) ? null : () => _cancel(r),
                          child: const Text('Batalkan', style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
