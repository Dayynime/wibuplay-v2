import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../../data/repository/clan_photo_uploader.dart';
import '../../../data/repository/clan_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/clan_badge_styles.dart';
import '../../components/clan_tag_badge.dart';
import '../../components/game_badges.dart';
import 'clan_access_widgets.dart';
import 'clan_badge_shop_screen.dart';
import 'clan_widgets.dart';
import '../../redesign/z_kit.dart';
import '../../glass/glass.dart';

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

  /// Clan sudah dibubarkan: tutup Kelola Clan dan kasih tahu layar clan lewat
  /// hasil pop (true) supaya ikut menutup diri.
  void _onClanDeleted() {
    ref.invalidate(allClansProvider);
    ref.invalidate(myClanMembershipProvider);
    if (mounted) Navigator.of(context).pop(true);
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
    final detail = ref.watch(clanDetailProvider(widget.clanId)).valueOrNull;
    final clan = detail?.clan;
    final tab = _isLeader ? _tab : 0;

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        title: Text('Kelola Clan', style: ZFont.display(size: 18)),
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
                ? Column(
                    children: [
                      // Undang teman: leader & pengurus (dicek lagi di server).
                      if (clan != null && ClanRoles.canManageClan(widget.myRole))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: ClanInviteButton(
                            clan: clan,
                            memberUids: {for (final m in detail!.members) m.firebaseUid},
                          ),
                        ),
                      Expanded(
                        child: _RequestsTab(
                          pending: pending,
                          busyId: _busyId,
                          onRetry: () => ref.invalidate(clanPendingRequestsProvider(widget.clanId)),
                          onApprove: (r) => _respond(r, true),
                          onReject: (r) => _respond(r, false),
                        ),
                      ),
                    ],
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
                        onDeleted: _onClanDeleted,
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
      requestCount == null ? 'Request' : 'Request · $requestCount',
      if (showSettings) 'Pengaturan',
    ];
    if (labels.length == 1) {
      // Bukan leader: cuma satu tab, tampil sebagai judul kecil.
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(labels.first, style: ZFont.display(size: 16)),
      );
    }
    return ClanSegment(labels: labels, selected: selected, onChanged: onChanged);
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
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final r = list[i];
            final busy = busyId == r.requestId;
            // Satu panel: sudut membulat di baris pertama/terakhir + garis pemisah.
            return Container(
              decoration: BoxDecoration(
                color: clanSurface,
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(18) : Radius.zero,
                  bottom: i == list.length - 1 ? const Radius.circular(18) : Radius.zero,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0) const Divider(height: 1, thickness: 1, indent: 12, endIndent: 12, color: clanBorder),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    child: Row(
                      children: [
                        RepaintBoundary(
                          child: UserAvatar(username: r.username, url: r.avatarUrl, size: 42, frameUid: r.firebaseUid),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            r.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (busy)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        else ...[
                          _RoundAction(
                            icon: Icons.close_rounded,
                            color: const Color(0xFFFF6F91),
                            tooltip: 'Tolak',
                            onTap: () => onReject(r),
                          ),
                          const SizedBox(width: 6),
                          _RoundAction(
                            icon: Icons.check_rounded,
                            color: AppColors.accentTeal,
                            tooltip: 'Terima',
                            filled: true,
                            onTap: () => onApprove(r),
                          ),
                        ],
                      ],
                    ),
                  ),
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
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  /// Terisi penuh (aksi utama "Terima").
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? color : color.withValues(alpha: 0.13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, color: filled ? const Color(0xFF032A22) : color, size: 20),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- pengaturan

class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab({
    super.key,
    required this.clan,
    required this.onChanged,
    required this.onDeleted,
  });

  final Clan clan;
  final VoidCallback onChanged;
  final VoidCallback onDeleted;

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> {
  late final TextEditingController _name = TextEditingController(text: widget.clan.name);
  late final TextEditingController _tag = TextEditingController(text: widget.clan.tag);
  final _picker = ImagePicker();
  bool _uploadingPhoto = false;
  bool _saving = false;
  String? _feedback;
  bool _feedbackError = false;

  int _packs = 1;
  bool _buying = false;
  String? _slotsFeedback;
  bool _slotsError = false;

  bool _deleting = false;
  String? _deleteError;

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    super.dispose();
  }

  /// Pilih foto dari galeri -> upload ke Cloudinary -> simpan photo_url ke clan.
  Future<void> _changePhoto() async {
    if (_uploadingPhoto || _saving) return;
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedback = 'Gagal membuka galeri';
          _feedbackError = true;
        });
      }
      return;
    }
    if (picked == null) return;

    setState(() {
      _uploadingPhoto = true;
      _feedback = null;
    });
    try {
      // pathKey WAJIB unik tiap upload (pakai timestamp). Upload unsigned
      // Cloudinary tidak boleh menimpa public_id yang sudah ada, jadi kalau
      // pathKey-nya cuma clanId, foto kedua dst akan balik ke foto lama.
      final url = await ClanPhotoUploader.uploadClanPhoto(
        picked.path,
        '${widget.clan.id}-${DateTime.now().millisecondsSinceEpoch}',
      );
      await ref.read(clanRepositoryProvider).updateClanSettings(widget.clan.id, photoUrl: url);
      widget.onChanged();
      if (mounted) {
        setState(() {
          _feedback = 'Foto clan berhasil diganti';
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedback = 'Gagal upload foto. Periksa koneksi lalu coba lagi.';
          _feedbackError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
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

  /// Minta leader mengetik tag clan dulu; true = boleh lanjut hapus.
  Future<bool> _confirmDelete() async {
    final clan = widget.clan;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final match = ctrl.text.trim().toUpperCase() == clan.tag.toUpperCase();
          return AlertDialog(
            backgroundColor: AppColors.surfaceDark,
            title: const Text('Bubarkan clan?', style: TextStyle(fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clan "${clan.name}" akan dihapus PERMANEN beserta seluruh member, '
                  'chat, dan saldo donasinya (${_thousands(clan.treasuryBalance)} ZCoin, tidak dikembalikan). '
                  'Aksi ini tidak bisa dibatalkan.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Text(
                  'Ketik ${clan.tag} untuk konfirmasi',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: AppColors.accentViolet,
                  decoration: _decoration('Tag clan'),
                  onChanged: (_) => setD(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
              TextButton(
                onPressed: match ? () => Navigator.pop(ctx, true) : null,
                child: Text(
                  'Bubarkan',
                  style: TextStyle(color: match ? const Color(0xFFFF8A98) : AppColors.textMuted),
                ),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    return ok == true;
  }

  Future<void> _deleteClan() async {
    if (_deleting) return;
    if (!await _confirmDelete()) return;
    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    try {
      await ref.read(clanRepositoryProvider).deleteClan(widget.clan.id, widget.clan.tag);
      if (!mounted) return;
      widget.onDeleted();
      return;
    } on ClanException catch (e) {
      if (mounted) setState(() => _deleteError = e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.backgroundDarkSecondary,
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

    // Urutan kartu: Identitas, Akses Bergabung, Kuota Member, Badge, Zona Bahaya.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        ClanSectionCard(
          icon: Icons.badge_rounded,
          title: 'Identitas Clan',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PhotoButton(
                    tag: clan.tag,
                    url: clan.photoUrl,
                    uploading: _uploadingPhoto,
                    onTap: _changePhoto,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ganti foto clan',
                          style: TextStyle(color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Ketuk lambang untuk pilih dari galeri',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                enabled: !_saving,
                style: const TextStyle(color: Colors.white),
                cursorColor: AppColors.accentViolet,
                decoration: _decoration('Nama Clan'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tag,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(4),
                  TextInputFormatter.withFunction(
                    (old, v) => v.copyWith(text: v.text.toUpperCase()),
                  ),
                ],
                style: const TextStyle(color: Colors.white, letterSpacing: 2),
                cursorColor: AppColors.accentViolet,
                decoration: _decoration('Tag (3-4 huruf)'),
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
              const SizedBox(height: 12),
              ClanGradientButton(
                text: 'Simpan',
                icon: Icons.save_rounded,
                loading: _saving,
                onTap: _save,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Mode join + level minimal
        ClanJoinSettingsCard(clan: clan, onChanged: widget.onChanged),
        const SizedBox(height: 12),
        ClanSectionCard(
          icon: Icons.groups_rounded,
          title: 'Kuota Member',
          color: const Color(0xFFF6BE4F),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Terisi', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                  Text(
                    '${clan.memberCount} / ${clan.memberLimit}',
                    style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: clan.memberLimit <= 0 ? 0 : (clan.memberCount / clan.memberLimit).clamp(0.0, 1.0),
                  minHeight: 8,
                  color: const Color(0xFFF6BE4F),
                  backgroundColor: const Color(0x14FFFFFF),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Batas maksimal ${_thousands(ClanSlotShop.maxMemberLimit)} member',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0x14F6BE4F),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0x38F6BE4F)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Saldo donasi clan', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                    Text(
                      '${_thousands(clan.treasuryBalance)} ZCoin',
                      style: ZFont.display(size: 15, color: const Color(0xFFF6BE4F)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${ClanSlotShop.slotsPerPack} kuota = ${_thousands(ClanSlotShop.pricePerPack)} ZCoin dari saldo donasi. Level clan tidak berkurang.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              if (maxed)
                const Text(
                  'Kuota sudah mencapai batas maksimal.',
                  style: TextStyle(color: AppColors.accentVioletLight, fontSize: 12.5),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundDarkSecondary,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: clanBorder),
                  ),
                  child: Row(
                    children: [
                      _Stepper(
                        icon: Icons.remove_rounded,
                        onTap: packs > 1 && !_buying ? () => setState(() => _packs = packs - 1) : null,
                      ),
                      Expanded(
                        child: Text(
                          '$packs paket (+$slots kuota)',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      _Stepper(
                        icon: Icons.add_rounded,
                        onTap: packs < maxPacks && !_buying ? () => setState(() => _packs = packs + 1) : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ClanGradientButton(
                  text: canAfford
                      ? 'Beli +$slots kuota (${_thousands(cost)} ZCoin)'
                      : 'Saldo donasi belum cukup',
                  icon: Icons.shopping_cart_rounded,
                  gold: true,
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
        const SizedBox(height: 12),
        // Kartu Badge Clan
        _BadgeEntry(clan: clan),
        const SizedBox(height: 12),
        // Zona bahaya: bubarkan clan (khusus leader, dicek lagi di server).
        ClanSectionCard(
          icon: Icons.warning_amber_rounded,
          title: 'Zona Bahaya',
          danger: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bubarkan clan menghapus clan, semua member, chat, dan saldo donasi secara permanen.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.45),
              ),
              if (_deleteError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _deleteError!,
                  style: const TextStyle(color: Color(0xFFFF8A98), fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _deleting ? null : _deleteClan,
                icon: _deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF8A98)),
                      )
                    : const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text('Bubarkan Clan', style: TextStyle(fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF8A98),
                  backgroundColor: const Color(0x1FFF6F91),
                  side: const BorderSide(color: Color(0x59FF6F91)),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Avatar clan yang bisa diketuk buat ganti foto (ada badge kamera + spinner).
class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.tag,
    required this.url,
    required this.uploading,
    required this.onTap,
  });

  final String tag;
  final String? url;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClanAvatar(tag: tag, url: url, size: size),
            if (uploading)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(size * 0.3),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentViolet,
                  border: Border.all(color: AppColors.backgroundDark, width: 2),
                ),
                child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
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
        color: AppColors.surfaceVariantDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(width: 36, height: 36, child: Icon(icon, color: Colors.white, size: 20)),
        ),
      ),
    );
  }
}

/// Kartu "Badge Clan" di Pengaturan: pratinjau badge terpasang + buka toko.
class _BadgeEntry extends StatelessWidget {
  const _BadgeEntry({required this.clan});

  final Clan clan;

  @override
  Widget build(BuildContext context) {
    final style = clanBadgeStyleOrNull(clan.badgeStyle);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push<void>(fadeRoute(ClanBadgeShopScreen(clanId: clan.id))),
      child: ClanSectionCard(
        icon: Icons.workspace_premium_rounded,
        title: 'Badge Clan',
        color: const Color(0xFFF6BE4F),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.backgroundDarkSecondary,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: clanBorder),
              ),
              child: Row(
                children: [
                  ClanTagBadge.known(text: clan.tag, styleId: clan.badgeStyle, height: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      style?.label ?? 'Pelangi (bawaan)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Beli dan pasang badge pakai saldo donasi clan. Ketuk untuk buka toko badge.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
