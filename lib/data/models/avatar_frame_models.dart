import '../../core/supabase_config.dart';

/// Border Avatar animasi. Server menyimpan katalog (id, nama, harga),
/// kepemilikan, dan border yang sedang dipakai.
///
/// File border ada di dua tempat:
/// - Bawaan app (assets/frames/<id>.webp) untuk border generasi pertama.
/// - Supabase Storage, bucket publik [kAvatarFrameBucket] (<id>.webp), untuk
///   semua border lain. Border baru cukup diupload + ditambah ke katalog,
///   tanpa update app.

/// Border yang file-nya di-bundle di app.
const Map<String, String> kAvatarFrameAssets = {
  'neon': 'assets/frames/neon.webp',
  'api': 'assets/frames/api.webp',
  'es': 'assets/frames/es.webp',
  'petir': 'assets/frames/petir.webp',
  'sakura': 'assets/frames/sakura.webp',
  'galaksi': 'assets/frames/galaksi.webp',
  'malaikat': 'assets/frames/malaikat.webp',
};

/// Bucket Storage (publik, read-only untuk app) berisi border remote.
const String kAvatarFrameBucket = 'avatar-frames';

/// id border remote juga dipakai sebagai nama file, jadi dibatasi ketat
/// supaya tidak bisa menyusun path/URL aneh.
final RegExp _kFrameIdRe = RegExp(r'^[a-z0-9_]{1,64}$');

bool isValidFrameId(String? id) =>
    id != null && (kAvatarFrameAssets.containsKey(id) || _kFrameIdRe.hasMatch(id));

/// Path asset kalau border ini bawaan app, selain itu null.
String? avatarFrameAsset(String? id) => id == null ? null : kAvatarFrameAssets[id];

/// URL Storage kalau border ini remote, selain itu null.
String? avatarFrameUrl(String? id) {
  if (id == null || kAvatarFrameAssets.containsKey(id) || !_kFrameIdRe.hasMatch(id)) {
    return null;
  }
  return '${SupabaseConfig.url}/storage/v1/object/public/$kAvatarFrameBucket/$id.webp';
}

/// Ukuran kanvas border dibanding avatar.
/// - Border bawaan: default 1.25 (avatar mengisi 80% kanvas); yang hiasannya
///   besar (sayap, halo) pakai kanvas lebih lebar.
/// - Border remote: 1.2 (avatar mengisi ~83% kanvas).
const double kAvatarFrameScale = 1.25;
const double kRemoteAvatarFrameScale = 1.2;
const Map<String, double> _kFrameScaleById = {
  'malaikat': 1.8,
};

double avatarFrameScale(String? id) {
  if (id == null) return kAvatarFrameScale;
  final custom = _kFrameScaleById[id];
  if (custom != null) return custom;
  return kAvatarFrameAssets.containsKey(id) ? kAvatarFrameScale : kRemoteAvatarFrameScale;
}

/// Tingkat border, ditentukan server (kolom avatar_frames.tier).
enum AvatarFrameTier {
  basic('Basic'),
  standard('Standard'),
  premium('Premium');

  const AvatarFrameTier(this.label);
  final String label;

  static AvatarFrameTier parse(Object? v) => switch (v) {
        'standard' => AvatarFrameTier.standard,
        'premium' => AvatarFrameTier.premium,
        _ => AvatarFrameTier.basic,
      };
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class AvatarFrameItem {
  const AvatarFrameItem({
    required this.id,
    required this.name,
    required this.price,
    required this.owned,
    this.tier = AvatarFrameTier.basic,
  });

  final String id;
  final String name;
  final int price;
  final bool owned;
  final AvatarFrameTier tier;

  static AvatarFrameItem? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || !isValidFrameId(id)) return null;
    return AvatarFrameItem(
      id: id,
      name: (j['name'] as String?) ?? id,
      price: _int(j['price']),
      owned: j['owned'] == true,
      tier: AvatarFrameTier.parse(j['tier']),
    );
  }

  AvatarFrameItem copyWith({bool? owned}) =>
      AvatarFrameItem(id: id, name: name, price: price, owned: owned ?? this.owned, tier: tier);
}

class AvatarFrameState {
  const AvatarFrameState({required this.balance, required this.frames, this.equippedId});

  final int balance;
  final List<AvatarFrameItem> frames;
  final String? equippedId;

  factory AvatarFrameState.fromJson(Map<String, dynamic> j) {
    final raw = j['frames'];
    final frames = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => AvatarFrameItem.fromJson(Map<String, dynamic>.from(e)))
            .whereType<AvatarFrameItem>()
            .toList()
        : <AvatarFrameItem>[];
    final eq = j['equipped_id'];
    return AvatarFrameState(
      balance: _int(j['balance']),
      frames: frames,
      equippedId: eq is String && isValidFrameId(eq) ? eq : null,
    );
  }

  AvatarFrameState copyWith({
    int? balance,
    List<AvatarFrameItem>? frames,
    String? Function()? equippedId,
  }) =>
      AvatarFrameState(
        balance: balance ?? this.balance,
        frames: frames ?? this.frames,
        equippedId: equippedId != null ? equippedId() : this.equippedId,
      );
}
