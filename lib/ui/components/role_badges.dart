import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/screen_seed.dart';
import '../../providers.dart';

/// Role di tabel `user_roles`. developer/admin/moderator = STAFF (punya hak
/// moderasi). betaTester & security = role badge saja (tanpa hak apa pun,
/// tidak bisa membuka Panel Admin, dan tetap bisa di-ban).
enum ZenimeRole {
  developer('developer'),
  admin('admin'),
  moderator('moderator'),
  betaTester('beta_tester'),
  security('security');

  const ZenimeRole(this.value);

  /// Nilai di kolom `user_roles.role`.
  final String value;

  /// Staff = boleh membuka Panel Admin. Hak per aksi tetap dicek di server.
  bool get isStaff =>
      this == ZenimeRole.developer || this == ZenimeRole.admin || this == ZenimeRole.moderator;

  static ZenimeRole? fromValue(String? v) {
    for (final r in ZenimeRole.values) {
      if (r.value == v) return r;
    }
    return null;
  }
}

/// Role + warna gradient badge + warna centang satu user.
class RoleInfo {
  const RoleInfo({
    required this.role,
    required this.primary,
    required this.secondary,
    required this.checkColor,
  });

  final ZenimeRole role;
  final Color primary;
  final Color secondary;

  /// Warna centang di samping username (role menang atas Premium).
  final Color checkColor;
}

Color? _parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Warna default centang per role (sama dengan Chat Global & Clan):
/// developer merah, admin hijau, moderator ungu; `badge_color` custom menang.
Color _defaultCheck(ZenimeRole r) {
  switch (r) {
    case ZenimeRole.developer:
      return const Color(0xFFE53935);
    case ZenimeRole.admin:
      return const Color(0xFF43A047);
    case ZenimeRole.moderator:
      return const Color(0xFF8E24AA);
    case ZenimeRole.betaTester:
      return const Color(0xFFFACC15);
    case ZenimeRole.security:
      return const Color(0xFF00E5FF);
  }
}

RoleInfo? roleInfoFrom(String? roleValue, String? badgeColorHex) {
  final role = ZenimeRole.fromValue(roleValue);
  if (role == null) return null;
  final custom = _parseHex(badgeColorHex);
  if (custom != null) {
    return RoleInfo(
      role: role,
      primary: custom,
      secondary: Color.lerp(custom, Colors.white, 0.35)!,
      checkColor: custom,
    );
  }
  switch (role) {
    case ZenimeRole.developer:
      return RoleInfo(
        role: role,
        primary: const Color(0xFFFF3B5C),
        secondary: const Color(0xFFFF7A3D),
        checkColor: _defaultCheck(role),
      );
    case ZenimeRole.admin:
      return RoleInfo(
        role: role,
        primary: const Color(0xFF2EE6A6),
        secondary: const Color(0xFF19B5FF),
        checkColor: _defaultCheck(role),
      );
    case ZenimeRole.moderator:
      return RoleInfo(
        role: role,
        primary: const Color(0xFFB26CFF),
        secondary: const Color(0xFF6C7BFF),
        checkColor: _defaultCheck(role),
      );
    case ZenimeRole.betaTester:
      return RoleInfo(
        role: role,
        primary: const Color(0xFFFACC15),
        secondary: const Color(0xFFFFE680),
        checkColor: _defaultCheck(role),
      );
    case ZenimeRole.security:
      return RoleInfo(
        role: role,
        primary: const Color(0xFF00E5FF),
        secondary: const Color(0xFF6BFFB8),
        checkColor: _defaultCheck(role),
      );
  }
}

/// Mengumpulkan permintaan role dari banyak badge (mis. satu layar chat) jadi
/// satu request `firebase_uid=in.(...)` per ~40ms, seperti getRolesForUids di
/// Zenime, supaya chat dengan banyak pengirim tidak menembak server satu-satu.
class _RoleBatcher {
  _RoleBatcher(this._dio);

  final Dio _dio;
  final Map<String, Completer<RoleInfo?>> _pending = {};
  Timer? _timer;

  static final RegExp _safeUid = RegExp(r'^[A-Za-z0-9_-]+$');
  static const int _chunk = 50;

  Future<RoleInfo?> load(String uid) {
    if (!_safeUid.hasMatch(uid)) return Future.value(null);
    final c = _pending.putIfAbsent(uid, () => Completer<RoleInfo?>());
    _timer ??= Timer(const Duration(milliseconds: 40), _flush);
    return c.future;
  }

  Future<void> _flush() async {
    final batch = Map<String, Completer<RoleInfo?>>.from(_pending);
    _pending.clear();
    _timer = null;
    final uids = batch.keys.toList();
    for (var i = 0; i < uids.length; i += _chunk) {
      final part = uids.sublist(i, i + _chunk > uids.length ? uids.length : i + _chunk);
      try {
        final res = await _dio.get<dynamic>(
          'rest/v1/user_roles',
          queryParameters: {
            'firebase_uid': 'in.(${part.join(',')})',
            'select': 'firebase_uid,role,badge_color',
          },
        );
        final found = <String, RoleInfo>{};
        final data = res.data;
        if (data is List) {
          for (final row in data) {
            if (row is! Map) continue;
            final uid = row['firebase_uid'] as String?;
            final info = roleInfoFrom(row['role'] as String?, row['badge_color'] as String?);
            if (uid != null && info != null) found[uid] = info;
          }
        }
        for (final uid in part) {
          batch[uid]!.complete(found[uid]);
        }
      } catch (e) {
        // Gagal: error (bukan null) supaya tidak di-cache selamanya (lihat
        // roleInfoProvider); badge cukup tidak tampil dulu.
        for (final uid in part) {
          batch[uid]!.completeError(e);
        }
      }
    }
  }
}

final _roleBatcherProvider =
    Provider<_RoleBatcher>((ref) => _RoleBatcher(ref.watch(supabaseDioProvider)));

/// Role satu user dari `user_roles` (SELECT publik). null = bukan staff atau
/// gagal dimuat (badge cukup tidak tampil). Hasil sukses di-cache selama app
/// jalan; yang gagal dicoba lagi saat widget dibangun ulang.
final roleInfoProvider =
    FutureProvider.autoDispose.family<RoleInfo?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  final batcher = ref.watch(_roleBatcherProvider);
  // Layar Profil publik menitipkan role dari screen-data (tanpa request lagi).
  if (ScreenSeed.active(uid)) {
    final (hit, value) = await ScreenSeed.take('role', uid);
    if (hit) {
      ref.keepAlive();
      return value as RoleInfo?;
    }
  }
  final info = await batcher.load(uid);
  ref.keepAlive();
  return info;
});

ShapeBorder _roleShape(ZenimeRole role, Color outline) {
  final side = BorderSide(color: outline, width: 1);
  switch (role) {
    // potong kiri-atas & kanan-bawah
    case ZenimeRole.developer:
      return BeveledRectangleBorder(
        side: side,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(5),
          bottomRight: Radius.circular(5),
        ),
      );
    // potong keempat sudut
    case ZenimeRole.admin:
      return BeveledRectangleBorder(
        side: side,
        borderRadius: BorderRadius.circular(4),
      );
    // potong kanan-atas & kiri-bawah
    case ZenimeRole.moderator:
      return BeveledRectangleBorder(
        side: side,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(5),
          bottomLeft: Radius.circular(5),
        ),
      );
    // potong dua sudut kanan
    case ZenimeRole.betaTester:
      return BeveledRectangleBorder(
        side: side,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(5),
          bottomRight: Radius.circular(5),
        ),
      );
    // potong dua sudut kiri
    case ZenimeRole.security:
      return BeveledRectangleBorder(
        side: side,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(5),
          bottomLeft: Radius.circular(5),
        ),
      );
  }
}

IconData _roleIcon(ZenimeRole r) {
  switch (r) {
    case ZenimeRole.developer:
      return Icons.code;
    case ZenimeRole.admin:
      return Icons.verified_user;
    case ZenimeRole.moderator:
      return Icons.visibility;
    case ZenimeRole.betaTester:
      return Icons.science_rounded;
    case ZenimeRole.security:
      return Icons.security_rounded;
  }
}

String _roleLabel(ZenimeRole r) {
  switch (r) {
    case ZenimeRole.developer:
      return 'DEVELOPER';
    case ZenimeRole.admin:
      return 'ADMIN';
    case ZenimeRole.moderator:
      return 'MODERATOR';
    case ZenimeRole.betaTester:
      return 'BETA TESTER';
    case ZenimeRole.security:
      return 'SECURITY';
  }
}

/// Badge role gaya "cyber cut" (port RoleBadge.kt): sudut dipotong beda tiap
/// role, gradient neon, ikon + label. Developer punya kilau yang geser terus.
/// Tidak render apa-apa kalau user tidak punya role.
class RoleBadge extends ConsumerWidget {
  const RoleBadge({
    super.key,
    required this.firebaseUid,
    this.height = 20,
    this.rounded = false,
  });

  final String firebaseUid;
  final double height;

  /// true = kapsul sudut membulat (header Profil gaya baru), false = cyber cut.
  final bool rounded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(roleInfoProvider(firebaseUid)).valueOrNull;
    if (info == null) return const SizedBox.shrink();
    return RoleBadgeChip(info: info, height: height, rounded: rounded);
  }
}

class RoleBadgeChip extends StatefulWidget {
  const RoleBadgeChip({
    super.key,
    required this.info,
    this.height = 20,
    this.rounded = false,
  });

  final RoleInfo info;
  final double height;
  final bool rounded;

  @override
  State<RoleBadgeChip> createState() => _RoleBadgeChipState();
}

class _RoleBadgeChipState extends State<RoleBadgeChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.info.role == ZenimeRole.developer) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final rounded = widget.rounded;
    final ShapeBorder shape = rounded
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
        : _roleShape(info.role, Colors.black.withValues(alpha: 0.65));
    // Teks gelap di warna neon terang; kalau badge_color custom-nya gelap, putih.
    final lum = (info.primary.computeLuminance() + info.secondary.computeLuminance()) / 2;
    final content = lum > 0.2 ? const Color(0xFF0B0B0F) : Colors.white;

    final body = Container(
      height: widget.height,
      padding: EdgeInsets.symmetric(horizontal: rounded ? 10 : 8),
      decoration: ShapeDecoration(
        shape: shape,
        gradient: LinearGradient(colors: [info.primary, info.secondary]),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(_roleIcon(info.role), size: rounded ? 12 : 10, color: content),
          SizedBox(width: rounded ? 5 : 3),
          Text(
            _roleLabel(info.role),
            style: TextStyle(
              color: content,
              fontSize: rounded ? 10 : 9,
              fontWeight: rounded ? FontWeight.w900 : FontWeight.w800,
              letterSpacing: rounded ? 1.0 : 0.8,
              height: 1.2,
            ),
          ),
        ],
      ),
    );

    final c = _c;
    final shaped = c == null
        ? body
        : AnimatedBuilder(
            animation: c,
            builder: (context, child) {
              // Kilau melintas dari kiri ke kanan (-0.3 .. 1.3 lebar badge).
              final t = -0.3 + 1.6 * c.value;
              return Stack(
                children: [
                  child!,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1 + 2 * (t - 0.14), 0),
                            end: Alignment(-1 + 2 * (t + 0.14), 0.4),
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: 0.7),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
            child: body,
          );

    return RepaintBoundary(
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: shaped,
      ),
    );
  }
}

/// Centang di samping username. Role menang atas Premium (satu centang saja):
/// warna role kalau punya role, biru kalau cuma Premium, kosong kalau bukan
/// keduanya (port UserCheckBadge.kt).
class UserCheckBadge extends ConsumerWidget {
  const UserCheckBadge({
    super.key,
    required this.firebaseUid,
    required this.isPremium,
    this.size = 16,
  });

  final String firebaseUid;
  final bool isPremium;
  final double size;

  static const Color _premiumBlue = Color(0xFF3897F0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleInfoProvider(firebaseUid)).valueOrNull;
    final tint = role?.checkColor ?? (isPremium ? _premiumBlue : null);
    if (tint == null) return const SizedBox.shrink();
    return Icon(Icons.verified, size: size, color: tint);
  }
}

/// Avatar otomatis (warna solid + inisial) yang deterministik per [seed]
/// (biasanya firebase_uid), port GeneratedAvatar.kt.
class GeneratedAvatar extends StatelessWidget {
  const GeneratedAvatar({
    super.key,
    required this.seed,
    required this.label,
    required this.size,
  });

  final String seed;
  final String label;
  final double size;

  static const List<Color> _palette = [
    Color(0xFFE53E5A),
    Color(0xFFEF6C3A),
    Color(0xFFF2A93B),
    Color(0xFF7C5CE0),
    Color(0xFF3D8BFF),
    Color(0xFF2FB380),
    Color(0xFFE0507A),
    Color(0xFF4FB8C4),
  ];

  // Hash sendiri (bukan String.hashCode) supaya warna stabil lintas platform.
  static int _stableHash(String s) {
    var h = 0;
    for (final u in s.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final color = _palette[_stableHash(seed) % _palette.length];
    final trimmed = label.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size / 2.2,
        ),
      ),
    );
  }
}
