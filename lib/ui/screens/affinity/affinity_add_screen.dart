import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/affinity_models.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';
import '../../components/app_toast.dart';
import '../../glass/glass.dart';
import '../../redesign/z_kit.dart';
import '../profile/profile_screen.dart' show ProfileAvatar;
import 'affinity_fx.dart';
import 'affinity_providers.dart';

/// Kirim permintaan afinitas: pilih teman (kalau belum), pilih jenis, peran
/// (Kin / Senpai·Kouhai), pesan opsional. Teman harus menyetujui.
class AffinityAddScreen extends ConsumerStatefulWidget {
  const AffinityAddScreen({super.key, this.presetUid, this.presetName, this.presetAvatar, this.presetType});

  final String? presetUid;
  final String? presetName;
  final String? presetAvatar;
  final AffinityType? presetType;

  @override
  ConsumerState<AffinityAddScreen> createState() => _AffinityAddScreenState();
}

class _Target {
  const _Target(this.uid, this.name, this.avatar, this.number);
  final String uid;
  final String name;
  final String? avatar;
  final int? number;
}

class _AffinityAddScreenState extends ConsumerState<AffinityAddScreen> {
  _Target? _target;
  AffinityType? _type;
  String? _role;
  final _msg = TextEditingController();
  final _search = TextEditingController();
  bool _sending = false;

  List<FriendDisplay>? _friends;
  String? _friendsError;

  @override
  void initState() {
    super.initState();
    final p = widget.presetUid;
    if (p != null && p.isNotEmpty) _target = _Target(p, widget.presetName ?? 'Teman', widget.presetAvatar, null);
    _type = widget.presetType;
    if (_type != null && _type!.roles.isNotEmpty) _role = _type!.roles.first;
    if (_target == null) _loadFriends();
  }

  @override
  void dispose() {
    _msg.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _me => ref.read(authUserProvider).valueOrNull?.uid ?? '';

  Future<void> _loadFriends() async {
    setState(() => _friendsError = null);
    try {
      final lists = await ref.read(friendRepositoryProvider).getLists(_me);
      if (mounted) setState(() => _friends = lists.friends);
    } catch (e) {
      if (mounted) setState(() => _friendsError = errorMessage(e, 'Gagal memuat daftar teman'));
    }
  }

  Future<void> _send() async {
    final t = _target;
    final type = _type;
    if (t == null || type == null || _sending) return;
    if (type.roles.isNotEmpty && _role == null) {
      showAppToast(context, 'Pilih peranmu dulu', kind: ToastKind.warning);
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(affinityRepositoryProvider).request(
            target: t.uid,
            type: type,
            role: type.roles.isEmpty ? null : _role,
            message: _msg.text,
          );
      HapticFeedback.mediumImpact();
      refreshAffinity(ref, uid: _me, otherUid: t.uid);
      if (!mounted) return;
      showAppToast(context, 'Permintaan terkirim ke ${t.name}', kind: ToastKind.success, icon: Icons.send_rounded);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppToast(context, errorMessage(e, 'Gagal mengirim permintaan'), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final myList = ref.watch(affinityListProvider(me)).valueOrNull;
    final t = _target;
    final current = t == null ? null : myList?.withUser(t.uid);

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Kembali',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textWhite),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(current == null ? 'Tambah Afinitas' : 'Ganti Afinitas', style: ZFont.display(size: 19)),
                        Text(
                          t == null ? 'Pilih teman dulu' : 'Pilih jenis ikatan',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: t == null ? _friendPicker() : _form(t, myList, current)),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ pilih teman

  Widget _friendPicker() {
    final all = _friends;
    if (_friendsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_friendsError!, style: const TextStyle(color: AppColors.textSecondary)),
            TextButton(onPressed: _loadFriends, child: const Text('Coba lagi')),
          ],
        ),
      );
    }
    if (all == null) {
      return const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet)),
      );
    }
    if (all.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Belum punya teman. Afinitas cuma bisa dibuat dengan teman.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all.where((f) => f.username.toLowerCase().contains(q) || '${f.userNumber ?? ''}'.contains(q)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Cari teman',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceDark,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final f = list[i];
              return AffinityRise(
                index: i.clamp(0, 8),
                child: ZPress(
                  onTap: () => setState(() => _target = _Target(f.firebaseUid, f.username, f.avatarUrl, f.userNumber)),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x12FFFFFF)),
                    ),
                    child: Row(
                      children: [
                        ProfileAvatar(url: f.avatarUrl, seed: f.firebaseUid, label: f.username, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
                              if (f.userNumber != null)
                                Text('ID #${f.userNumber}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- formulir

  Widget _form(_Target t, AffinityList? myList, AffinityItem? current) {
    final type = _type;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottom),
      children: [
        // Teman yang dipilih
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: Row(
            children: [
              ProfileAvatar(url: t.avatar, seed: t.uid, label: t.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
                    Text(
                      current == null ? 'Teman' : 'Sekarang: ${current.type.label}',
                      style: TextStyle(color: current?.type.color ?? AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (widget.presetUid == null)
                TextButton(
                  onPressed: () {
                    setState(() => _target = null);
                    if (_friends == null) _loadFriends();
                  },
                  child: const Text('Ganti', style: TextStyle(color: AppColors.accentVioletLight, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Grid jenis
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.82,
          children: [
            for (final tp in AffinityType.values)
              _TypeTile(
                type: tp,
                used: (myList?.usedOf(tp) ?? 0) - (current?.type == tp ? 1 : 0),
                max: myList?.slotsOf(tp) ?? tp.slots,
                selected: tp == type,
                same: current?.type == tp && tp.roles.isEmpty,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _type = tp;
                    _role = tp.roles.isEmpty ? null : (_role != null && tp.roles.contains(_role) ? _role : tp.roles.first);
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (type != null) ...[
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey(type),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: type.color.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  AffinitySeal(type: type, size: 34, delay: const Duration(milliseconds: 60)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${type.label} · ${type.jp}',
                            style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(
                          [type.description, if (type.bonusHint != null) type.bonusHint!].join(' · '),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (type.roles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final r in type.roles) ...[
                  if (r != type.roles.first) const SizedBox(width: 8),
                  Expanded(
                    child: ZPress(
                      onTap: () => setState(() => _role = r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _role == r ? type.color.withValues(alpha: 0.14) : AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _role == r ? type.color : const Color(0x12FFFFFF)),
                        ),
                        child: Text(
                          'Aku ${affinityRoleLabel(r)}',
                          style: TextStyle(
                            color: _role == r ? AppColors.textWhite : AppColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _msg,
            maxLength: 120,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Pesan singkat (opsional)',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              counterStyle: const TextStyle(color: AppColors.textMuted, fontSize: 10),
              filled: true,
              fillColor: AppColors.surfaceDark,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${t.name} harus menerima dulu · kedaluwarsa dalam 7 hari',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentViolet,
                shape: const StadiumBorder(),
              ),
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Kirim permintaan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Pilih salah satu jenis di atas',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.used,
    required this.max,
    required this.selected,
    required this.same,
    required this.onTap,
  });

  final AffinityType type;
  final int used;
  final int max;
  final bool selected;

  /// Sudah jenis ini dengan teman tersebut (tanpa peran yang bisa ditukar).
  final bool same;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final full = used >= max;
    final disabled = full || same;
    return Opacity(
      opacity: disabled ? 0.35 : 1,
      child: ZPress(
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? type.color.withValues(alpha: 0.10) : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? type.color : Colors.transparent, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: AffinitySeal(type: type, size: 38, stamp: false),
              ),
              const SizedBox(height: 6),
              Text(
                type == AffinityType.senpai ? 'SENPAI' : type.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textWhite, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
              ),
              Text(
                same ? 'sudah' : '${used.clamp(0, max)}/$max',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
