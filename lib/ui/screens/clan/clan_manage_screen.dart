import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../../data/repository/clan_repository.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';
import 'clan_widgets.dart';

String _thousands(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Kelola Clan (port ManageClanScreen.kt). Officer ke atas: tab Request
/// (terima/tolak). Leader: ditambah tab Pengaturan (nama, tag, kuota member).
/// Ubah role dan kick dilakukan dari daftar member di halaman clan.
///
/// Belum dipindah: ganti foto clan (butuh image picker + upload).
class ClanManageScreen extends ConsumerStatefulWidget {
  const ClanManageScreen({super.key, required this.clanId, required this.myRole});

  final String clanId;
  final String myRole;

  @override
  ConsumerState<ClanManageScreen> createState() => _ClanManageScreenState();
}

class _ClanManageScreenState extends ConsumerState<ClanManageScreen> {
  int _tab = 0; // 0 = Request, 1 = Pengaturan (leader saja)
  String? _busyId;

  bool get _isLeader => widget.myRole == ClanRoles.leader;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _refreshClan() {
    ref.invalidate(clanDetailProvider(widget.clanId));
    ref.invalidate(allClansProvider);
  }

  Future<void> _respond(PendingJoinRequestDisplay r, bool approve) async {
    setState(() => _busyId = r.requestId);
    try {
      await ref.read(clanRepositoryProvider).respondJoinRequest(r.requestId, approve);
      ref.invalidate(clanPendingRequestsProvider(widget.clanId));
      if (approve) {
        _refreshClan(); // ada member baru
        _toast('${r.username} diterima');
      } else {
        _toast('Request ${r.username} ditolak');
      }
    } on ClanException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(clanPendingRequestsProvider(widget.clanId));
    final clan = ref.watch(clanDetailProvider(widget.clanId)).valueOrNull?.clan;
    final tab = _isLeader ? _tab : 0;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        title: const Text('Kelola Clan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _Tabs(
              selected: tab,
              showSettings: _isLeader,
              requestCount: pending.valueOrNull?.length,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          Expanded(
            child: tab == 0
                ? _RequestsTab(
                    pending: pending,
                    busyId: _busyId,
                    onRetry: () => ref.invalidate(clanPendingRequestsProvider(widget.clanId)),
                    onApprove: (r) => _respond(r, true),
                    onReject: (r) => _respond(r, false),
                  )
                : clan == null
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accentViolet,
                          strokeWidth: 3,
                        ),
                      )
                    : _SettingsTab(
                        key: ValueKey(clan.id),
                        clan: clan,
                        onChanged: _refreshClan,
                      ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.showSettings,
    required this.requestCount,
    required this.onChanged,
  });

  final int selected;
  final bool showSettings;
  final int? requestCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = [
      requestCount == null ? 'Request' : 'Request ($requestCount)',
      if (showSettings) 'Pengaturan',
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: clanSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: clanBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: i == selected
                        ? const LinearGradient(
                            colors: [AppColors.accentViolet, Color(0xFFB06CF0)],
                          )
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == selected ? Colors.white : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ request

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.pending,
    required this.busyId,
    required this.onRetry,
    required this.onApprove,
    required this.onReject,
  });

  final AsyncValue<List<PendingJoinRequestDisplay>> pending;
  final String? busyId;
  final VoidCallback onRetry;
  final ValueChanged<PendingJoinRequestDisplay> onApprove;
  final ValueChanged<PendingJoinRequestDisplay> onReject;

  @override
  Widget build(BuildContext context) {
    return pending.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              e is ClanException ? e.message : 'Gagal ambil request join',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Text(
              'Belum ada yang minta gabung clan ini.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = list[i];
            final busy = busyId == r.requestId;
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: clanSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: clanBorder),
              ),
              child: Row(
                children: [
                  UserAvatar(username: r.username, url: r.avatarUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else ...[
                    _RoundAction(
                      icon: Icons.close_rounded,
                      color: const Color(0xFFFF8A98),
                      tooltip: 'Tolak',
                      onTap: () => onReject(r),
                    ),
                    const SizedBox(width: 6),
                    _RoundAction(
                      icon: Icons.check_rounded,
                      color: AppColors.successGreen,
                      tooltip: 'Terima',
                      onTap: () => onApprove(r),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.14),
        shape: CircleBorder(side: BorderSide(color: color.withValues(alpha: 0.4))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, color: color, size: 22)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- pengaturan

class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab({super.key, required this.clan, required this.onChanged});

  final Clan clan;
  final VoidCallback onChanged;

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> {
  late final TextEditingController _name = TextEditingController(text: widget.clan.name);
  late final TextEditingController _tag = TextEditingController(text: widget.clan.tag);
  bool _saving = false;
  String? _feedback;
  bool _feedbackError = false;

  int _packs = 1;
  bool _buying = false;
  String? _slotsFeedback;
  bool _slotsError = false;

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final clan = widget.clan;
    final name = _name.text.trim();
    final tag = _tag.text.trim();
    final newName = name.isNotEmpty && name != clan.name ? name : null;
    final newTag = tag.isNotEmpty && tag != clan.tag ? tag : null;
    if (newName == null && newTag == null) {
      setState(() {
        _feedback = 'Tidak ada perubahan';
        _feedbackError = false;
      });
      return;
    }
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      await ref.read(clanRepositoryProvider).updateClanSettings(clan.id, name: newName, tag: newTag);
      widget.onChanged();
      if (mounted) {
        setState(() {
          _feedback = 'Settingan clan berhasil disimpan';
          _feedbackError = false;
        });
      }
    } on ClanException catch (e) {
      if (mounted) {
        setState(() {
          _feedback = e.message;
          _feedbackError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _buy() async {
    final clan = widget.clan;
    setState(() {
      _buying = true;
      _slotsFeedback = null;
    });
    try {
      await ref.read(clanRepositoryProvider).buyMemberSlots(clan.id, _packs);
      widget.onChanged();
      if (mounted) {
        setState(() {
          _slotsFeedback =
              'Kuota member bertambah ${_packs * ClanSlotShop.slotsPerPack}';
          _slotsError = false;
          _packs = 1;
        });
      }
    } on ClanException catch (e) {
      if (mounted) {
        setState(() {
          _slotsFeedback = e.message;
          _slotsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: clanSurface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: clanBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentViolet),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final clan = widget.clan;
    final maxPacks = ClanSlotShop.maxPacksFor(clan.memberLimit);
    final packs = _packs > maxPacks && maxPacks > 0 ? maxPacks : _packs;
    final cost = packs * ClanSlotShop.pricePerPack;
    final slots = packs * ClanSlotShop.slotsPerPack;
    final canAfford = clan.treasuryBalance >= cost;
    final maxed = maxPacks == 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Center(child: ClanAvatar(tag: clan.tag, url: clan.photoUrl, size: 84)),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          enabled: !_saving,
          style: const TextStyle(color: Colors.white),
          cursorColor: AppColors.accentViolet,
          decoration: _decoration('Nama Clan'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tag,
          enabled: !_saving,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            LengthLimitingTextInputFormatter(3),
            TextInputFormatter.withFunction(
              (old, v) => v.copyWith(text: v.text.toUpperCase()),
            ),
          ],
          style: const TextStyle(color: Colors.white),
          cursorColor: AppColors.accentViolet,
          decoration: _decoration('Tag (3 huruf)'),
        ),
        if (_feedback != null) ...[
          const SizedBox(height: 10),
          Text(
            _feedback!,
            style: TextStyle(
              color: _feedbackError ? const Color(0xFFFF8A98) : AppColors.accentVioletLight,
              fontSize: 12.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        ClanGradientButton(
          text: 'Simpan',
          icon: Icons.save_rounded,
          loading: _saving,
          onTap: _save,
        ),
        const SizedBox(height: 24),
        // Kartu Kuota Member
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: clanSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: clanBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.groups_rounded, size: 18, color: AppColors.accentVioletLight),
                  SizedBox(width: 8),
                  Text(
                    'Kuota Member',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Kuota sekarang ${clan.memberCount}/${clan.memberLimit} (maks ${ClanSlotShop.maxMemberLimit})',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.diamond_rounded, size: 13, color: clanGemBlue),
                  const SizedBox(width: 4),
                  Text(
                    'Saldo donasi clan: ${_thousands(clan.treasuryBalance)} ZCoin',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${ClanSlotShop.slotsPerPack} kuota = ${_thousands(ClanSlotShop.pricePerPack)} ZCoin dari saldo donasi. Level clan tidak berkurang.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 14),
              if (maxed)
                const Text(
                  'Kuota sudah mencapai batas maksimal.',
                  style: TextStyle(color: AppColors.accentVioletLight, fontSize: 12.5),
                )
              else ...[
                Row(
                  children: [
                    _Stepper(
                      icon: Icons.remove_rounded,
                      onTap: packs > 1 && !_buying ? () => setState(() => _packs = packs - 1) : null,
                    ),
                    Expanded(
                      child: Text(
                        '$packs paket (+$slots kuota)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _Stepper(
                      icon: Icons.add_rounded,
                      onTap: packs < maxPacks && !_buying ? () => setState(() => _packs = packs + 1) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClanGradientButton(
                  text: canAfford
                      ? 'Beli +$slots kuota (${_thousands(cost)} ZCoin)'
                      : 'Saldo donasi belum cukup',
                  icon: Icons.shopping_cart_rounded,
                  loading: _buying,
                  onTap: canAfford ? _buy : null,
                ),
              ],
              if (_slotsFeedback != null) ...[
                const SizedBox(height: 10),
                Text(
                  _slotsFeedback!,
                  style: TextStyle(
                    color: _slotsError ? const Color(0xFFFF8A98) : AppColors.accentVioletLight,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Material(
        color: const Color(0x14FFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }
}
