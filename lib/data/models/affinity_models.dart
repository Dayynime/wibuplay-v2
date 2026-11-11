import 'package:flutter/material.dart';

/// Jenis afinitas. Nama `key` sama dengan kolom `type` di server.
enum AffinityType {
  soulmate('soulmate', 'Soulmate', '運命', '運', Color(0xFFE4344A), 1, 'Pasangan, takdir'),
  crush('crush', 'Crush', '片想い', '恋', Color(0xFFFF6B9A), 1, 'Masih PDKT, bisa naik jadi Soulmate'),
  partner('partner', 'Partner', '相棒', '棒', Color(0xFFE8B04A), 1, 'Partner andalan nomor satu'),
  twin('twin', 'Twin', '双子', '双', Color(0xFFB9C2CF), 1, 'Kembar, satu jiwa'),
  nakama('nakama', 'Nakama', '仲間', '仲', Color(0xFF5B8DEF), 5, 'Satu kru, satu tujuan'),
  kin('kin', 'Kin', '家族', '家', Color(0xFF36B5A8), 5, 'Keluarga di Zenime'),
  senpai('senpai', 'Senpai · Kouhai', '先輩・後輩', '先', Color(0xFFE8A0B0), 5, 'Senior dan junior'),
  rival('rival', 'Rival', '宿敵', '敵', Color(0xFF9277E0), 5, 'Saingan abadi');

  const AffinityType(this.key, this.label, this.jp, this.kanji, this.color, this.slots, this.description);

  final String key;
  final String label;
  final String jp;
  final String kanji;
  final Color color;

  /// Slot bawaan (server tetap yang menentukan, lihat [AffinityList.slots]).
  final int slots;
  final String description;

  /// Jenis 1 slot (tampil di bagian atas halaman).
  bool get single => slots == 1;

  /// Peran yang bisa dipilih pengirim (kosong = tanpa peran).
  List<String> get roles => switch (this) {
        AffinityType.kin => const ['kakak', 'adik'],
        AffinityType.senpai => const ['senpai', 'kouhai'],
        _ => const [],
      };

  /// Bonus x1.5 dari sumber poin tertentu.
  String? get bonusHint => switch (this) {
        AffinityType.nakama => 'Poin nobar x1.5',
        AffinityType.rival => 'Poin catur x1.5',
        AffinityType.senpai => 'Poin chat x1.5',
        _ => null,
      };

  static AffinityType? fromKey(String? k) {
    for (final t in values) {
      if (t.key == k) return t;
    }
    return null;
  }
}

String affinityRoleLabel(String? role) => switch (role) {
      'kakak' => 'Kakak',
      'adik' => 'Adik',
      'senpai' => 'Senpai',
      'kouhai' => 'Kouhai',
      _ => '',
    };

/// Tahap level afinitas (Lv 1..5).
class AffinityLevels {
  AffinityLevels._();

  static const names = ['Deai', 'Kizuna', 'Shinrai', 'Kyoumei', 'Eien'];
  static const jp = ['出会い', '絆', '信頼', '共鳴', '永遠'];
  static const short = ['出', '絆', '信', '共', '永'];
  static const defaultThresholds = [0, 500, 2000, 6000, 15000];

  static String name(int level) => names[(level - 1).clamp(0, 4)];
  static String jpName(int level) => jp[(level - 1).clamp(0, 4)];

  /// Progres 0..1 di dalam level sekarang.
  static double progress(int points, int level, List<int> t) {
    if (level >= t.length) return 1;
    final lo = t[(level - 1).clamp(0, t.length - 1)];
    final hi = t[level.clamp(0, t.length - 1)];
    if (hi <= lo) return 1;
    return ((points - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble();
  }

  /// Progres total 0..1 (Lv1 kosong .. Lv5 penuh).
  static double overall(int points, int level, List<int> t) =>
      (((level - 1) + (level >= 5 ? 1.0 : progress(points, level, t))) / 5).clamp(0.0, 1.0).toDouble();
}

int _int(Object? v, [int d = 0]) => (v as num?)?.toInt() ?? d;
String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

List<int> _intList(Object? v) =>
    v is List ? v.map((e) => (e as num?)?.toInt() ?? 0).toList() : AffinityLevels.defaultThresholds;

/// Satu ikatan dilihat dari sisi pemilik halaman.
class AffinityItem {
  const AffinityItem({
    required this.id,
    required this.type,
    required this.otherUid,
    this.username,
    this.avatarUrl,
    this.userNumber,
    this.myRole,
    this.otherRole,
    this.points = 0,
    this.level = 1,
    this.since,
  });

  final String id;
  final AffinityType type;
  final String otherUid;
  final String? username;
  final String? avatarUrl;
  final int? userNumber;
  final String? myRole;
  final String? otherRole;
  final int points;
  final int level;
  final DateTime? since;

  String get displayName => username ?? 'Pengguna Zenime';

  int get days => since == null ? 0 : DateTime.now().difference(since!).inDays;

  static AffinityItem? fromJson(Map<String, dynamic> j) {
    final t = AffinityType.fromKey(j['type']?.toString());
    final id = _str(j['id']);
    final other = _str(j['other_uid']);
    if (t == null || id == null || other == null) return null;
    return AffinityItem(
      id: id,
      type: t,
      otherUid: other,
      username: _str(j['username']),
      avatarUrl: _str(j['avatar_url']),
      userNumber: (j['user_number'] as num?)?.toInt(),
      myRole: _str(j['my_role']),
      otherRole: _str(j['other_role']),
      points: _int(j['points']),
      level: _int(j['level'], 1),
      since: DateTime.tryParse(j['since']?.toString() ?? '')?.toLocal(),
    );
  }
}

class AffinityList {
  const AffinityList({
    this.items = const [],
    this.incoming = 0,
    this.outgoing = 0,
    this.slots = const {},
    this.levels = AffinityLevels.defaultThresholds,
  });

  final List<AffinityItem> items;
  final int incoming;
  final int outgoing;
  final Map<String, int> slots;
  final List<int> levels;

  int slotsOf(AffinityType t) => slots[t.key] ?? t.slots;
  List<AffinityItem> ofType(AffinityType t) => items.where((e) => e.type == t).toList();
  int usedOf(AffinityType t) => items.where((e) => e.type == t).length;

  AffinityItem? withUser(String uid) {
    for (final e in items) {
      if (e.otherUid == uid) return e;
    }
    return null;
  }

  factory AffinityList.fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    final slots = <String, int>{};
    final s = j['slots'];
    if (s is Map) {
      s.forEach((k, v) => slots[k.toString()] = (v as num?)?.toInt() ?? 0);
    }
    return AffinityList(
      items: raw is List
          ? raw.whereType<Map>().map((e) => AffinityItem.fromJson(Map<String, dynamic>.from(e))).whereType<AffinityItem>().toList()
          : const [],
      incoming: _int(j['incoming']),
      outgoing: _int(j['outgoing']),
      slots: slots,
      levels: _intList(j['levels']),
    );
  }
}

/// Permintaan afinitas (masuk / keluar). [username] dkk = pihak lain.
class AffinityRequest {
  const AffinityRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.type,
    this.fromRole,
    this.toRole,
    this.message,
    this.username,
    this.avatarUrl,
    this.userNumber,
    this.currentType,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String fromUid;
  final String toUid;
  final AffinityType type;
  final String? fromRole;
  final String? toRole;
  final String? message;
  final String? username;
  final String? avatarUrl;
  final int? userNumber;

  /// Jenis afinitas yang sudah ada di antara mereka (permintaan ganti jenis).
  final AffinityType? currentType;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  String get displayName => username ?? 'Pengguna Zenime';

  int get daysLeft {
    final e = expiresAt;
    if (e == null) return 0;
    final d = e.difference(DateTime.now());
    return d.isNegative ? 0 : (d.inHours / 24).ceil();
  }

  static AffinityRequest? fromJson(Map<String, dynamic> j) {
    final t = AffinityType.fromKey(j['type']?.toString());
    final id = _str(j['id']);
    if (t == null || id == null) return null;
    return AffinityRequest(
      id: id,
      fromUid: _str(j['from_uid']) ?? '',
      toUid: _str(j['to_uid']) ?? '',
      type: t,
      fromRole: _str(j['from_role']),
      toRole: _str(j['to_role']),
      message: _str(j['message']),
      username: _str(j['username']),
      avatarUrl: _str(j['avatar_url']),
      userNumber: (j['user_number'] as num?)?.toInt(),
      currentType: AffinityType.fromKey(j['current_type']?.toString()),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal(),
      expiresAt: DateTime.tryParse(j['expires_at']?.toString() ?? '')?.toLocal(),
    );
  }
}

class AffinityPerson {
  const AffinityPerson({required this.uid, this.username, this.avatarUrl, this.userNumber, this.role});

  final String uid;
  final String? username;
  final String? avatarUrl;
  final int? userNumber;
  final String? role;

  String get displayName => username ?? 'Pengguna Zenime';

  factory AffinityPerson.fromJson(Object? v, String? role) {
    final j = v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
    return AffinityPerson(
      uid: _str(j['uid']) ?? '',
      username: _str(j['username']),
      avatarUrl: _str(j['avatar_url']),
      userNumber: (j['user_number'] as num?)?.toInt(),
      role: role,
    );
  }
}

class AffinityMoment {
  const AffinityMoment({required this.kind, required this.value, this.createdAt});

  final String kind;
  final String value;
  final DateTime? createdAt;

  /// Kalimat yang ditampilkan.
  String text(AffinityType type) => switch (kind) {
        'start' => 'Ikatan ${type.label} dimulai',
        'level' => 'Naik ke Lv $value · ${AffinityLevels.name(int.tryParse(value) ?? 1)}',
        'days' => '$value hari bersama',
        'chess' => '$value kali main catur bareng',
        'nobar' => '$value kali nobar bareng',
        'type' => 'Berganti jadi ${AffinityType.fromKey(value.split(':').first)?.label ?? 'jenis baru'}',
        _ => kind,
      };
}

class AffinityDetail {
  const AffinityDetail({
    required this.id,
    required this.type,
    required this.a,
    required this.b,
    this.points = 0,
    this.level = 1,
    this.since,
    this.stats = const {},
    this.moments = const [],
    this.levels = AffinityLevels.defaultThresholds,
    this.viewerIn = false,
  });

  final String id;
  final AffinityType type;
  final AffinityPerson a;
  final AffinityPerson b;
  final int points;
  final int level;
  final DateTime? since;
  final Map<String, int> stats;
  final List<AffinityMoment> moments;
  final List<int> levels;
  final bool viewerIn;

  int get days => since == null ? 0 : DateTime.now().difference(since!).inDays;

  /// Urutkan: [me] di kiri kalau termasuk.
  (AffinityPerson, AffinityPerson) ordered(String me) => b.uid == me ? (b, a) : (a, b);

  static AffinityDetail? fromJson(Map<String, dynamic> j) {
    final t = AffinityType.fromKey(j['type']?.toString());
    final id = _str(j['id']);
    if (t == null || id == null) return null;
    final stats = <String, int>{};
    final s = j['stats'];
    if (s is Map) s.forEach((k, v) => stats[k.toString()] = (v as num?)?.toInt() ?? 0);
    final m = j['moments'];
    return AffinityDetail(
      id: id,
      type: t,
      a: AffinityPerson.fromJson(j['user_a'], _str(j['role_a'])),
      b: AffinityPerson.fromJson(j['user_b'], _str(j['role_b'])),
      points: _int(j['points']),
      level: _int(j['level'], 1),
      since: DateTime.tryParse(j['since']?.toString() ?? '')?.toLocal(),
      stats: stats,
      moments: m is List
          ? m.whereType<Map>().map((e) {
              final x = Map<String, dynamic>.from(e);
              return AffinityMoment(
                kind: x['kind']?.toString() ?? '',
                value: x['value']?.toString() ?? '',
                createdAt: DateTime.tryParse(x['created_at']?.toString() ?? '')?.toLocal(),
              );
            }).toList()
          : const [],
      levels: _intList(j['levels']),
      viewerIn: j['viewer_in'] == true,
    );
  }
}
