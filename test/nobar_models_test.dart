import 'package:flutter_test/flutter_test.dart';
import 'package:wibuplay/data/models/nobar_models.dart';

void main() {
  group('NobarRoom.fromJson', () {
    test('membaca room, anggota, dan umur status dari jam server', () {
      final r = NobarRoom.fromJson({
        'id': 'a1b2',
        'code': 'K7QX2M',
        'host_uid': 'u1',
        'movie_id': 'm1',
        'movie_title': 'Frieren',
        'episode_id': 'e5',
        'position_ms': 60000,
        'playing': true,
        'state_at': '2026-11-04T10:00:00.000Z',
        'server_now': '2026-11-04T10:00:05.000Z',
        'max_members': 5,
        'members': [
          {'uid': 'u1', 'username': ' Ramdan ', 'avatar_url': '', 'active': true},
          {'uid': 'u2', 'username': null, 'active': false},
          {'uid': ''},
          'rusak',
        ],
      });
      expect(r.topic, 'nobar-a1b2');
      expect(r.isHost('u1'), isTrue);
      expect(r.isHost('u2'), isFalse);
      expect(r.members.length, 2);
      expect(r.members.first.username, 'Ramdan');
      expect(r.members.first.avatarUrl, isNull);
      expect(r.members.last.username, 'Pengguna Zenime');
      expect(r.members.last.active, isFalse);
      expect(r.stateAgeMs, 5000);
      expect(r.estimatedPositionMs, 65000);
    });

    test('video dijeda: posisi tidak ditambah umur status', () {
      final r = NobarRoom.fromJson({
        'id': 'x',
        'position_ms': 1000,
        'playing': false,
        'state_at': '2026-11-04T10:00:00Z',
        'server_now': '2026-11-04T10:01:00Z',
      });
      expect(r.estimatedPositionMs, 1000);
      expect(r.maxMembers, kNobarMaxMembers);
      expect(r.members, isEmpty);
    });
  });

  test('NobarIce.fromJson', () {
    final ice = NobarIce.fromJson({
      'ice_servers': [
        {'urls': ['turn:x:3478'], 'username': 'a', 'credential': 'b'},
        5,
      ],
      'turn_ready': true,
    });
    expect(ice.iceServers.length, 1);
    expect(ice.turnReady, isTrue);
  });
}
