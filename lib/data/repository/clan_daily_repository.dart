import 'package:dio/dio.dart';

import 'authed_function.dart';

/// Status absen harian clan untuk user yang login. Semua angka dari server.
class ClanDailyState {
  const ClanDailyState({
    required this.member,
    this.joinedToday = false,
    this.checkedIn = false,
    this.streak = 1,
    this.rewardToday = 0,
    this.maxDays = 7,
    this.base = 5,
    this.step = 5,
    this.bonus = 10,
    this.bonusMinMembers = 3,
    this.eligibleMembers = 0,
    this.checkedMembers = 0,
    this.neededMembers = 0,
    this.bonusClaimed = false,
    this.bonusReady = false,
  });

  final bool member;
  final bool joinedToday;
  final bool checkedIn;

  /// Hari ke berapa (streak hari ini, atau yang akan didapat kalau absen).
  final int streak;
  final int rewardToday;
  final int maxDays;
  final int base;
  final int step;
  final int bonus;
  final int bonusMinMembers;
  final int eligibleMembers;
  final int checkedMembers;
  final int neededMembers;
  final bool bonusClaimed;
  final bool bonusReady;

  int rewardForDay(int day) => base + ((day.clamp(1, maxDays)) - 1) * step;

  factory ClanDailyState.fromJson(Map<String, dynamic> j) {
    int i(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    return ClanDailyState(
      member: j['member'] == true,
      joinedToday: j['joined_today'] == true,
      checkedIn: j['checked_in'] == true,
      streak: i('streak', 1),
      rewardToday: i('reward_today', 0),
      maxDays: i('max_days', 7),
      base: i('base', 5),
      step: i('step', 5),
      bonus: i('bonus', 10),
      bonusMinMembers: i('bonus_min_members', 3),
      eligibleMembers: i('eligible_members', 0),
      checkedMembers: i('checked_members', 0),
      neededMembers: i('needed_members', 0),
      bonusClaimed: j['bonus_claimed'] == true,
      bonusReady: j['bonus_ready'] == true,
    );
  }
}

class ClanDailyResult {
  const ClanDailyResult(this.state, this.amount);
  final ClanDailyState state;

  /// ZCoin yang baru didapat.
  final int amount;
}

/// Edge Function `clan-daily`. UID diambil server dari Firebase ID Token.
class ClanDailyRepository {
  ClanDailyRepository(this._dio);

  final Dio _dio;

  static const String _fn = 'clan-daily';

  Future<Map<String, dynamic>> _call(String action) async {
    final d = await callAuthedFunction(_dio, _fn, {'action': action});
    if (d is! Map) throw Exception('Server tidak merespons');
    return Map<String, dynamic>.from(d);
  }

  ClanDailyState _state(Map<String, dynamic> d) {
    final s = d['state'];
    return ClanDailyState.fromJson(s is Map ? Map<String, dynamic>.from(s) : const {});
  }

  Future<ClanDailyState> state() async => _state(await _call('state'));

  Future<ClanDailyResult> checkIn() async {
    final d = await _call('checkin');
    final r = d['result'];
    final amount = r is Map ? (r['reward'] as num?)?.toInt() ?? 0 : 0;
    return ClanDailyResult(_state(d), amount);
  }

  Future<ClanDailyResult> claimBonus() async {
    final d = await _call('bonus');
    final r = d['result'];
    final amount = r is Map ? (r['bonus'] as num?)?.toInt() ?? 0 : 0;
    return ClanDailyResult(_state(d), amount);
  }
}
