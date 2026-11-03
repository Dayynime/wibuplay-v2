/// Model Nobar (nonton bareng). Semua nilai dari Edge Function `nobar-room`.
library;

/// Batas anggota per room (sama dengan server).
const int kNobarMaxMembers = 5;

class NobarMember {
  const NobarMember({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.usernameColor,
    this.active = true,
  });

  final String uid;
  final String username;
  final String? avatarUrl;
  final String? usernameColor;

  /// false = tidak ada kabar > 90 detik (app ditutup / sinyal hilang).
  final bool active;

  static NobarMember? fromJson(dynamic v) {
    if (v is! Map) return null;
    final uid = v['uid'];
    if (uid is! String || uid.isEmpty) return null;
    final name = (v['username'] as String?)?.trim() ?? '';
    final avatar = v['avatar_url'] as String?;
    return NobarMember(
      uid: uid,
      username: name.isEmpty ? 'Pengguna Zenime' : name,
      avatarUrl: (avatar == null || avatar.isEmpty) ? null : avatar,
      usernameColor: v['username_color'] as String?,
      active: v['active'] != false,
    );
  }
}

class NobarRoom {
  const NobarRoom({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.movieId,
    required this.episodeId,
    required this.members,
    this.movieTitle,
    this.posterUrl,
    this.positionMs = 0,
    this.playing = false,
    this.stateAgeMs = 0,
    this.maxMembers = kNobarMaxMembers,
  });

  final String id;
  final String code;
  final String hostUid;
  final String movieId;
  final String? movieTitle;
  final String? posterUrl;

  /// Status video terakhir yang disimpan host (untuk yang baru masuk).
  final String episodeId;
  final int positionMs;
  final bool playing;

  /// Umur status di atas (ms), dihitung pakai jam server supaya jam HP yang
  /// tidak pas tidak berpengaruh.
  final int stateAgeMs;
  final int maxMembers;
  final List<NobarMember> members;

  String get topic => 'nobar-$id';

  bool isHost(String? uid) => uid != null && uid == hostUid;

  NobarMember? member(String uid) {
    for (final m in members) {
      if (m.uid == uid) return m;
    }
    return null;
  }

  /// Perkiraan posisi host sekarang berdasarkan status tersimpan.
  int get estimatedPositionMs => playing ? positionMs + stateAgeMs : positionMs;

  factory NobarRoom.fromJson(Map<String, dynamic> j) {
    final list = j['members'];
    final stateAt = DateTime.tryParse((j['state_at'] as String?) ?? '');
    final serverNow = DateTime.tryParse((j['server_now'] as String?) ?? '');
    var age = 0;
    if (stateAt != null && serverNow != null) {
      age = serverNow.difference(stateAt).inMilliseconds.clamp(0, 6 * 3600 * 1000);
    }
    return NobarRoom(
      id: j['id'] as String? ?? '',
      code: j['code'] as String? ?? '',
      hostUid: j['host_uid'] as String? ?? '',
      movieId: j['movie_id'] as String? ?? '',
      movieTitle: j['movie_title'] as String?,
      posterUrl: j['poster_url'] as String?,
      episodeId: j['episode_id'] as String? ?? '',
      positionMs: (j['position_ms'] as num?)?.toInt() ?? 0,
      playing: j['playing'] == true,
      stateAgeMs: age,
      maxMembers: (j['max_members'] as num?)?.toInt() ?? kNobarMaxMembers,
      members: list is List
          ? list.map(NobarMember.fromJson).whereType<NobarMember>().toList()
          : const <NobarMember>[],
    );
  }
}

/// Server STUN/TURN untuk voice chat nobar.
class NobarIce {
  const NobarIce({required this.iceServers, required this.turnReady});

  final List<Map<String, dynamic>> iceServers;
  final bool turnReady;

  factory NobarIce.fromJson(Map<String, dynamic> j) {
    final list = j['ice_servers'];
    return NobarIce(
      iceServers: list is List
          ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const <Map<String, dynamic>>[],
      turnReady: j['turn_ready'] == true,
    );
  }
}
