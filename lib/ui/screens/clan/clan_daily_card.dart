import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/clan_daily_repository.dart';
import '../../../providers.dart';

const Color _gold = Color(0xFFF5B301);
const Color _green = Color(0xFF22C55E);

/// Kartu "Absen Harian" di halaman clan (hanya untuk anggota clan itu).
/// Semua angka (streak, ZCoin, bonus) dihitung server; kartu cuma menampilkan.
class ClanDailyCard extends ConsumerStatefulWidget {
  const ClanDailyCard({super.key});

  @override
  ConsumerState<ClanDailyCard> createState() => _ClanDailyCardState();
}

class _ClanDailyCardState extends ConsumerState<ClanDailyCard> {
  ClanDailyState? _s;
  String? _error;
  bool _busy = false;

  ClanDailyRepository get _repo => ref.read(clanDailyRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.state();
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  String _msg(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    return s.isEmpty || s.length > 140 ? 'Gagal memuat absen harian' : s;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<ClanDailyResult> Function() action, String Function(ClanDailyResult r) ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await action();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _s = r.state);
      _snack(ok(r));
      final uid = ref.read(authUserProvider).valueOrNull?.uid;
      if (uid != null) ref.invalidate(coinBalanceProvider(uid));
    } catch (e) {
      if (!mounted) return;
      _snack(_msg(e));
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    Widget body;
    if (s == null) {
      body = _error != null
          ? Row(
              children: [
                Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                TextButton(onPressed: _load, child: const Text('Coba lagi')),
              ],
            )
          : const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator(color: _gold, strokeWidth: 2.5)),
            );
    } else if (!s.member) {
      return const SizedBox.shrink();
    } else {
      body = _content(s);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2210), AppColors.surfaceCard],
        ),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: body,
    );
  }

  Widget _content(ClanDailyState s) {
    final days = s.maxDays;
    // Hari yang sudah "selesai" di deret: kalau sudah absen termasuk hari ini.
    final done = s.checkedIn ? s.streak.clamp(0, days) : (s.streak - 1).clamp(0, days);
    final todayIndex = s.streak.clamp(1, days); // posisi hari ini di deret 1..7

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_available_rounded, color: _gold, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Absen Harian',
              style: TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '🔥 Streak ${s.checkedIn ? s.streak : s.streak - 1}',
                style: const TextStyle(color: _gold, fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var d = 1; d <= days; d++)
              Expanded(
                child: _DayDot(
                  day: d,
                  amount: s.rewardForDay(d),
                  done: d <= done,
                  today: d == todayIndex && !s.checkedIn,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (s.joinedToday)
          const Text(
            'Kamu baru gabung clan hari ini. Absen bisa mulai besok.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          )
        else
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: s.checkedIn ? Colors.white.withValues(alpha: 0.08) : _gold,
                foregroundColor: s.checkedIn ? AppColors.textSecondary : const Color(0xFF241A00),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                disabledForegroundColor: AppColors.textSecondary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: s.checkedIn || _busy
                  ? null
                  : () => _run(
                        _repo.checkIn,
                        (r) => '+${r.amount} ZCoin! Streak hari ke-${r.state.streak}',
                      ),
              child: _busy && !s.checkedIn
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      s.checkedIn ? 'Sudah absen hari ini ✓' : 'Absen  +${s.rewardToday} ZCoin',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
            ),
          ),
        const SizedBox(height: 14),
        _bonus(s),
      ],
    );
  }

  Widget _bonus(ClanDailyState s) {
    if (s.eligibleMembers < s.bonusMinMembers) {
      return Text(
        'Bonus bareng +${s.bonus} ZCoin aktif kalau clan punya minimal ${s.bonusMinMembers} anggota.',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      );
    }
    final need = s.neededMembers <= 0 ? 1 : s.neededMembers;
    final progress = (s.checkedMembers / need).clamp(0.0, 1.0);
    final reached = s.checkedMembers >= need;

    Widget? action;
    if (s.bonusClaimed) {
      action = const Text('Bonus diklaim ✓', style: TextStyle(color: _green, fontSize: 12.5, fontWeight: FontWeight.w700));
    } else if (s.bonusReady) {
      action = SizedBox(
        height: 32,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: const StadiumBorder(),
          ),
          onPressed: _busy ? null : () => _run(_repo.claimBonus, (r) => 'Bonus bareng +${r.amount} ZCoin!'),
          child: Text('Klaim +${s.bonus}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.groups_rounded, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                reached
                    ? 'Bonus bareng terbuka! ${s.checkedMembers} anggota sudah absen'
                    : 'Bonus bareng: ${s.checkedMembers}/$need anggota absen',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ),
            if (action != null) action,
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              color: reached ? _green : _gold,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
        if (!s.checkedIn && !reached) ...[
          const SizedBox(height: 6),
          Text(
            'Kalau ≥50% anggota absen hari ini, yang absen dapat +${s.bonus} ZCoin.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day, required this.amount, required this.done, required this.today});

  final int day;
  final int amount;
  final bool done;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final color = done ? _gold : (today ? _gold.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.12));
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? _gold : Colors.transparent,
            border: Border.all(color: color, width: today ? 2 : 1.5),
            boxShadow: today ? [BoxShadow(color: _gold.withValues(alpha: 0.35), blurRadius: 10)] : null,
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF241A00))
              : Text(
                  '$amount',
                  style: TextStyle(
                    color: today ? _gold : AppColors.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          today ? 'Hari ini' : 'H$day',
          style: TextStyle(
            color: today ? _gold : AppColors.textMuted,
            fontSize: 10,
            fontWeight: today ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
