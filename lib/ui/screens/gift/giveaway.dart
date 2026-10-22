import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/gift_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart' show openPremium;

const Color _gold = Color(0xFFF5B73B);
const Color _goldDeep = Color(0xFFE0892B);

// Warna dialog Buat Giveaway (mengikuti referensi).
const Color _cardBg = Color(0xFF161C28);
const Color _pillBg = Color(0xFF232A38);
const Color _sumBg = Color(0xFF0F141D);

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
    var blocked = false;
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
    } else if (!mine && g.claimedFromCreator) {
      subtitle = 'Kamu sudah pernah klaim dari dia';
      button = 'Klaim';
      blocked = true;
    } else if (!mine && g.myClaimLeft != null && g.myClaimLeft! < days) {
      subtitle = g.myClaimLeft! <= 0
          ? 'Jatah klaim 30 hari kamu sudah habis'
          : 'Sisa jatah klaim kamu ${g.myClaimLeft} hari';
      button = 'Klaim';
      blocked = true;
    } else {
      subtitle = '${g.claimed}/${g.slots} diklaim · ${_countdown(g.expiresAt)}';
      button = mine ? 'Punyamu' : 'Klaim';
      onTap = mine || _claiming ? null : _claim;
    }

    final gradient = active && g != null && !g.claimedByMe && !blocked
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
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => const _CreateGiveawaySheet(),
    transitionBuilder: (_, anim, __, child) {
      final a = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
      );
    },
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
        if (!_ok(_days, _slots)) {
          _days = 1;
          _slots = 1;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is GiftException ? e.message : 'Gagal memuat kuota';
      });
    }
  }

  static const List<int> _dayPresets = [1, 3, 7, 14, 30];
  static const List<int> _slotPresets = [5, 10, 20, 30, 50];

  /// Biaya giveaway dalam hari, termasuk pajak (dibayar pemberi).
  double _cost(int d, int s) => d * s * (100 + (_status?.giveawayTaxPct ?? 0)) / 100;

  bool _ok(int d, int s) => _cost(d, s) <= (_status?.availableDays ?? 0);

  static String _fmtDays(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

  int get _maxSlots => _status?.giveawayMaxSlots ?? 1;

  Future<void> _create() async {
    if (_sending || !_ok(_days, _slots)) return;
    FocusScope.of(context).unfocus();
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

  void _setSlots(int n) {
    final v = n.clamp(1, _maxSlots).toInt();
    if (v == _slots) return;
    setState(() => _slots = v);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _cardBg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: const BorderSide(color: Color(0x0FFFFFFF)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  _CrownIcon(size: 30),
                  SizedBox(width: 12),
                  Text(
                    'Buat Giveaway',
                    style: TextStyle(color: AppColors.textWhite, fontSize: 25, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator(color: _gold)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _content(),
                      ),
              ),
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

    final avail = s.availableDays;
    final dayOptions = [
      for (final d in _dayPresets)
        if (d <= s.maxDaysPerGift) d,
    ];
    final slotOptions = [
      for (final n in _slotPresets)
        if (n <= s.giveawayMaxSlots) n,
    ];
    final total = _days * _slots;
    final taxPct = s.isPermanent ? 0 : s.giveawayTaxPct;
    final tax = total * taxPct / 100;
    final cost = total + tax;
    final enough = _ok(_days, _slots);

    // Sisa Premium pemberi setelah giveaway dibuat (khusus non-permanen).
    double? remainAfter;
    final exp = s.expiresAt;
    if (!s.isPermanent && exp != null) {
      final left = exp.difference(DateTime.now()).inMinutes / 1440;
      remainAfter = left - cost;
    }

    return [
      _ValuePicker(
        label: 'Durasi per hadiah',
        unit: 'hari',
        value: _days,
        max: s.maxDaysPerGift,
        presets: dayOptions,
        enabled: !_sending,
        isAllowed: (v) => _ok(v, 1),
        onChanged: (v) => setState(() => _days = v),
      ),
      const SizedBox(height: 12),
      _ValuePicker(
        label: 'Jumlah hadiah',
        unit: 'orang',
        value: _slots,
        max: s.giveawayMaxSlots,
        presets: slotOptions,
        enabled: !_sending,
        isAllowed: (v) => _ok(_days, v),
        onChanged: _setSlots,
      ),
      const SizedBox(height: 20),
      _label('Isi pesan'),
      const SizedBox(height: 12),
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
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0x1FFFFFFF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _gold, width: 1.2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0x14FFFFFF)),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: _sumBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'RINGKASAN',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _sumRow('Penerima', '$_days hari × $_slots orang', _gold),
            const Divider(color: Color(0x14FFFFFF), height: 20),
            if (taxPct > 0) ...[
              _sumRow('Hadiah', '$total hari', AppColors.textWhite),
              _sumRow('Pajak $taxPct%', '+${_fmtDays(tax)} hari', _gold),
            ],
            _sumRow(
              s.isPermanent ? 'Total hadiah' : 'Total Biaya',
              '${_fmtDays(cost)} hari',
              s.isPermanent ? AppColors.textWhite : AppColors.errorRed,
            ),
            if (remainAfter != null)
              _sumRow(
                'Sisa Premium-mu',
                remainAfter > 0 ? '${remainAfter.floor()} hari' : 'Tidak cukup',
                remainAfter > 0 ? AppColors.textSecondary : AppColors.errorRed,
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Siapa cepat dia dapat. Slot yang tidak diklaim dalam 24 jam dikembalikan ke kamu, beserta pajaknya. '
        'Tiap orang cuma bisa klaim sekali dari kamu, dan maksimal 30 hari dari semua giveaway.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: const TextStyle(color: AppColors.errorRed, fontSize: 13)),
      ],
      const SizedBox(height: 18),
      SizedBox(
        height: 54,
        child: FilledButton(
          onPressed: !enough || _sending ? null : _create,
          style: FilledButton.styleFrom(
            backgroundColor: _goldDeep,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF3A3F49),
            disabledForegroundColor: const Color(0xFF9AA0AC),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: _sending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  avail < 1
                      ? 'Sisa Premium tidak cukup'
                      : (enough ? 'Buat Giveaway' : 'Kurangi durasi / jumlah'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
        ),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: _sending ? null : () => Navigator.pop(context),
        style: TextButton.styleFrom(foregroundColor: const Color(0xFF5AB4F5)),
        child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    ];
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700, fontSize: 15),
      );

  Widget _sumRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                value,
                key: ValueKey(value),
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ],
        ),
      );
}

/// Ikon mahkota emas (judul dialog Buat Giveaway).
class _CrownIcon extends StatelessWidget {
  const _CrownIcon({this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 0.78), painter: _CrownPainter());
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final body = Path()
      ..moveTo(w * 0.06, h * 0.30)
      ..lineTo(w * 0.30, h * 0.55)
      ..lineTo(w * 0.50, h * 0.12)
      ..lineTo(w * 0.70, h * 0.55)
      ..lineTo(w * 0.94, h * 0.30)
      ..lineTo(w * 0.84, h * 0.80)
      ..lineTo(w * 0.16, h * 0.80)
      ..close();
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFD25A), _goldDeep],
      ).createShader(Offset.zero & s);
    canvas.drawPath(body, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.16, h * 0.86, w * 0.68, h * 0.14), Radius.circular(h * 0.05)),
      Paint()..color = _goldDeep,
    );
    final dot = Paint()..color = const Color(0xFFFFD25A);
    for (final x in [0.06, 0.50, 0.94]) {
      canvas.drawCircle(Offset(w * x, x == 0.50 ? h * 0.10 : h * 0.28), w * 0.065, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pemilih angka ringkas: angka besar dengan tombol − / +, slider untuk geser
/// cepat, dan beberapa chip pintasan. Nilai yang tidak terjangkau sisa Premium
/// (isAllowed = false) dibuat redup dan slider berhenti di batas terjangkau.
class _ValuePicker extends StatelessWidget {
  const _ValuePicker({
    required this.label,
    required this.unit,
    required this.value,
    required this.max,
    required this.presets,
    required this.isAllowed,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String unit;
  final int value;
  final int max;
  final List<int> presets;
  final bool Function(int) isAllowed;
  final ValueChanged<int> onChanged;
  final bool enabled;

  int get _maxAllowed {
    for (var v = max; v >= 1; v--) {
      if (isAllowed(v)) return v;
    }
    return 1;
  }

  void _set(int v) {
    final c = v.clamp(1, max).toInt();
    if (c == value || !isAllowed(c)) return;
    HapticFeedback.selectionClick();
    onChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final cap = _maxAllowed;
    final canMinus = enabled && value > 1;
    final canPlus = enabled && value < max && isAllowed(value + 1);
    final over = !isAllowed(value);

    Widget roundBtn(IconData icon, bool on, VoidCallback tap) => Material(
          color: on ? _pillBg : _pillBg.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: on ? tap : null,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 20, color: on ? AppColors.textWhite : AppColors.textMuted),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _sumBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: over ? AppColors.errorRed.withValues(alpha: 0.5) : const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('maks $max',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              roundBtn(Icons.remove_rounded, canMinus, () => _set(value - 1)),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: c),
                      ),
                      child: Text(
                        '$value',
                        key: ValueKey(value),
                        style: TextStyle(
                          color: over ? AppColors.errorRed : _gold,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(unit,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              roundBtn(Icons.add_rounded, canPlus, () => _set(value + 1)),
            ],
          ),
          if (max > 1)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: _gold,
                inactiveTrackColor: _pillBg,
                thumbColor: _gold,
                overlayColor: _gold.withValues(alpha: 0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                showValueIndicator: ShowValueIndicator.never,
                tickMarkShape: SliderTickMarkShape.noTickMark,
              ),
              child: Slider(
                min: 1,
                max: max.toDouble(),
                divisions: max - 1,
                value: value.clamp(1, max).toDouble(),
                onChanged: enabled
                    ? (v) {
                        final n = v.round().clamp(1, cap).toInt();
                        if (n != value) {
                          HapticFeedback.selectionClick();
                          onChanged(n);
                        }
                      }
                    : null,
              ),
            ),
          if (presets.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < presets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _PresetChip(
                      label: '${presets[i]}',
                      selected: value == presets[i],
                      enabled: enabled && isAllowed(presets[i]),
                      onTap: () => _set(presets[i]),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, required this.enabled, required this.onTap});

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _gold : _pillBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF1A1300) : const Color(0xFFD5D9E0),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
