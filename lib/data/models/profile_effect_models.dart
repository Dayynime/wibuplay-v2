import '../../core/supabase_config.dart';
import 'avatar_frame_models.dart' show AvatarFrameTier;

/// Efek Profil animasi (ditumpuk di atas kartu profil). Server menyimpan
/// katalog (id, nama, harga, tier, lapisan), kepemilikan, dan efek yang dipakai.
///
/// File ada di bucket Storage publik [kProfileEffectBucket]:
/// - l/<hash>.webp : lapisan animasi (WebP animasi, menutupi seluruh kartu)
/// - t/<id>.<ext>  : gambar pratinjau untuk grid Shop

const String kProfileEffectBucket = 'profile-effects';

final RegExp _kEffectIdRe = RegExp(r'^[a-z0-9_]{2,32}$');
final RegExp _kLayerFileRe = RegExp(r'^[0-9a-f]{8,64}$');
final RegExp _kThumbRe = RegExp(r'^t/[a-z0-9_]{2,32}\.(png|webp|gif|jpg)$');

bool isValidEffectId(String? id) => id != null && _kEffectIdRe.hasMatch(id);

String _publicUrl(String path) =>
    '${SupabaseConfig.url}/storage/v1/object/public/$kProfileEffectBucket/$path';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

int _ms(Object? v) {
  final n = _int(v);
  return n < 0 ? 0 : (n > 600000 ? 600000 : n);
}

/// Satu lapisan efek. Aturan waktunya meniru Discord:
/// - muncul setelah [startMs] sejak efek mulai diputar,
/// - main sekali (semua frame), lalu hilang,
/// - kalau [loop], muncul lagi setelah jeda [delayMs], terus berulang.
class ProfileEffectLayer {
  const ProfileEffectLayer({
    required this.files,
    required this.loop,
    required this.startMs,
    required this.delayMs,
    required this.z,
  });

  /// File pertama = utama; sisanya alternatif yang dipilih acak tiap putaran.
  final List<String> files;
  final bool loop;
  final int startMs;
  final int delayMs;
  final int z;

  String url(String file) => _publicUrl('l/$file.webp');

  static ProfileEffectLayer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final main = raw['f'];
    if (main is! String || !_kLayerFileRe.hasMatch(main)) return null;
    final alt = raw['alt'];
    return ProfileEffectLayer(
      files: [
        main,
        if (alt is List) ...alt.whereType<String>().where(_kLayerFileRe.hasMatch),
      ],
      loop: raw['loop'] == true,
      startMs: _ms(raw['start']),
      delayMs: _ms(raw['delay']),
      z: _int(raw['z']),
    );
  }

  static List<ProfileEffectLayer> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    final out = raw.map(fromJson).whereType<ProfileEffectLayer>().toList()
      ..sort((a, b) => a.z.compareTo(b.z));
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileEffectLayer &&
      other.loop == loop &&
      other.startMs == startMs &&
      other.delayMs == delayMs &&
      other.z == z &&
      other.files.join(',') == files.join(',');

  @override
  int get hashCode => Object.hash(files.join(','), loop, startMs, delayMs, z);
}

/// Efek yang siap diputar: id + lapisan (urut zIndex, bawah ke atas).
class ProfileEffect {
  const ProfileEffect({required this.id, required this.layers});

  final String id;
  final List<ProfileEffectLayer> layers;

  @override
  bool operator ==(Object other) => other is ProfileEffect && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ProfileEffectItem {
  const ProfileEffectItem({
    required this.id,
    required this.name,
    required this.price,
    required this.owned,
    required this.layers,
    this.thumb,
    this.tier = AvatarFrameTier.basic,
  });

  final String id;
  final String name;
  final int price;
  final bool owned;
  final List<ProfileEffectLayer> layers;
  final String? thumb;
  final AvatarFrameTier tier;

  String? get thumbUrl => thumb == null ? null : _publicUrl(thumb!);

  ProfileEffect get effect => ProfileEffect(id: id, layers: layers);

  static ProfileEffectItem? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || !isValidEffectId(id)) return null;
    final layers = ProfileEffectLayer.listFromJson(j['layers']);
    if (layers.isEmpty) return null;
    final thumb = j['thumb'];
    return ProfileEffectItem(
      id: id,
      name: (j['name'] as String?) ?? id,
      price: _int(j['price']),
      owned: j['owned'] == true,
      layers: layers,
      thumb: thumb is String && _kThumbRe.hasMatch(thumb) ? thumb : null,
      tier: AvatarFrameTier.parse(j['tier']),
    );
  }

  ProfileEffectItem copyWith({bool? owned}) => ProfileEffectItem(
        id: id,
        name: name,
        price: price,
        owned: owned ?? this.owned,
        layers: layers,
        thumb: thumb,
        tier: tier,
      );
}

class ProfileEffectState {
  const ProfileEffectState({required this.balance, required this.effects, this.equippedId});

  final int balance;
  final List<ProfileEffectItem> effects;
  final String? equippedId;

  ProfileEffectItem? get equipped {
    for (final e in effects) {
      if (e.id == equippedId) return e;
    }
    return null;
  }

  factory ProfileEffectState.fromJson(Map<String, dynamic> j) {
    final raw = j['effects'];
    final effects = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => ProfileEffectItem.fromJson(Map<String, dynamic>.from(e)))
            .whereType<ProfileEffectItem>()
            .toList()
        : <ProfileEffectItem>[];
    final eq = j['equipped_id'];
    return ProfileEffectState(
      balance: _int(j['balance']),
      effects: effects,
      equippedId: eq is String && isValidEffectId(eq) ? eq : null,
    );
  }

  ProfileEffectState copyWith({
    int? balance,
    List<ProfileEffectItem>? effects,
    String? Function()? equippedId,
  }) =>
      ProfileEffectState(
        balance: balance ?? this.balance,
        effects: effects ?? this.effects,
        equippedId: equippedId != null ? equippedId() : this.equippedId,
      );
}
