/// Border Avatar animasi. File border di-bundle di app
/// (assets/frames/<id>.webp); server cuma menyimpan kepemilikan, harga,
/// dan border yang sedang dipakai.

/// id border yang punya file di app. id dari server yang tidak ada di sini
/// diabaikan (misal border baru yang butuh update app).
const Map<String, String> kAvatarFrameAssets = {
  'neon': 'assets/frames/neon.webp',
  'api': 'assets/frames/api.webp',
  'es': 'assets/frames/es.webp',
  'petir': 'assets/frames/petir.webp',
  'sakura': 'assets/frames/sakura.webp',
  'galaksi': 'assets/frames/galaksi.webp',
  'malaikat': 'assets/frames/malaikat.webp',
};

String? avatarFrameAsset(String? id) => id == null ? null : kAvatarFrameAssets[id];

/// Ukuran kanvas border dibanding avatar. Default 1.25 (avatar mengisi 80%
/// kanvas). Border dengan hiasan besar (sayap, halo) pakai kanvas lebih lebar.
const double kAvatarFrameScale = 1.25;
const Map<String, double> _kFrameScaleById = {
  'malaikat': 1.8,
};

double avatarFrameScale(String? id) => _kFrameScaleById[id] ?? kAvatarFrameScale;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class AvatarFrameItem {
  const AvatarFrameItem({
    required this.id,
    required this.name,
    required this.price,
    required this.owned,
  });

  final String id;
  final String name;
  final int price;
  final bool owned;

  String get asset => kAvatarFrameAssets[id]!;

  static AvatarFrameItem? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || !kAvatarFrameAssets.containsKey(id)) return null;
    return AvatarFrameItem(
      id: id,
      name: (j['name'] as String?) ?? id,
      price: _int(j['price']),
      owned: j['owned'] == true,
    );
  }

  AvatarFrameItem copyWith({bool? owned}) =>
      AvatarFrameItem(id: id, name: name, price: price, owned: owned ?? this.owned);
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
      equippedId: eq is String && kAvatarFrameAssets.containsKey(eq) ? eq : null,
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
