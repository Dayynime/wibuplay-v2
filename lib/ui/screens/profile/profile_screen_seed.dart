import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/screen_seed.dart';
import '../../../data/models/account_models.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/friend_models.dart';
import '../../../data/models/public_profile_models.dart';
import '../../../data/models/xp_models.dart';
import '../../../providers.dart';
import '../../components/avatar_frame.dart';
import '../../components/role_badges.dart';

Map<String, dynamic>? _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// Ambil `screen-data` Profil publik sekali, lalu bagikan ke semua bagian
/// layar lewat [ScreenSeed]. Dipanggil di initState (sebelum build pertama).
/// Return relasi teman (null = gagal / profil sendiri -> pakai jalur lama).
Future<FriendRelation?> loadProfileScreenSeed(WidgetRef ref, String uid) async {
  ScreenSeed.begin(uid);
  final frames = ref.read(avatarFrameCacheProvider.notifier);
  frames.reserve(uid);

  Map<String, dynamic>? d;
  try {
    d = await ref.read(screenDataRepositoryProvider).profile(uid);
  } catch (_) {
    d = null;
  }

  final seeds = <String, Object?>{};
  FriendRelation? relation;
  var frameDone = false;

  if (d != null) {
    final profile = _map(d['profile']);
    if (profile != null) {
      final row = _map(profile['row']);
      seeds['profile'] = row == null ? null : ChatProfile.fromJson(row);
      final created = row?['created_at'];
      seeds['join'] = created is String ? DateTime.tryParse(created)?.toLocal() : null;
    }

    // Profil sendiri: premium JANGAN dititipkan (versi ini tanpa tanggal
    // kedaluwarsa; kartu Beranda butuh tanggalnya).
    final me = ref.read(authRepositoryProvider).currentUser?.uid;
    final premium = d['premium'];
    if (premium is bool && me != uid) seeds['premium'] = PremiumStatus(isPremium: premium);

    final xp = _map(d['xp']);
    if (xp != null) {
      final row = _map(xp['row']);
      seeds['xp'] = row == null ? null : UserXp.fromJson(row);
    }

    final tag = d['clan_tag'];
    if (tag is String) seeds['clan_tag'] = tag.isEmpty ? null : tag;

    final count = d['comment_count'];
    if (count is num) seeds['comment_count'] = count.toInt();

    final role = _map(d['role']);
    if (role != null) {
      seeds['role'] = roleInfoFrom(role['role'] as String?, role['badge_color'] as String?);
    }

    final frame = d['frame_id'];
    if (frame is String) {
      frames.fill(uid, frame.isEmpty ? null : frame);
      frameDone = true;
    }

    final rel = _map(d['relation']);
    if (rel != null) {
      final id = rel['id']?.toString() ?? '';
      switch (rel['kind']) {
        case 'none':
          relation = const FriendRelationNone();
        case 'friends':
          if (id.isNotEmpty) relation = FriendRelationFriends(id);
        case 'outgoing':
          if (id.isNotEmpty) relation = FriendRelationOutgoing(id);
        case 'incoming':
          if (id.isNotEmpty) relation = FriendRelationIncoming(id);
      }
    }

    final content = _map(d['content']);
    if (content != null && content['favorites_failed'] != true && content['history_failed'] != true) {
      final favs = content['favorites'];
      final hist = content['history'];
      seeds['content'] = PublicProfileContent(
        favoritesPublic: content['favorites_public'] == true,
        historyPublic: content['history_public'] == true,
        favorites: favs is List
            ? favs.whereType<Map>().map((e) => PublicFavoriteRow.fromJson(Map<String, dynamic>.from(e))).toList()
            : null,
        history: hist is List
            ? hist.whereType<Map>().map((e) => PublicHistoryRow.fromJson(Map<String, dynamic>.from(e))).toList()
            : null,
      );
    }
  }

  ScreenSeed.finish(uid, seeds);
  if (!frameDone) frames.release(uid);
  return relation;
}
