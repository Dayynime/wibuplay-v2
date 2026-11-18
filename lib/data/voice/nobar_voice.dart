import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../models/nobar_models.dart';

/// Token LiveKit untuk masuk ke room voice.
class NobarVoiceToken {
  const NobarVoiceToken({required this.url, required this.token, required this.room});

  final String url;
  final String token;
  final String room;

  factory NobarVoiceToken.fromJson(Map<String, dynamic> j) => NobarVoiceToken(
        url: (j['url'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        room: (j['room'] ?? '').toString(),
      );

  bool get valid => url.isNotEmpty && token.isNotEmpty;
}

/// Status suara satu anggota room (selain aku).
class NobarPeerVoice {
  const NobarPeerVoice({
    required this.uid,
    this.connected = false,
    this.micOn = false,
    this.speaking = false,
    this.mutedByMe = false,
  });

  final String uid;

  /// Orang ini ada di room voice (tersambung ke server).
  final bool connected;

  /// Mic orang ini terbuka.
  final bool micOn;

  /// Sedang ngomong.
  final bool speaking;

  /// Aku membisukan orang ini (hanya di HP-ku).
  final bool mutedByMe;
}

/// Voice chat Nobar memakai LiveKit (SFU), maksimal 5 orang, audio saja.
///
/// Semua HP tersambung ke satu server LiveKit, bukan saling peer-to-peer.
/// Jauh lebih tahan di data seluler dibanding mesh WebRTC.
///
/// - Begitu masuk room, semua otomatis "dengar" (mic MATI, speaker ON).
/// - Mic dibuka/ditutup kapan saja ([toggleMic]).
/// - Tiap anggota bisa membisukan anggota lain di HP-nya sendiri
///   ([toggleMuteFor], [setMuteAll]) — volume orang itu di-nol-kan lokal.
/// - Host bisa mematikan mic anggota ([forceMute]) lewat pesan data; anggota
///   membukanya lagi sendiri.
///
/// Identitas tiap peserta di LiveKit = firebase uid, jadi [peer] bisa dicari
/// langsung dari uid.
class NobarVoice extends ChangeNotifier {
  NobarVoice({required this.myUid, required this.fetchToken});

  final String myUid;
  final Future<NobarVoiceToken> Function() fetchToken;

  static const double _speakLevel = 0.03;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;

  String _hostUid = '';
  bool _started = false;
  bool _starting = false;
  bool _disposed = false;

  bool _micOn = false;
  bool _micBusy = false;
  bool _speaker = true;
  bool _muteAll = false;
  bool _meSpeaking = false;
  String? _notice;

  final Set<String> _mutedByMe = <String>{};
  Set<String> _speaking = <String>{};
  Timer? _noticeTimer;

  // ================================================================ getter

  bool get started => _started;
  bool get micOn => _micOn;
  bool get micBusy => _micBusy;
  bool get speakerOn => _speaker;
  bool get muteAll => _muteAll;
  bool get meSpeaking => _meSpeaking;

  /// LiveKit punya TURN sendiri, jadi selalu dianggap siap.
  bool get turnReady => true;

  /// Pesan singkat (mis. "Host mematikan mic kamu"), hilang sendiri.
  String? get notice => _notice;

  lk.RemoteParticipant? _remote(String uid) {
    for (final p in _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[]) {
      if (p.identity == uid) return p;
    }
    return null;
  }

  NobarPeerVoice peer(String uid) {
    final p = _remote(uid);
    if (p == null) return NobarPeerVoice(uid: uid, mutedByMe: _mutedByMe.contains(uid));
    final mutedByMe = _muteAll || _mutedByMe.contains(uid);
    final micOn = _micEnabled(p);
    return NobarPeerVoice(
      uid: uid,
      connected: true,
      micOn: micOn,
      speaking: micOn && !mutedByMe && _speaking.contains(uid),
      mutedByMe: _mutedByMe.contains(uid),
    );
  }

  bool isMutedByMe(String uid) => _muteAll || _mutedByMe.contains(uid);

  /// Identity semua peserta lain yang sedang tersambung.
  List<String> get remoteIds =>
      _room?.remoteParticipants.values.map((p) => p.identity).toList() ?? const <String>[];

  // ================================================================ aksi

  /// Mulai voice (mode dengar). Aman dipanggil berkali-kali.
  Future<void> start() async {
    if (_started || _starting || _disposed) return;
    _starting = true;
    _notify();
    try {
      final tok = await fetchToken();
      if (_disposed) return;
      if (!tok.valid) {
        _starting = false;
        _showNotice('Voice belum siap, coba lagi');
        return;
      }

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: false,
          dynacast: false,
          // Kualitas suara ngobrol (bukan musik), hemat data.
          defaultAudioPublishOptions: lk.AudioPublishOptions(dtx: true),
        ),
      );
      final listener = room.createListener();
      _room = room;
      _listener = listener;
      _wire(listener);

      await room.connect(
        tok.url,
        tok.token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: true),
      );
      if (_disposed) {
        await room.disconnect();
        return;
      }

      _started = true;
      _starting = false;

      // Jangan rebut audio focus, supaya suara anime tetap jalan.
      try {
        await webrtc.Helper.setAndroidAudioConfiguration(_kVoiceAudio);
      } catch (_) {}
      await _applySpeaker();
      _applyAllMutes();
      _notify();
    } catch (e) {
      _starting = false;
      await _teardownRoom();
      _showNotice(_errorText(e));
      _notify();
    }
  }

  /// Host terbaru dari server (untuk izin [forceMute]).
  void setRoom(NobarRoom room) {
    _hostUid = room.hostUid;
    _notify();
  }

  Future<void> toggleMic() => setMic(!_micOn);

  Future<void> setMic(bool on) async {
    if (_micBusy || on == _micOn || !_started) return;
    final lp = _room?.localParticipant;
    if (lp == null) return;
    _micBusy = true;
    _notify();
    try {
      await lp.setMicrophoneEnabled(on);
      _micOn = on;
      if (!on) _meSpeaking = false;
      if (on) HapticFeedback.selectionClick();
    } catch (e) {
      _micOn = false;
      _showNotice(_errorText(e));
    } finally {
      _micBusy = false;
      _notify();
    }
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    _notify();
    await _applySpeaker();
  }

  /// Bisukan / bunyikan satu orang (hanya di HP-ku).
  void toggleMuteFor(String uid) {
    if (_mutedByMe.contains(uid)) {
      _mutedByMe.remove(uid);
    } else {
      _mutedByMe.add(uid);
    }
    _applyMuteFor(uid);
    _notify();
  }

  /// Bisukan semua orang lain (hanya di HP-ku).
  void setMuteAll(bool v) {
    _muteAll = v;
    _applyAllMutes();
    _notify();
  }

  /// Host: matikan mic satu anggota ([uid]) atau semua (null).
  void forceMute(String? uid) {
    if (_hostUid != myUid || _room == null) return;
    _sendData({'t': 'fmute', 'to': uid ?? '*'});
  }

  // ================================================================ LiveKit

  void _wire(lk.EventsListener<lk.RoomEvent> l) {
    l
      ..on<lk.ParticipantConnectedEvent>((_) {
        _applyAllMutes();
        _notify();
      })
      ..on<lk.ParticipantDisconnectedEvent>((_) => _notify())
      ..on<lk.TrackSubscribedEvent>((e) {
        _applyMuteFor(e.participant.identity);
        _notify();
      })
      ..on<lk.TrackUnsubscribedEvent>((_) => _notify())
      ..on<lk.TrackMutedEvent>((_) => _notify())
      ..on<lk.TrackUnmutedEvent>((_) => _notify())
      ..on<lk.ActiveSpeakersChangedEvent>((e) {
        _speaking = e.speakers.map((p) => p.identity).toSet();
        final me = _micOn && (_speaking.contains(myUid) || (_room?.localParticipant?.isSpeaking ?? false));
        if (me != _meSpeaking) _meSpeaking = me;
        _notify();
      })
      ..on<lk.DataReceivedEvent>((e) => _onData(e))
      ..on<lk.RoomReconnectingEvent>((_) {
        _showNotice('Menyambung ulang suara...');
      })
      ..on<lk.RoomReconnectedEvent>((_) {
        _showNotice(null);
        _applyAllMutes();
        unawaited(_applySpeaker());
      })
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (!_disposed && _started) _showNotice('Suara terputus');
      });
  }

  void _onData(lk.DataReceivedEvent e) {
    if (e.participant?.identity != _hostUid) return; // hanya host
    try {
      final msg = jsonDecode(utf8.decode(e.data)) as Map<String, dynamic>;
      if (msg['t'] != 'fmute') return;
      final to = msg['to'];
      if ((to == '*' || to == myUid) && _micOn) {
        unawaited(setMic(false));
        _showNotice('Host mematikan mic kamu');
      }
    } catch (_) {}
  }

  void _sendData(Map<String, dynamic> msg) {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    try {
      lp.publishData(utf8.encode(jsonEncode(msg)), reliable: true);
    } catch (_) {}
  }

  bool _micEnabled(lk.Participant p) {
    try {
      for (final pub in p.audioTrackPublications) {
        if (pub.source == lk.TrackSource.microphone && !pub.muted) return true;
      }
    } catch (_) {}
    return false;
  }

  void _applyAllMutes() {
    for (final p in _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[]) {
      _applyMuteFor(p.identity);
    }
  }

  void _applyMuteFor(String uid) {
    final p = _remote(uid);
    if (p == null) return;
    final muted = _muteAll || _mutedByMe.contains(uid);
    for (final pub in p.audioTrackPublications) {
      final track = pub.track;
      if (track is lk.RemoteAudioTrack) {
        // livekit_client 2.13 tidak punya RemoteAudioTrack.setVolume;
        // atur volume lewat flutter_webrtc (dipakai LiveKit di dalamnya).
        try {
          unawaited(webrtc.Helper.setVolume(muted ? 0 : 1.0, track.mediaStreamTrack));
        } catch (_) {}
      }
    }
  }

  Future<void> _applySpeaker() async {
    // LiveKit memakai flutter_webrtc di dalamnya, jadi Helper yang sama bekerja.
    try {
      await webrtc.Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
  }

  // ================================================================ bantu

  Future<void> _teardownRoom() async {
    final room = _room;
    final listener = _listener;
    _room = null;
    _listener = null;
    _started = false;
    _micOn = false;
    _meSpeaking = false;
    _speaking = <String>{};
    try {
      await listener?.dispose();
    } catch (_) {}
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
  }

  String _errorText(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('permission') || s.contains('notallowed') || s.contains('denied')) {
      return 'Izin mikrofon ditolak. Aktifkan di Setelan > Aplikasi > Zenime > Izin.';
    }
    return 'Suara gagal tersambung, coba lagi';
  }

  void _showNotice(String? text) {
    _noticeTimer?.cancel();
    _notice = text;
    if (text != null) {
      _noticeTimer = Timer(const Duration(seconds: 4), () {
        _notice = null;
        _notify();
      });
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _noticeTimer?.cancel();
    unawaited(() async {
      await _teardownRoom();
      try {
        await webrtc.Helper.setSpeakerphoneOn(false);
        await webrtc.Helper.setAndroidAudioConfiguration(_kNormalAudio);
      } catch (_) {}
    }());
    super.dispose();
  }
}

/// Mode komunikasi tanpa merebut audio focus (video tetap bersuara).
final webrtc.AndroidAudioConfiguration _kVoiceAudio = webrtc.AndroidAudioConfiguration(
  manageAudioFocus: false,
  androidAudioMode: webrtc.AndroidAudioMode.inCommunication,
  androidAudioStreamType: webrtc.AndroidAudioStreamType.voiceCall,
  androidAudioAttributesUsageType: webrtc.AndroidAudioAttributesUsageType.voiceCommunication,
  androidAudioAttributesContentType: webrtc.AndroidAudioAttributesContentType.speech,
);

final webrtc.AndroidAudioConfiguration _kNormalAudio = webrtc.AndroidAudioConfiguration(
  manageAudioFocus: false,
  androidAudioMode: webrtc.AndroidAudioMode.normal,
  androidAudioStreamType: webrtc.AndroidAudioStreamType.music,
  androidAudioAttributesUsageType: webrtc.AndroidAudioAttributesUsageType.media,
  androidAudioAttributesContentType: webrtc.AndroidAudioAttributesContentType.unknown,
);
