import 'account_models.dart';
import 'chat_models.dart';
import 'xp_models.dart';

/// Hasil Edge Function `home-bootstrap`: semua data kartu akun Beranda dalam
/// satu request. Field null = bagian itu gagal di server; app memakai jalur
/// lama khusus untuk bagian tersebut.
class HomeBootstrap {
  const HomeBootstrap({
    required this.uid,
    required this.raw,
    this.premium,
    this.identity,
    this.coins,
    this.xp,
    this.profile,
    this.friendRequests,
    this.unread,
  });

  final String uid;
  final Map<String, dynamic> raw;
  final PremiumStatus? premium;
  final ProfileIdentity? identity;
  final int? coins;
  final UserXp? xp;
  final ChatProfile? profile;
  final int? friendRequests;
  final int? unread;

  static Map<String, dynamic>? _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  factory HomeBootstrap.fromJson(Map<String, dynamic> j) {
    final premium = _map(j['premium']);
    final identity = _map(j['identity']);
    final xp = _map(j['xp']);
    final profile = _map(j['profile']);
    return HomeBootstrap(
      uid: (j['uid'] as String?) ?? '',
      raw: j,
      premium: premium == null ? null : PremiumStatus.fromJson(premium),
      identity: identity == null ? null : ProfileIdentity.fromJson(identity),
      coins: _int(j['coins']),
      xp: xp == null ? null : UserXp.fromJson(xp),
      profile: profile == null ? null : ChatProfile.fromJson(profile),
      friendRequests: _int(j['friend_requests']),
      unread: _int(j['unread']),
    );
  }
}
