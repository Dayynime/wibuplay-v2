import 'package:flutter/material.dart';

import '../../core/supabase_config.dart';

/// Model Wallpaper Komentar (gacha spin). File disimpan di Supabase Storage
/// VPS sendiri: bucket publik `comment-wallpapers` (sudah disetujui) dan
/// bucket privat `wp-review` (pending, cuma lewat signed URL).

enum WallpaperRarity {
  common,
  rare,
  epic,
  legendary,
  mythic,

  /// Di atas Mythic: tag "Limited" silver mengkilap (chip pakai [RarityChip]).
  limited;

  static WallpaperRarity from(Object? v) =>
      WallpaperRarity.values.firstWhere((e) => e.name == v, orElse: () => WallpaperRarity.common);

  String get label => switch (this) {
        WallpaperRarity.common => 'Common',
        WallpaperRarity.rare => 'Rare',
        WallpaperRarity.epic => 'Epic',
        WallpaperRarity.legendary => 'Legendary',
        WallpaperRarity.mythic => 'Mythic',
        WallpaperRarity.limited => 'Limited',
      };

  Color get color => switch (this) {
        WallpaperRarity.common => const Color(0xFF8B93A1),
        WallpaperRarity.rare => const Color(0xFF3B82F6),
        WallpaperRarity.epic => const Color(0xFFA855F7),
        WallpaperRarity.legendary => const Color(0xFFF59E0B),
        WallpaperRarity.mythic => const Color(0xFFFF2E63),
        WallpaperRarity.limited => const Color(0xFFD7DCE4),
      };

  /// Gradient khusus Mythic & Limited; rarity lain warna polos.
  Gradient? get gradient => switch (this) {
        WallpaperRarity.mythic => const LinearGradient(colors: [Color(0xFFFF2E63), Color(0xFFB026FF)]),
        WallpaperRarity.limited => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8D95A3), Color(0xFFF5F7FA), Color(0xFFB4BCC8), Color(0xFFFFFFFF), Color(0xFF9AA3B1)],
            stops: [0, 0.3, 0.55, 0.75, 1],
          ),
        _ => null,
      };

  /// Rarity silver mengkilap (chip dianimasikan kilau).
  bool get isShiny => this == WallpaperRarity.limited;

  /// Warna teks di atas chip rarity (silver terlalu terang buat teks putih).
  Color get onColor => isShiny ? const Color(0xFF1C2230) : Colors.white;
}

// Nama file selalu uuid buatan server. URL HANYA dirakit dari nama yang lolos
// regex ini, jadi data aneh di database tidak bisa mengarahkan app ke host luar.
final RegExp _fileRe = RegExp(r'^[0-9a-f-]{36}(_p)?\.webp$');

String? wallpaperPublicUrl(Object? fileName) {
  if (fileName is! String || !_fileRe.hasMatch(fileName)) return null;
  return '${SupabaseConfig.url}/storage/v1/object/public/comment-wallpapers/$fileName';
}

/// Signed URL relatif dari Edge Function -> URL lengkap ke Supabase kita sendiri.
String? storageSignedUrl(Object? relative) {
  if (relative is! String || !relative.startsWith('/storage/v1/object/sign/')) return null;
  return '${SupabaseConfig.url}$relative';
}

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;

/// Wallpaper yang dipakai seseorang (untuk latar komentar).
class CommentWallpaper {
  const CommentWallpaper({required this.id, required this.rarity, required this.url});

  final String id;
  final WallpaperRarity rarity;
  final String url;

  static CommentWallpaper? fromJson(Map<String, dynamic> j) {
    final url = wallpaperPublicUrl(j['file_name']);
    final id = j['wallpaper_id'] as String?;
    if (url == null || id == null) return null;
    return CommentWallpaper(id: id, rarity: WallpaperRarity.from(j['rarity']), url: url);
  }
}

class WallpaperItem {
  const WallpaperItem({
    required this.id,
    required this.name,
    required this.rarity,
    required this.url,
    required this.previewUrl,
    this.chancePercent,
    this.eventEndsAt,
    this.eventId,
  });

  final String id;
  final String name;
  final WallpaperRarity rarity;
  final String url;
  final String previewUrl;
  final double? chancePercent;

  /// Diisi kalau wallpaper ini cuma bisa didapat selama event (Limited).
  final DateTime? eventEndsAt;
  final int? eventId;

  static WallpaperItem? fromJson(Map<String, dynamic> j) {
    final url = wallpaperPublicUrl(j['file_name']);
    final prev = wallpaperPublicUrl(j['preview_name']);
    final id = j['id'] as String?;
    if (url == null || prev == null || id == null) return null;
    return WallpaperItem(
      id: id,
      name: (j['name'] as String?) ?? 'Wallpaper',
      rarity: WallpaperRarity.from(j['rarity']),
      url: url,
      previewUrl: prev,
      chancePercent: (j['chance_percent'] as num?)?.toDouble(),
      eventEndsAt: _date(j['event_ends_at']),
      eventId: (j['event_id'] as num?)?.toInt(),
    );
  }
}

List<WallpaperItem> _items(Object? v) => v is List
    ? v
        .whereType<Map>()
        .map((e) => WallpaperItem.fromJson(Map<String, dynamic>.from(e)))
        .whereType<WallpaperItem>()
        .toList()
    : const [];

class WallpaperState {
  const WallpaperState({
    required this.spinCost,
    required this.spin10Cost,
    required this.dupRefundPercent,
    required this.balance,
    required this.pool,
    required this.inventory,
    this.equippedId,
    this.events = const [],
    this.clockOffset = Duration.zero,
  });

  final int spinCost;
  final int spin10Cost;
  final int dupRefundPercent;
  final int balance;
  final List<WallpaperItem> pool;
  final List<WallpaperItem> inventory;
  final String? equippedId;

  /// Event Limited yang sedang berjalan / akan datang (urut jam mulai).
  final List<WallpaperEvent> events;

  /// Jam server - jam HP, supaya hitung mundur event tidak ketipu jam HP.
  final Duration clockOffset;

  DateTime get serverNow => DateTime.now().toUtc().add(clockOffset);

  factory WallpaperState.fromJson(Map<String, dynamic> j) => WallpaperState(
        spinCost: _int(j['spin_cost']),
        spin10Cost: _int(j['spin10_cost'], _int(j['spin_cost']) * 10),
        dupRefundPercent: _int(j['dup_refund_percent']),
        balance: _int(j['balance']),
        pool: _items(j['pool']),
        inventory: _items(j['inventory']),
        equippedId: j['equipped_id'] as String?,
        events: j['events'] is List
            ? (j['events'] as List)
                .whereType<Map>()
                .map((e) => WallpaperEvent.fromJson(Map<String, dynamic>.from(e)))
                .whereType<WallpaperEvent>()
                .toList()
            : const [],
        clockOffset: _date(j['server_now'])?.difference(DateTime.now().toUtc()) ?? Duration.zero,
      );

  WallpaperState copyWith({int? balance, String? Function()? equippedId, List<WallpaperItem>? inventory}) =>
      WallpaperState(
        spinCost: spinCost,
        spin10Cost: spin10Cost,
        dupRefundPercent: dupRefundPercent,
        balance: balance ?? this.balance,
        pool: pool,
        inventory: inventory ?? this.inventory,
        equippedId: equippedId != null ? equippedId() : this.equippedId,
        events: events,
        clockOffset: clockOffset,
      );

  /// Total peluang per rarity (transparansi odds).
  Map<WallpaperRarity, double> get chanceByRarity {
    final out = <WallpaperRarity, double>{};
    for (final w in pool) {
      out[w.rarity] = (out[w.rarity] ?? 0) + (w.chancePercent ?? 0);
    }
    return out;
  }
}

class SpinEntry {
  const SpinEntry({required this.item, required this.duplicate});

  final WallpaperItem item;
  final bool duplicate;

  static SpinEntry? fromJson(Map<String, dynamic> j) {
    final w = j['wallpaper'];
    final item = w is Map ? WallpaperItem.fromJson(Map<String, dynamic>.from(w)) : null;
    if (item == null) return null;
    return SpinEntry(item: item, duplicate: j['duplicate'] == true);
  }
}

/// Hasil spin 1x atau 10x (diacak di server).
class SpinResult {
  const SpinResult({required this.entries, required this.refund, required this.balance});

  final List<SpinEntry> entries;

  /// Total ZCoin yang dikembalikan karena duplikat.
  final int refund;
  final int balance;

  /// Hasil dengan rarity tertinggi (dipakai untuk animasi reel).
  SpinEntry get best => entries.reduce((a, b) => b.item.rarity.index > a.item.rarity.index ? b : a);

  static SpinResult? fromJson(Map<String, dynamic> j) {
    final raw = j['results'];
    final entries = <SpinEntry>[];
    if (raw is List) {
      for (final e in raw.whereType<Map>()) {
        final s = SpinEntry.fromJson(Map<String, dynamic>.from(e));
        if (s != null) entries.add(s);
      }
    } else {
      // respons format lama (1x)
      final s = SpinEntry.fromJson(j);
      if (s != null) entries.add(s);
    }
    if (entries.isEmpty) return null;
    return SpinResult(entries: entries, refund: _int(j['refund']), balance: _int(j['balance']));
  }
}

// ------------------------------------------------------------------ event

/// Event Limited: wallpaper Limited-nya cuma ada di pool Spin selama event.
class WallpaperEvent {
  const WallpaperEvent({
    required this.id,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    this.itemCount = 0,
  });

  final int id;
  final String name;
  final DateTime startsAt;
  final DateTime endsAt;
  final int itemCount;

  bool isRunning(DateTime now) => !now.isBefore(startsAt) && now.isBefore(endsAt);
  bool isUpcoming(DateTime now) => now.isBefore(startsAt);

  static WallpaperEvent? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num?)?.toInt();
    final s = _date(j['starts_at']);
    final e = _date(j['ends_at']);
    if (id == null || s == null || e == null) return null;
    return WallpaperEvent(
      id: id,
      name: (j['name'] as String?) ?? 'Event',
      startsAt: s,
      endsAt: e,
      itemCount: _int(j['item_count']),
    );
  }
}

/// "2h 3j", "3j 05m", "12m 09d", "45d".
String formatEventCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays;
  final h = d.inHours % 24;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  if (days > 0) return '${days}h ${h}j';
  if (d.inHours > 0) return '${d.inHours}j ${two(m)}m';
  if (m > 0) return '${m}m ${two(s)}d';
  return '${s}d';
}

/// Tanggal & jam lokal HP, mis. "31/10 19:00".
String formatEventTime(DateTime utc) {
  final t = utc.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

// ------------------------------------------------------------------ admin

class AdminWallpaper {
  const AdminWallpaper({
    required this.id,
    required this.name,
    required this.rarity,
    required this.weight,
    required this.status,
    required this.isActive,
    required this.uploadedBy,
    this.uploaderName,
    this.previewUrl,
    this.fileUrl,
    this.ownerCount = 0,
    this.width,
    this.height,
    this.frames,
    this.bytes,
  });

  final String id;
  final String name;
  final WallpaperRarity rarity;
  final int weight;
  final String status; // pending | approved | rejected | removed
  final bool isActive;
  final String uploadedBy;
  final String? uploaderName;
  final String? previewUrl;
  final String? fileUrl;
  final int ownerCount;
  final int? width;
  final int? height;
  final int? frames;
  final int? bytes;

  factory AdminWallpaper.fromJson(Map<String, dynamic> j) {
    final status = (j['status'] as String?) ?? 'pending';
    final approved = status == 'approved';
    return AdminWallpaper(
      id: (j['id'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      rarity: WallpaperRarity.from(j['rarity']),
      weight: _int(j['weight'], 100),
      status: status,
      isActive: j['is_active'] == true,
      uploadedBy: (j['uploaded_by'] as String?) ?? '',
      uploaderName: j['uploader_name'] as String?,
      previewUrl: approved
          ? wallpaperPublicUrl(j['preview_name'])
          : storageSignedUrl(j['review_preview_url']),
      fileUrl: approved ? wallpaperPublicUrl(j['file_name']) : storageSignedUrl(j['review_file_url']),
      ownerCount: _int(j['owner_count']),
      width: (j['width'] as num?)?.toInt(),
      height: (j['height'] as num?)?.toInt(),
      frames: (j['frames'] as num?)?.toInt(),
      bytes: (j['bytes'] as num?)?.toInt(),
    );
  }
}

class AdminUploadJob {
  const AdminUploadJob({required this.id, required this.name, required this.status, this.error});

  final String id;
  final String name;
  final String status; // queued | processing | failed
  final String? error;

  factory AdminUploadJob.fromJson(Map<String, dynamic> j) => AdminUploadJob(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        status: (j['status'] as String?) ?? '',
        error: j['error'] as String?,
      );
}

class AdminWallpaperPage {
  const AdminWallpaperPage({required this.items, required this.jobs, required this.hasMore});

  final List<AdminWallpaper> items;
  final List<AdminUploadJob> jobs;
  final bool hasMore;
}

/// Event di Panel Admin.
class AdminWallpaperEvent {
  const AdminWallpaperEvent({
    required this.id,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    required this.wallpaperIds,
    this.creatorName,
  });

  final int id;
  final String name;
  final DateTime startsAt;
  final DateTime endsAt;
  final List<String> wallpaperIds;
  final String? creatorName;

  bool isRunning(DateTime now) => !now.isBefore(startsAt) && now.isBefore(endsAt);
  bool isUpcoming(DateTime now) => now.isBefore(startsAt);
  bool isEnded(DateTime now) => !now.isBefore(endsAt);

  static AdminWallpaperEvent? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num?)?.toInt();
    final s = _date(j['starts_at']);
    final e = _date(j['ends_at']);
    if (id == null || s == null || e == null) return null;
    final ids = j['wallpaper_ids'];
    return AdminWallpaperEvent(
      id: id,
      name: (j['name'] as String?) ?? '',
      startsAt: s,
      endsAt: e,
      wallpaperIds: ids is List ? ids.whereType<String>().toList() : const [],
      creatorName: j['creator_name'] as String?,
    );
  }
}

/// Wallpaper Limited yang sudah disetujui (calon isi event).
class AdminEventCandidate {
  const AdminEventCandidate({
    required this.id,
    required this.name,
    required this.isActive,
    required this.weight,
    this.previewUrl,
    this.eventId,
  });

  final String id;
  final String name;
  final bool isActive;
  final int weight;
  final String? previewUrl;
  final int? eventId;

  factory AdminEventCandidate.fromJson(Map<String, dynamic> j) => AdminEventCandidate(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        isActive: j['is_active'] == true,
        weight: _int(j['weight'], 1),
        previewUrl: wallpaperPublicUrl(j['preview_name']),
        eventId: (j['event_id'] as num?)?.toInt(),
      );
}

class AdminEventPage {
  const AdminEventPage({required this.events, required this.candidates, required this.clockOffset});

  final List<AdminWallpaperEvent> events;
  final List<AdminEventCandidate> candidates;
  final Duration clockOffset;

  DateTime get serverNow => DateTime.now().toUtc().add(clockOffset);

  factory AdminEventPage.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> rows(Object? v) =>
        v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
    return AdminEventPage(
      events: rows(j['events']).map(AdminWallpaperEvent.fromJson).whereType<AdminWallpaperEvent>().toList(),
      candidates: rows(j['candidates']).map(AdminEventCandidate.fromJson).where((c) => c.id.isNotEmpty).toList(),
      clockOffset: _date(j['server_now'])?.difference(DateTime.now().toUtc()) ?? Duration.zero,
    );
  }
}
