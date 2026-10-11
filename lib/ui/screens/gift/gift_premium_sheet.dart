import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/gift_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart' show openPremium;

const Color _gold = Color(0xFFF5B73B);
const Color _goldDeep = Color(0xFFE0892B);

/// Buka sheet Gift Premium. [channel]: 'global' atau 'private'.
/// Return baris pesan bubble gift dari server (null kalau batal/gagal).
Future<Map<String, dynamic>?> showGiftPremiumSheet(
  BuildContext context, {
  required String recipientUid,
  required String recipientName,
  required String channel,
}) {
  return showModalBottomSheet<Map<String, dynamic>?>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _GiftSheet(
      recipientUid: recipientUid,
      recipientName: recipientName,
      channel: channel,
    ),
  );
}

String _until(DateTime? t) {
  if (t == null) return '';
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'sebentar lagi';
  if (d.inDays >= 1) {
    final h = d.inHours % 24;
    return h > 0 ? '${d.inDays} hari $h jam' : '${d.inDays} hari';
  }
  if (d.inHours >= 1) return '${d.inHours} jam ${d.inMinutes % 60} menit';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} menit';
}

class _GiftSheet extends ConsumerStatefulWidget {
  const _GiftSheet({required this.recipientUid, required this.recipientName, required this.channel});

  final String recipientUid;
  final String recipientName;
  final String channel;

  @override
  ConsumerState<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends ConsumerState<_GiftSheet> {
  GiftStatus? _status;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  int _days = 1;

  @override
  void initState() {
    super.initState();
    _load();
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
        if (_days > s.availableDays) _days = s.availableDays < 1 ? 1 : s.availableDays;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is GiftException ? e.message : 'Gagal memuat kuota gift';
      });
    }
  }

  Future<void> _send() async {
    final s = _status;
    if (s == null || _sending || _days < 1 || _days > s.availableDays) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final msg = await ref.read(giftRepositoryProvider).send(
            recipientUid: widget.recipientUid,
            days: _days,
            channel: widget.channel,
          );
      // Sisa premium sendiri berubah -> segarkan status premium.
      final uid = ref.read(authUserProvider).valueOrNull?.uid;
      if (uid != null) {
        ref.invalidate(premiumStatusProvider(uid));
        ref.invalidate(premiumProvider(uid));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🎁 Premium $_days hari terkirim ke ${widget.recipientName}')),
      );
      Navigator.pop(context, msg);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is GiftException ? e.message : 'Gift gagal dikirim';
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_gold, _goldDeep]),
                  ),
                  child: const Icon(Icons.card_giftcard, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gift Premium',
                        style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'untuk ${widget.recipientName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: _gold)),
              )
            else
              ..._content(),
          ],
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
        const Text(
          'Gift Premium khusus member Premium.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            openPremium(context);
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet, shape: const StadiumBorder()),
          child: const Text('Lihat Premium'),
        ),
      ];
    }
    if (!s.canGift) {
      return [
        const Text(
          'Gift Premium hanya untuk yang pernah membeli Premium. Premium hasil gift tidak bisa diberikan lagi.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
      ];
    }

    final avail = s.availableDays;
    final monthFull = s.monthUsed >= s.monthMax;
    final windowFull = s.windowUsed >= s.windowMax;

    return [
      const Text('Jumlah hari', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final d in const [1, 2, 3]) ...[
            Expanded(
              child: _DayChip(
                days: d,
                selected: _days == d && d <= avail,
                enabled: d <= avail && !_sending,
                onTap: () => setState(() => _days = d),
              ),
            ),
            if (d != 3) const SizedBox(width: 10),
          ],
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(Icons.timelapse, 'Kuota 3 hari', '${s.windowMax - s.windowUsed < 0 ? 0 : s.windowMax - s.windowUsed} / ${s.windowMax} hari'),
            _infoRow(Icons.calendar_month, 'Bulan ini', '${s.monthUsed} / ${s.monthMax} hari terpakai'),
            if (avail == 0 && monthFull)
              _note('Batas bulan ini tercapai. Reset dalam ${_until(s.monthResetAt)}.')
            else if (avail == 0 && windowFull)
              _note('Kuota habis. Bisa kirim lagi dalam ${_until(s.windowUnlockAt)}.')
            else if (avail == 0)
              _note('Sisa Premium kamu tidak cukup untuk memberi.')
            else if (!s.isPermanent)
              _note('Sisa Premium kamu akan berkurang $_days hari.'),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: const TextStyle(color: AppColors.errorRed, fontSize: 13)),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: avail < 1 || _sending ? null : _send,
          style: FilledButton.styleFrom(
            backgroundColor: _goldDeep,
            disabledBackgroundColor: AppColors.surfaceElevated,
            shape: const StadiumBorder(),
          ),
          icon: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.card_giftcard, size: 18),
          label: Text(
            avail < 1 ? 'Belum bisa kirim' : 'Kirim Premium $_days hari',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ];
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(value, style: const TextStyle(color: AppColors.textWhite, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: const TextStyle(color: _gold, fontSize: 12, height: 1.35)),
      );
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.days, required this.selected, required this.enabled, required this.onTap});

  final int days;
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
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected ? const LinearGradient(colors: [_gold, _goldDeep]) : null,
            color: selected ? null : AppColors.backgroundDark,
            border: Border.all(color: selected ? Colors.transparent : const Color(0x33F5B73B)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$days',
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'hari',
                style: TextStyle(color: selected ? Colors.white : AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isi bubble gift (dipakai di chat global & chat pribadi).
class GiftBubbleCard extends StatelessWidget {
  const GiftBubbleCard({super.key, required this.days, required this.title, this.subtitle});

  final int days;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A2A10), Color(0xFF6B4314)],
        ),
        border: Border.all(color: const Color(0x80F5B73B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_gold, _goldDeep]),
            ),
            child: const Icon(Icons.card_giftcard, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Premium $days hari',
                  style: const TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3)),
                if (subtitle != null)
                  Text(subtitle!, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
