import '../../core/supabase_config.dart';

// Model Pohon ZCoin (Edge Function `tree-game`). Semua angka dihitung server.

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
    this.look,
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

  /// Dekorasi yang dipasang. null = respons ini tidak membawa data dekorasi
  /// (mis. hasil panen) -> pakai yang terakhir diketahui.
  final TreeLook? look;

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
      look: j['equipped'] is Map ? TreeLook.fromJson(Map<String, dynamic>.from(j['equipped'] as Map)) : null,
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

// ==================================================================== dekorasi

String? _s(dynamic v) => v is String && v.isNotEmpty ? v : null;

/// Slot dekorasi.
class TreeSlot {
  TreeSlot._();
  static const String tree = 'tree';
  static const String fruit = 'fruit';
  static const String treeDeco = 'tree_deco';
  static const String ground = 'ground';
  static const String pet = 'pet';
  static const String effect = 'effect';
  static const int maxGround = 2;
}

/// Dekorasi yang dipasang di pohon.
class TreeLook {
  const TreeLook({
    this.tree,
    this.fruit,
    this.treeDeco,
    this.ground = const [],
    this.pet,
    this.effect,
    this.petAsset,
  });

  final String? tree;
  final String? fruit;
  final String? treeDeco;
  final List<String> ground;
  final String? pet;
  final String? effect;

  /// Animasi Lottie pet yang dipasang. null = pet digambar pakai kode.
  final PetAsset? petAsset;

  factory TreeLook.fromJson(Map<String, dynamic> j) {
    final g = j['ground'];
    final pa = j['pet_asset'];
    return TreeLook(
      petAsset: pa is Map ? PetAsset.tryParse(pa['file'], pa['place'], pa['scale'], pa['dx'], pa['dy']) : null,
      tree: _s(j['tree']),
      fruit: _s(j['fruit']),
      treeDeco: _s(j['tree_deco']),
      ground: g is List ? g.whereType<String>().toList() : const [],
      pet: _s(j['pet']),
      effect: _s(j['effect']),
    );
  }

  bool isEquipped(String id, String slot) {
    switch (slot) {
      case TreeSlot.tree:
        return tree == id;
      case TreeSlot.fruit:
        return fruit == id;
      case TreeSlot.treeDeco:
        return treeDeco == id;
      case TreeSlot.ground:
        return ground.contains(id);
      case TreeSlot.pet:
        return pet == id;
      case TreeSlot.effect:
        return effect == id;
    }
    return false;
  }

  /// Versi dengan [id] terpasang (dipakai buat preview di toko).
  TreeLook withItem(String id, String slot, {PetAsset? asset}) {
    if (slot == TreeSlot.pet) {
      return TreeLook(
        tree: tree,
        fruit: fruit,
        treeDeco: treeDeco,
        ground: ground,
        pet: id,
        effect: effect,
        petAsset: asset,
      );
    }
    switch (slot) {
      case TreeSlot.tree:
        return _copy(tree: id);
      case TreeSlot.fruit:
        return _copy(fruit: id);
      case TreeSlot.treeDeco:
        return _copy(treeDeco: id);
      case TreeSlot.pet:
        return _copy(pet: id);
      case TreeSlot.effect:
        return _copy(effect: id);
      case TreeSlot.ground:
        if (ground.contains(id)) return this;
        final g = [...ground, id];
        while (g.length > TreeSlot.maxGround) {
          g.removeAt(0);
        }
        return _copy(ground: g);
    }
    return this;
  }

  TreeLook _copy({
    String? tree,
    String? fruit,
    String? treeDeco,
    List<String>? ground,
    String? pet,
    String? effect,
  }) =>
      TreeLook(
        tree: tree ?? this.tree,
        fruit: fruit ?? this.fruit,
        treeDeco: treeDeco ?? this.treeDeco,
        ground: ground ?? this.ground,
        pet: pet ?? this.pet,
        effect: effect ?? this.effect,
        petAsset: petAsset,
      );
}

class ShopItem {
  const ShopItem({
    required this.id,
    required this.slot,
    required this.name,
    required this.description,
    required this.rarity,
    required this.price,
    required this.premiumOnly,
    required this.availableUntil,
    this.asset,
  });

  final String id;
  final String slot;
  final String name;
  final String description;

  /// common | rare | epic | legendary
  final String rarity;
  final int price;
  final bool premiumOnly;

  /// null = dijual permanen; ada isinya = item terbatas.
  final DateTime? availableUntil;

  bool get limited => availableUntil != null;

  /// Animasi Lottie (khusus pet). null = pakai gambar kode.
  final PetAsset? asset;

  factory ShopItem.fromJson(Map<String, dynamic> j) => ShopItem(
        id: (j['id'] as String?) ?? '',
        slot: (j['slot'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        rarity: (j['rarity'] as String?) ?? 'common',
        price: _i(j['price']),
        premiumOnly: j['premium_only'] == true,
        availableUntil: _d(j['available_until']),
        asset: PetAsset.tryParse(j['asset'], j['asset_place'], j['asset_scale'], j['asset_dx'], j['asset_dy']),
      );
}

class ShopData {
  const ShopData({required this.items, required this.owned, required this.look});

  final List<ShopItem> items;
  final Set<String> owned;
  final TreeLook look;

  factory ShopData.fromJson(Map<String, dynamic> j) {
    final items = j['items'];
    final owned = j['owned'];
    final eq = j['equipped'];
    return ShopData(
      items: items is List
          ? items.whereType<Map>().map((e) => ShopItem.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      owned: owned is List ? owned.whereType<String>().toSet() : <String>{},
      look: eq is Map ? TreeLook.fromJson(Map<String, dynamic>.from(eq)) : const TreeLook(),
    );
  }
}

/// Pohon teman (mode kunjungan).
class TreeVisit {
  const TreeVisit({
    required this.level,
    required this.fruits,
    required this.capacity,
    required this.premium,
    required this.waterReceivedToday,
    required this.waterReceiveLimit,
    required this.wateredByMe,
    required this.look,
  });

  final int level;
  final int fruits;
  final int capacity;
  final bool premium;
  final int waterReceivedToday;
  final int waterReceiveLimit;
  final bool wateredByMe;
  final TreeLook look;

  factory TreeVisit.fromJson(Map<String, dynamic> j) {
    final eq = j['equipped'];
    return TreeVisit(
      level: _i(j['level'], 1),
      fruits: _i(j['fruits']),
      capacity: _i(j['capacity'], 6),
      premium: j['premium'] == true,
      waterReceivedToday: _i(j['water_received_today']),
      waterReceiveLimit: _i(j['water_receive_limit'], 5),
      wateredByMe: j['watered_by_me'] == true,
      look: eq is Map ? TreeLook.fromJson(Map<String, dynamic>.from(eq)) : const TreeLook(),
    );
  }
}

/// Animasi Lottie pet yang disimpan di bucket publik `tree-assets`.
class PetAsset {
  const PetAsset({
    required this.file,
    required this.place,
    required this.scale,
    this.dx = 0,
    this.dy = 0,
  });

  final String file;

  /// ground_left | ground_right | canopy_top | branch_left | branch_right
  final String place;
  final double scale;

  /// Geser posisi (satuan = ukuran kotak animasi). dx + ke kanan, dy + ke bawah.
  final double dx;
  final double dy;

  static final RegExp _fileRe = RegExp(r'^[A-Za-z0-9._-]{1,80}\.json$');

  String get url => '${SupabaseConfig.url}/storage/v1/object/public/tree-assets/$file';

  static PetAsset? tryParse(dynamic file, dynamic place, dynamic scale, [dynamic dx, dynamic dy]) {
    if (file is! String || !_fileRe.hasMatch(file)) return null;
    final s = (scale as num?)?.toDouble() ?? 1.0;
    final x = (dx as num?)?.toDouble() ?? 0.0;
    final y = (dy as num?)?.toDouble() ?? 0.0;
    return PetAsset(
      file: file,
      place: place is String ? place : 'ground_right',
      scale: s.clamp(0.3, 3.0),
      dx: x.clamp(-1.0, 1.0),
      dy: y.clamp(-1.0, 1.0),
    );
  }
}
