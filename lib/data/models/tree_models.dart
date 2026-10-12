/// Model Pohon ZCoin (Edge Function `tree-game`). Semua angka dihitung server.

int _i(dynamic v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

DateTime? _d(dynamic v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;

class TreeLevelStats {
  const TreeLevelStats({
    required this.intervalSec,
    required this.capacity,
    required this.coinsPerFruit,
  });

  final int intervalSec;
  final int capacity;
  final int coinsPerFruit;

  factory TreeLevelStats.fromJson(Map<String, dynamic> j) => TreeLevelStats(
        intervalSec: _i(j['interval_sec'], 7200),
        capacity: _i(j['capacity'], 6),
        coinsPerFruit: _i(j['coins_per_fruit'], 1),
      );
}

class TreeState {
  const TreeState({
    required this.level,
    required this.maxLevel,
    required this.fruits,
    required this.capacity,
    required this.intervalSec,
    required this.coinsPerFruit,
    required this.nextFruitAt,
    required this.coinsToday,
    required this.dailyCap,
    required this.upgradeCost,
    required this.next,
    required this.premium,
    required this.premiumSpeed,
    required this.waterReceivedToday,
    required this.waterReceiveLimit,
    required this.waterGivenToday,
    required this.waterGiveLimit,
    required this.waterBonusMin,
    required this.totalCoins,
    required this.serverNow,
  });

  final int level;
  final int maxLevel;
  final int fruits;
  final int capacity;
  final int intervalSec;
  final int coinsPerFruit;

  /// null = pohon penuh (pertumbuhan berhenti sampai dipanen).
  final DateTime? nextFruitAt;
  final int coinsToday;
  final int dailyCap;

  /// null = sudah level maksimal.
  final int? upgradeCost;
  final TreeLevelStats? next;
  final bool premium;
  final double premiumSpeed;
  final int waterReceivedToday;
  final int waterReceiveLimit;
  final int waterGivenToday;
  final int waterGiveLimit;
  final int waterBonusMin;
  final int totalCoins;
  final DateTime serverNow;

  bool get isFull => fruits >= capacity;
  bool get isMaxLevel => level >= maxLevel || upgradeCost == null;
  int get coinsLeftToday => (dailyCap - coinsToday).clamp(0, dailyCap);

  factory TreeState.fromJson(Map<String, dynamic> j) {
    final next = j['next'];
    return TreeState(
      level: _i(j['level'], 1),
      maxLevel: _i(j['max_level'], 10),
      fruits: _i(j['fruits']),
      capacity: _i(j['capacity'], 6),
      intervalSec: _i(j['interval_sec'], 7200),
      coinsPerFruit: _i(j['coins_per_fruit'], 1),
      nextFruitAt: _d(j['next_fruit_at']),
      coinsToday: _i(j['coins_today']),
      dailyCap: _i(j['daily_cap'], 50),
      upgradeCost: (j['upgrade_cost'] as num?)?.toInt(),
      next: next is Map ? TreeLevelStats.fromJson(Map<String, dynamic>.from(next)) : null,
      premium: j['premium'] == true,
      premiumSpeed: (j['premium_speed'] as num?)?.toDouble() ?? 1.5,
      waterReceivedToday: _i(j['water_received_today']),
      waterReceiveLimit: _i(j['water_receive_limit'], 5),
      waterGivenToday: _i(j['water_given_today']),
      waterGiveLimit: _i(j['water_give_limit'], 5),
      waterBonusMin: _i(j['water_bonus_min'], 30),
      totalCoins: _i(j['total_coins']),
      serverNow: _d(j['server_now']) ?? DateTime.now().toUtc(),
    );
  }
}

class TreeHarvestResult {
  const TreeHarvestResult({
    required this.harvested,
    required this.coins,
    required this.balance,
    required this.tree,
  });

  final int harvested;
  final int coins;
  final int balance;
  final TreeState tree;
}

class TreeUpgradeResult {
  const TreeUpgradeResult({required this.cost, required this.balance, required this.tree});

  final int cost;
  final int balance;
  final TreeState tree;
}

class TreeWaterStatus {
  const TreeWaterStatus({
    required this.watered,
    required this.givenToday,
    required this.giveLimit,
    required this.bonusMin,
  });

  final Set<String> watered;
  final int givenToday;
  final int giveLimit;
  final int bonusMin;

  int get left => (giveLimit - givenToday).clamp(0, giveLimit);

  factory TreeWaterStatus.fromJson(Map<String, dynamic> j) {
    final w = j['watered'];
    return TreeWaterStatus(
      watered: w is List ? w.whereType<String>().toSet() : <String>{},
      givenToday: _i(j['given_today']),
      giveLimit: _i(j['give_limit'], 5),
      bonusMin: _i(j['bonus_min'], 30),
    );
  }
}

/// "2 jam", "1 jam 40 mnt", "45 mnt".
String formatTreeMinutes(int totalMinutes) {
  final m = totalMinutes < 1 ? 1 : totalMinutes;
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '$r mnt';
  if (r == 0) return '$h jam';
  return '$h jam $r mnt';
}

/// 1.5 -> "1,5x", 2.0 -> "2x".
String formatTreeSpeed(double v) {
  final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')}x';
}
