import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/gift_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart' show openPremium;

const Color _gold = Color(0xFFF5B73B);
const Color _goldDeep = Color(0xFFE0892B);

// =============================================================== store

/// Cache status giveaway (id -> state) untuk kartu di chat global.
class GiveawayStore extends Notifier<Map<int, GiveawayState>> {
  final Map<int, DateTime> _fetchedAt = {};
  final Set<int> _inflight = {};

  @override
  Map<int, GiveawayState> build() {
    // "Diklaim"/"Punyamu" tergantung akun: reset cache tiap ganti akun.
    ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid));
    _fetchedAt.clear();
    _inflight.clear();
    return const {};
  }

  /// Ambil status untuk [ids] yang belum ada / masih open dan sudah > 20 detik.
  Future<void> ensure(Iterable<int> ids) async {
    final now = DateTime.now();
    final need = <int>[];
    for (final id in ids) {
      if (_inflight.contains(id)) continue;
      final cur = state[id];
      final at = _fetchedAt[id];
      final stale = at == null || now.difference(at) > const Duration(seconds: 20);
      if (cur == null || (cur.isOpen && stale)) need.add(id);
    }
    if (need.isEmpty) return;
    _inflight.addAll(need);
    try {
      final list = await ref.read(giftRepositoryProvider).giveawayStates(need);
      final next = {...state};
      for (final g in list) {
        next[g.id] = g;
        _fetchedAt[g.id] = DateTime.now();
      }
      state = next;
    } catch (_) {
      // best-effort; dicoba lagi saat kartu dibangun ulang
    } finally {
      _inflight.removeAll(need);
    }
  }

  Future<void> refresh(int id) async {
    _fetchedAt.remove(id);
    final cur = state[id];
    if (cur != null) {
      // paksa ambil ulang walaupun statusnya sudah tidak open
      final next = {...state}..remove(id);
      state = next;
    }
    await ensure([id]);
  }

  /// Return jumlah hari yang didapat. Melempar [GiftException] kalau gagal.
  Future<int> claim(int id) async {
    try {
      final days = await ref.read(giftRepositoryProvider).claimGiveaway(id);
      final uid = ref.read(authUserProvider).valueOrNull?.uid;
      if (uid != null) {
        ref.invalidate(premiumStatusProvider(uid));
        ref.invalidate(premiumProvider(uid));
      }
      return days;
    } finally {
      unawaited(refresh(id));
    }
  }
}

final giveawayStoreProvider =
    NotifierProvider<GiveawayStore, Map<int, GiveawayState>>(GiveawayStore.new);

String _countdown(DateTime? t) {
  if (t == null) return '';
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'berakhir';
  if (d.inHours >= 1) return '${d.inHours}j lagi';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes}m lagi';
}

// =============================================================== kartu

/// Kartu giveaway di bubble chat global (tombol Klaim).
class GiveawayCard extends ConsumerStatefulWidget {
  const GiveawayCard({super.key, required this.giveawayId, required this.days});

  final int giveawayId;
  final int days;

  @override
  ConsumerState<GiveawayCard> createState() => _GiveawayCardState();
}

class _GiveawayCardState extends ConsumerState<GiveawayCard> {
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(giveawayStoreProvider.notifier).ensure([widget.giveawayId]);
    });
  }

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final days = await ref.read(giveawayStoreProvider.notifier).claim(widget.giveawayId);
      messenger.showSnackBar(SnackBar(content: Text('🎉 Kamu dapat Premium $days hari!')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is GiftException ? e.message : 'Gagal klaim, coba lagi')),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(giveawayStoreProvider.select((m) => m[widget.giveawayId]));
    final days = g?.days ?? widget.days;
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid;
    final mine = g != null && g.creatorUid == myUid;
    final active = g?.isOpen ?? true;

    String subtitle;
    String button;
    VoidCallback? onTap;
    if (g == null) {
      subtitle = 'Memuat...';
      button = '...';
    } else if (g.claimedByMe) {
      subtitle = 'Kamu sudah klaim';
      button = 'Diklaim';
    } else if (g.status == 'expired') {
      subtitle = 'Giveaway sudah berakhir';
      button = 'Berakhir';
    } else if (!g.isOpen) {
      subtitle = 'Slot sudah habis';
      button = 'Habis';
    } else {
      subtitle = '${g.claimed}/${g.slots} diklaim · ${_countdown(g.expiresAt)}';
      button = mine ? 'Punyamu' : 'Klaim';
      onTap = mine || _claiming ? null : _claim;
    }

    final gradient = active && g != null && !g.claimedByMe
        ? const LinearGradient(colors: [Color(0xFF8A5A12), _goldDeep, _gold])
        : const LinearGradient(colors: [Color(0xFF6B6F78), Color(0xFFA3A7AF), Color(0xFF7D8189)]);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: gradient,
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.white, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$days Hari Premium',
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: onTap != null ? Colors.white : const Color(0x33FFFFFF),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: _claiming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _goldDeep),
                      )
                    : Text(
                        button,
                        style: TextStyle(
                          color: onTap != null ? _goldDeep : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
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

// =============================================================== buat

Future<void> showCreateGiveawaySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _CreateGiveawaySheet(),
  );
}

class _CreateGiveawaySheet extends ConsumerStatefulWidget {
  const _CreateGiveawaySheet();

  @override
  ConsumerState<_CreateGiveawaySheet> createState() => _CreateGiveawaySheetState();
}

class _CreateGiveawaySheetState extends ConsumerState<_CreateGiveawaySheet> {
  final TextEditingController _note = TextEditingController();
  GiftStatus? _status;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  int _days = 1;
  int _slots = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await ref.read(giftRepositoryProvider).status();
      if (!mounted) return;
      setState(() {
        _status = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is GiftException ? e.message : 'Gagal memuat kuota';
      });
    }
  }

  bool _ok(int d, int s) => d * s <= (_status?.availableDays ?? 0);

  Future<void> _create() async {
    if (_sending || !_ok(_days, _slots)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(giftRepositoryProvider).createGiveaway(
            days: _days,
            slots: _slots,
            message: _note.text,
          );
      final uid = ref.read(authUserProvider).valueOrNull?.uid;
      if (uid != null) {
        ref.invalidate(premiumStatusProvider(uid));
        ref.invalidate(premiumProvider(uid));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('👑 Giveaway $_days hari × $_slots dibuat!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is GiftException ? e.message : 'Giveaway gagal dibuat';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.workspace_premium, color: _gold, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'Buat Giveaway',
                    style: TextStyle(color: AppColors.textWhite, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: CircularProgressIndicator(color: _gold)),
                )
              else
                ..._content(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content() {
    final s = _status;
    if (s == null) {
      return [
        Text(_error ?? 'Gagal memuat', style: const TextStyle(color: AppColors.textSecondary)),
        TextButton(onPressed: _load, child: const Text('Coba lagi')),
      ];
    }
    if (!s.isPremium) {
      return [
        const Text('Giveaway khusus member Premium.', style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            openPremium(context);
          },
          style: FilledButton.styleFrom(backgroundColor: _goldDeep, shape: const StadiumBorder()),
          child: const Text('Lihat Premium'),
        ),
      ];
    }
    if (!s.canGift) {
      return [
        const Text(
          'Giveaway hanya untuk yang pernah membeli Premium. Premium hasil gift tidak bisa dibagikan lagi.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
      ];
    }
    if (s.openGiveawayId != null) {
      return [
        const Text(
          'Giveaway kamu sebelumnya masih berjalan. Tunggu sampai slotnya habis atau berakhir (24 jam).',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
      ];
    }

    final avail = s.availableDays;
    if (!_ok(_days, _slots)) {
      // Pilihan saat ini melebihi kuota -> turunkan otomatis.
      _slots = 1;
      if (!_ok(_days, 1)) _days = 1;
    }
    final total = _days * _slots;

    return [
      const Text('Durasi per hadiah', style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        children: [
          for (var d = 1; d <= s.maxDaysPerGift; d++)
            _Pill(
              label: '${d}h',
              selected: _days == d,
              enabled: _ok(d, 1) && !_sending,
              onTap: () => setState(() {
                _days = d;
                if (!_ok(_days, _slots)) _slots = 1;
              }),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          const Text('Jumlah hadiah', style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('$_slots hadiah', style: const TextStyle(color: _gold, fontWeight: FontWeight.w700)),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        children: [
          for (var n = 1; n <= s.giveawayMaxSlots; n++)
            _Pill(
              label: '$n',
              selected: _slots == n,
              enabled: _ok(_days, n) && !_sending,
              onTap: () => setState(() => _slots = n),
            ),
        ],
      ),
      const SizedBox(height: 18),
      const Text('Isi pesan', style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      TextField(
        controller: _note,
        maxLength: 150,
        enabled: !_sending,
        style: const TextStyle(color: AppColors.textWhite),
        decoration: InputDecoration(
          hintText: 'Tulis pesan untuk penonton...',
          hintStyle: const TextStyle(color: AppColors.textMuted),
          counterStyle: const TextStyle(color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.backgroundDark,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('RINGKASAN',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            _sumRow('Penerima', '$_days hari × $_slots orang', _gold),
            const Divider(color: Color(0x14FFFFFF), height: 18),
            _sumRow(
              s.isPermanent ? 'Total hadiah' : 'Dipotong dari Premium-mu',
              '$total hari',
              s.isPermanent ? AppColors.textWhite : AppColors.errorRed,
            ),
            _sumRow('Sisa kuota', '${avail - total < 0 ? 0 : avail - total} hari', AppColors.textSecondary),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Siapa cepat dia dapat. Slot yang tidak diklaim dalam 24 jam dikembalikan ke kamu.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35),
      ),
      if (avail < 1) ...[
        const SizedBox(height: 8),
        Text(
          s.monthUsed >= s.monthMax
              ? 'Batas bulan ini tercapai.'
              : 'Kuota habis untuk sementara. Bisa lagi setelah 3 hari dari gift terakhir.',
          style: const TextStyle(color: _gold, fontSize: 12),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: AppColors.errorRed, fontSize: 13)),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: avail < 1 || _sending ? null : _create,
          style: FilledButton.styleFrom(
            backgroundColor: _goldDeep,
            disabledBackgroundColor: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _sending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Buat Giveaway', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ),
      TextButton(
        onPressed: _sending ? null : () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
    ];
  }

  Widget _sumRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.enabled, required this.onTap});

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 62,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _gold : AppColors.backgroundDark,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : AppColors.textWhite,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
