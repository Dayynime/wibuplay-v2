import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../../data/models/friend_models.dart';
import '../../../data/repository/clan_access_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../../components/friend_search_field.dart';
import 'clan_screen.dart';
import 'clan_widgets.dart';

/// Pesan error dari Exception server (callAuthedFunction) tanpa prefix.
String _msg(Object e, String fallback) {
  final s = e.toString().replaceFirst('Exception: ', '').trim();
  return s.isEmpty || s.length > 160 ? fallback : s;
}

// ============================================================================
// Pengaturan akses (Kelola Clan > Pengaturan, leader)
// ============================================================================

/// Kartu "Akses Bergabung": pilih mode join + level minimal. Aturannya
/// ditegakkan server (`clan-access`), kartu ini hanya mengirim pilihan.
class ClanJoinSettingsCard extends ConsumerStatefulWidget {
  const ClanJoinSettingsCard({super.key, required this.clan, required this.onChanged});

  final Clan clan;
  final VoidCallback onChanged;

  @override
  ConsumerState<ClanJoinSettingsCard> createState() => _ClanJoinSettingsCardState();
}

class _ClanJoinSettingsCardState extends ConsumerState<ClanJoinSettingsCard> {
  late String _mode = widget.clan.joinMode ?? ClanJoinMode.approval;
  late int _minLevel = widget.clan.minLevel.clamp(1, 500);
  bool _saving = false;
  String? _feedback;
  bool _error = false;

  static const int _maxLevel = 500;

  bool get _dirty =>
      _mode != (widget.clan.joinMode ?? ClanJoinMode.approval) || _minLevel != widget.clan.minLevel;

  // Level minimal tidak berlaku untuk mode undangan/tertutup.
  bool get _levelApplies => _mode == ClanJoinMode.open || _mode == ClanJoinMode.approval;

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      await ref.read(clanAccessRepositoryProvider).updateSettings(
            clanId: widget.clan.id,
            joinMode: _mode,
            minLevel: _minLevel,
          );
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() {
        _feedback = 'Tersimpan: ${ClanJoinMode.label(_mode)}'
            '${_levelApplies && _minLevel > 1 ? ', min. level $_minLevel' : ''}';
        _error = false;
      });
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = _msg(e, 'Gagal menyimpan pengaturan');
        _error = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setLevel(int v) => setState(() => _minLevel = v.clamp(1, _maxLevel));

  @override
  Widget build(BuildContext context) {
    // Pilihan mode dalam kisi 2 x 2 (gaya preview).
    Widget mode(String m) => Expanded(
          child: _ModeOption(
            mode: m,
            selected: _mode == m,
            onTap: _saving ? null : () => setState(() => _mode = m),
          ),
        );
    final modes = ClanJoinMode.all;
    return ClanSectionCard(
      icon: Icons.meeting_room_rounded,
      title: 'Akses Bergabung',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < modes.length; r += 2) ...[
            if (r > 0) const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mode(modes[r]),
                  const SizedBox(width: 8),
                  if (r + 1 < modes.length) mode(modes[r + 1]) else const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: !_levelApplies
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Level minimal',
                          style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Berlaku untuk join & request. Orang yang diundang bebas level.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _StepBtn(icon: Icons.remove_rounded, onTap: _minLevel > 1 && !_saving ? () => _setLevel(_minLevel - 1) : null),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    _minLevel <= 1 ? 'Bebas' : 'Lv $_minLevel',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                            _StepBtn(icon: Icons.add_rounded, onTap: _minLevel < _maxLevel && !_saving ? () => _setLevel(_minLevel + 1) : null),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final v in const [1, 5, 10, 20, 30, 50])
                              ChoiceChip(
                                label: Text(v == 1 ? 'Bebas' : 'Lv $v'),
                                selected: _minLevel == v,
                                onSelected: _saving ? null : (_) => _setLevel(v),
                                labelStyle: TextStyle(
                                  color: _minLevel == v ? Colors.white : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                selectedColor: AppColors.accentViolet,
                                backgroundColor: const Color(0x0FFFFFFF),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 10),
            Text(
              _feedback!,
              style: TextStyle(
                color: _error ? const Color(0xFFFF8A98) : AppColors.accentVioletLight,
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ClanGradientButton(
            text: 'Simpan Akses',
            icon: Icons.check_rounded,
            loading: _saving,
            onTap: _dirty ? _save : null,
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.selected, required this.onTap});

  final String mode;
  final bool selected;
  final VoidCallback? onTap;

  static IconData _icon(String m) {
    switch (m) {
      case ClanJoinMode.open:
        return Icons.lock_open_rounded;
      case ClanJoinMode.invite:
        return Icons.mail_lock_rounded;
      case ClanJoinMode.closed:
        return Icons.lock_rounded;
      default:
        return Icons.how_to_reg_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected ? AppColors.accentViolet.withValues(alpha: 0.12) : AppColors.backgroundDarkSecondary,
            border: Border.all(
              color: selected ? AppColors.accentViolet : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon(mode), size: 16, color: selected ? AppColors.accentVioletLight : AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ClanJoinMode.label(mode),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.accentVioletLight : AppColors.textWhite,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                ClanJoinMode.description(mode),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Material(
        color: AppColors.surfaceVariantDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }
}

// ============================================================================
// Tombol + lembar "Undang Teman" (Kelola Clan > Request, leader & pengurus)
// ============================================================================

class ClanInviteButton extends StatelessWidget {
  const ClanInviteButton({super.key, required this.clan, required this.memberUids});

  final Clan clan;
  final Set<String> memberUids;

  @override
  Widget build(BuildContext context) {
    final closed = clan.joinMode == ClanJoinMode.closed;
    final full = clan.memberCount >= clan.memberLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClanGradientButton(
          text: 'Undang Teman',
          icon: Icons.person_add_rounded,
          onTap: closed || full ? null : () => showClanInviteSheet(context, clan, memberUids),
        ),
        if (closed || full) ...[
          const SizedBox(height: 6),
          Text(
            closed ? 'Clan sedang Tertutup. Ubah mode join untuk mengundang.' : 'Kuota member clan sudah penuh.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

Future<void> showClanInviteSheet(BuildContext context, Clan clan, Set<String> memberUids) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _InviteSheet(clan: clan, memberUids: memberUids),
  );
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.clan, required this.memberUids});

  final Clan clan;
  final Set<String> memberUids;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  List<FriendDisplay>? _friends;
  String? _error;
  String? _sending;
  String _query = '';
  final Set<String> _sent = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _error = 'Kamu harus login dulu');
      return;
    }
    try {
      final lists = await ref.read(friendRepositoryProvider).getLists(uid);
      if (mounted) setState(() => _friends = lists.friends);
    } catch (_) {
      if (mounted) setState(() => _error = 'Daftar teman gagal dimuat');
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _invite(FriendDisplay f) async {
    if (_sending != null) return;
    setState(() => _sending = f.firebaseUid);
    try {
      await ref.read(clanAccessRepositoryProvider).invite(clanId: widget.clan.id, uid: f.firebaseUid);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _sent.add(f.firebaseUid));
    } catch (e) {
      if (mounted) _snack(_msg(e, 'Gagal mengirim undangan'));
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final all = _friends;
    final friends = all == null ? null : filterFriends(all, _query);

    Widget list;
    if (_error != null) {
      list = Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
      );
    } else if (friends == null) {
      list = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
      );
    } else if (all!.isEmpty) {
      list = const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Kamu belum punya teman di Zenime.', style: TextStyle(color: AppColors.textSecondary)),
      );
    } else if (friends.isEmpty) {
      list = const FriendSearchEmpty();
    } else {
      list = ListView.builder(
        shrinkWrap: true,
        itemCount: friends.length,
        itemBuilder: (_, i) {
          final f = friends[i];
          final member = widget.memberUids.contains(f.firebaseUid);
          final sent = _sent.contains(f.firebaseUid);
          final sending = _sending == f.firebaseUid;
          Widget trailing;
          if (member) {
            trailing = const Text('Anggota', style: TextStyle(color: AppColors.textMuted, fontSize: 12));
          } else if (sending) {
            trailing = const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
          } else if (sent) {
            trailing = const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.successGreen, size: 18),
                SizedBox(width: 4),
                Text('Terkirim', style: TextStyle(color: AppColors.successGreen, fontSize: 12)),
              ],
            );
          } else {
            trailing = FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentViolet,
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
              onPressed: () => _invite(f),
              child: const Text('Undang', style: TextStyle(fontWeight: FontWeight.w700)),
            );
          }
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: FriendAvatar(url: f.avatarUrl, seed: f.firebaseUid, label: f.username, size: 40, framed: false),
            title: Text(
              f.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textWhite),
            ),
            trailing: trailing,
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Undang ke ${widget.clan.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Temanmu dapat notifikasi dan tinggal tekan Gabung. Undangan bebas level.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
                const SizedBox(height: 10),
                FriendSearchField(onChanged: (v) => setState(() => _query = v)),
                const SizedBox(height: 8),
                Flexible(child: list),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Undangan masuk (dari notif / push `clan_invite`)
// ============================================================================

/// Dipanggil saat notif `clan_invite` di-tap: tampilkan pilihan Gabung / Tolak.
Future<void> handleClanInviteNotification(WidgetRef ref, Map<String, dynamic> data) async {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  final ctx = nav.context;

  void snack(String text) {
    ScaffoldMessenger.maybeOf(ctx)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  if (data['expired'] == true) {
    snack('Undangan clan ini sudah tidak berlaku');
    return;
  }

  final inviteId = data['invite_id']?.toString() ?? '';
  final clanId = data['clan_id']?.toString() ?? '';
  ClanInvite? invite;
  try {
    // Ambil dari server: sekalian memastikan undangan masih menunggu jawaban.
    final list = await ref.read(clanAccessRepositoryProvider).myInvites();
    invite = list.where((i) => i.inviteId == inviteId).firstOrNull ??
        list.where((i) => i.clanId == clanId).firstOrNull;
  } catch (_) {
    if (inviteId.isNotEmpty) {
      invite = ClanInvite(
        inviteId: inviteId,
        clanId: clanId,
        clanName: data['clan_name']?.toString() ?? 'Clan',
      );
    }
  }
  if (invite == null) {
    snack('Undangan clan ini sudah tidak berlaku');
    return;
  }

  final joinedClanId = await showDialog<String>(
    context: ctx,
    builder: (_) => _InviteDialog(invite: invite!),
  );
  ref.invalidate(unreadNotificationsProvider);
  if (joinedClanId != null && joinedClanId.isNotEmpty) {
    ref.invalidate(myClanMembershipProvider);
    ref.invalidate(allClansProvider);
    ref.invalidate(clanDetailProvider(joinedClanId));
    await nav.push<void>(fadeRoute(ClanScreen(clanId: joinedClanId)));
  }
}

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.invite});

  final ClanInvite invite;

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  bool? _busy; // true = gabung, false = tolak
  String? _error;

  Future<void> _answer(bool accept) async {
    if (_busy != null) return;
    setState(() {
      _busy = accept;
      _error = null;
    });
    try {
      final clanId = await ref.read(clanAccessRepositoryProvider).respond(widget.invite.inviteId, accept: accept);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, accept ? (clanId ?? widget.invite.clanId) : null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = _msg(e, 'Gagal menjawab undangan');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invite;
    return Dialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClanAvatar(tag: inv.clanTag.isEmpty ? '?' : inv.clanTag, url: inv.photoUrl, size: 72),
            const SizedBox(height: 14),
            Text(
              inv.fromName.isEmpty ? 'Kamu diundang ke clan' : '${inv.fromName} mengundangmu ke clan',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              inv.clanName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.warningAmber, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textWhite,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _busy != null ? null : () => _answer(false),
                    child: _busy == false
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Tolak'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentViolet,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _busy != null ? null : () => _answer(true),
                    child: _busy == true
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Gabung', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
            if (_error != null)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
          ],
        ),
      ),
    );
  }
}
