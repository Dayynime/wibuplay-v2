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
  });

  final String id;
  final String name;
  final WallpaperRarity rarity;
  final String url;
  final String previewUrl;
  final double? chancePercent;

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
  });

  final int spinCost;
  final int spin10Cost;
  final int dupRefundPercent;
  final int balance;
  final List<WallpaperItem> pool;
  final List<WallpaperItem> inventory;
  final String? equippedId;

  factory WallpaperState.fromJson(Map<String, dynamic> j) => WallpaperState(
        spinCost: _int(j['spin_cost']),
        spin10Cost: _int(j['spin10_cost'], _int(j['spin_cost']) * 10),
        dupRefundPercent: _int(j['dup_refund_percent']),
        balance: _int(j['balance']),
        pool: _items(j['pool']),
        inventory: _items(j['inventory']),
        equippedId: j['equipped_id'] as String?,
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
