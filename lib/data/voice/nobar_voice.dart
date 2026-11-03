import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/nobar_models.dart';
import '../realtime/chess_realtime_client.dart';

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

  /// Jalur suara ke orang ini sudah tersambung.
  final bool connected;

  /// Mic orang ini terbuka (laporan dari HP-nya).
  final bool micOn;

  /// Sedang ngomong (level suara yang masuk ke HP-ku).
  final bool speaking;

  /// Aku membisukan orang ini (cuma di HP-ku, dia tidak tahu).
  final bool mutedByMe;
}

/// Voice chat Nobar ala Mobile Legends, maksimal 5 orang (WebRTC mesh, audio).
///
/// - Begitu masuk room, semua otomatis "dengar" (speaker on, mic MATI).
/// - Mic dibuka/ditutup kapan saja tanpa sambung ulang ([toggleMic]).
/// - Tiap anggota bisa membisukan anggota lain di HP-nya sendiri ([toggleMuteFor],
///   [setMuteAll]).
/// - Host bisa mematikan mic anggota ([forceMute]); anggota bisa membukanya lagi.
///
/// Tiap pasangan anggota punya satu RTCPeerConnection. Yang uid-nya lebih
/// kecil selalu membuat offer, jadi tidak pernah tabrakan. Sinyal (hello,
/// offer, answer, ice, mic) dikirim lewat Realtime Broadcast topik room,
/// event `voice`. Pesan hanya diterima dari uid yang terdaftar sebagai anggota
/// room menurut server ([setRoom]).
class NobarVoice extends ChangeNotifier {
  NobarVoice({
    required this.myUid,
    required this.rt,
    required this.fetchIce,
  }) : _sess = _randomId() {
    _sub = rt.messages.where((m) => m.event == 'voice').listen(_onMessage);
  }

  final String myUid;
  final ChessRealtimeClient rt;
  final Future<NobarIce> Function() fetchIce;

  /// Id sesi suaraku; berganti tiap kali voice dimulai ulang supaya HP lain
  /// tahu harus menyambung ulang.
  String _sess;

  static const Duration _helloEvery = Duration(seconds: 8);
  static const Duration _reconnectGrace = Duration(seconds: 8);
  static const double _speakLevel = 0.035;

  final Map<String, _Peer> _peers = <String, _Peer>{};
  Set<String> _members = <String>{};
  String _hostUid = '';

  List<Map<String, dynamic>> _iceServers = const [];
  bool _turnReady = true;
  bool _started = false;
  bool _starting = false;
  bool _disposed = false;

  bool _micOn = false;
  bool _micBusy = false;
  bool _speaker = true;
  bool _muteAll = false;
  bool _meSpeaking = false;
  String? _notice;

  MediaStream? _local;
  StreamSubscription<ChessRtMessage>? _sub;
  Timer? _hello;
  Timer? _levels;
  Timer? _noticeTimer;

  // ================================================================ getter

  bool get started => _started;
  bool get micOn => _micOn;
  bool get micBusy => _micBusy;
  bool get speakerOn => _speaker;
  bool get muteAll => _muteAll;
  bool get meSpeaking => _meSpeaking;
  bool get turnReady => _turnReady;

  /// Pesan singkat (mis. "Host mematikan mic kamu"), hilang sendiri.
  String? get notice => _notice;

  NobarPeerVoice peer(String uid) {
    final p = _peers[uid];
    if (p == null) return NobarPeerVoice(uid: uid);
    return NobarPeerVoice(
      uid: uid,
      connected: p.connected,
      micOn: p.remoteMic,
      speaking: p.speaking && !p.mutedByMe,
      mutedByMe: p.mutedByMe,
    );
  }

  // ================================================================ aksi

  /// Mulai voice (mode dengar). Aman dipanggil berkali-kali.
  Future<void> start() async {
    if (_started || _starting || _disposed) return;
    _starting = true;
    try {
      final ice = await fetchIce();
      _turnReady = ice.turnReady;
      _iceServers = <Map<String, dynamic>>[
        ...ice.iceServers,
        {
          'urls': ['stun:stun.l.google.com:19302'],
        },
      ];
    } catch (_) {
      // Tanpa TURN pun tetap dicoba (cukup untuk WiFi yang sama / NAT ringan).
      _turnReady = false;
      _iceServers = const [
        {
          'urls': ['stun:stun.l.google.com:19302'],
        },
      ];
    }
    _starting = false;
    if (_disposed) return;
    _started = true;

    // Mode komunikasi supaya echo cancellation HP aktif. Audio focus TIDAK
    // diambil, supaya suara video tetap jalan.
    try {
      await Helper.setAndroidAudioConfiguration(_kVoiceAudio);
    } catch (_) {}
    await _applySpeaker();

    _sendHello();
    _hello = Timer.periodic(_helloEvery, (_) => _sendHello());
    _levels = Timer.periodic(const Duration(milliseconds: 450), (_) => _pollLevels());
    _notify();
  }

  /// Daftar anggota & host terbaru dari server. Sambungan ke orang yang
  /// sudah keluar ditutup.
  void setRoom(NobarRoom room) {
    _hostUid = room.hostUid;
    final next = room.members.map((m) => m.uid).where((u) => u != myUid).toSet();
    final added = next.difference(_members);
    _members = next;
    for (final uid in _peers.keys.toList()) {
      if (!_members.contains(uid)) _closePeer(uid);
    }
    // Anggota baru: sapa langsung, tidak perlu menunggu hello berkala.
    for (final uid in added) {
      _sendHello(uid);
    }
    _notify();
  }

  Future<void> toggleMic() => setMic(!_micOn);

  Future<void> setMic(bool on) async {
    if (_micBusy || on == _micOn || !_started) return;
    _micBusy = true;
    _notify();
    try {
      if (on) {
        final local = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
          'audio': <String, dynamic>{
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        });
        if (_disposed) {
          await _stopStream(local);
          return;
        }
        _local = local;
        final track = _micTrack;
        for (final p in _peers.values) {
          await p.attachMic(track);
        }
        _micOn = true;
        HapticFeedback.selectionClick();
      } else {
        await _releaseMic();
      }
      _broadcastMic();
    } catch (e) {
      await _releaseMic();
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
    final p = _peers[uid];
    if (p == null) return;
    p.mutedByMe = !p.mutedByMe;
    p.applyMute(_muteAll);
    _notify();
  }

  /// Bisukan semua orang lain (hanya di HP-ku), seperti tombol speaker ML.
  void setMuteAll(bool v) {
    _muteAll = v;
    for (final p in _peers.values) {
      p.applyMute(_muteAll);
    }
    _notify();
  }

  bool isMutedByMe(String uid) => _muteAll || (_peers[uid]?.mutedByMe ?? false);

  /// Host: matikan mic satu anggota ([uid]) atau semua (null).
  void forceMute(String? uid) {
    if (_hostUid != myUid) return;
    _send(uid ?? '*', 'force_mute');
  }

  // ================================================================ sinyal

  void _sendHello([String to = '*']) {
    if (!_started) return;
    _send(to, 'hello', {'mic': _micOn});
  }

  void _broadcastMic() => _send('*', 'mic', {'mic': _micOn});

  bool _send(String to, String type, [Map<String, dynamic> extra = const {}]) {
    return rt.send('voice', <String, dynamic>{
      'from': myUid,
      'to': to,
      'sess': _sess,
      'type': type,
      ...extra,
    });
  }

  Future<void> _onMessage(ChessRtMessage m) async {
    if (_disposed || !_started) return;
    final p = m.payload;
    final from = p['from'];
    final to = p['to'];
    final type = p['type'];
    final sess = p['sess'];
    if (from is! String || from == myUid || !_members.contains(from)) return;
    if (to != '*' && to != myUid) return;
    if (type is! String || sess is! String || sess.isEmpty || sess.length > 64) return;

    switch (type) {
      case 'hello':
        await _onHello(from, sess, p['mic'] == true);
      case 'mic':
        final peer = _peers[from];
        if (peer != null && peer.rsess == sess) {
          peer.remoteMic = p['mic'] == true;
          if (!peer.remoteMic) peer.speaking = false;
          _notify();
        }
      case 'offer':
        await _onOffer(from, sess, p);
      case 'answer':
        await _onAnswer(from, sess, p);
      case 'ice':
        await _onIce(from, sess, p);
      case 'bye':
        if (_peers[from]?.rsess == sess) _closePeer(from);
      case 'force_mute':
        if (from == _hostUid && _micOn) {
          await setMic(false);
          _showNotice('Host mematikan mic kamu');
          _notify();
        }
    }
  }

  Future<void> _onHello(String from, String sess, bool mic) async {
    var peer = _peers[from];
    if (peer == null || peer.rsess != sess) {
      if (peer != null) _closePeer(from, notify: false);
      peer = _Peer(uid: from, rsess: sess);
      _peers[from] = peer;
      peer.remoteMic = mic;
      if (_iAmOfferer(from)) {
        await _makeOffer(peer);
      } else {
        // Pastikan dia kenal sesiku, supaya dia yang membuat offer. Tidak
        // berulang: di sisinya sesiku sudah dikenal, jadi dia tidak membalas.
        _sendHello(from);
      }
    } else {
      peer.remoteMic = mic;
      // Dia belum tersambung tapi aku pembuat offer dan offer belum jalan
      // (mis. gagal kirim): coba lagi.
      if (_iAmOfferer(from) && peer.pc == null) await _makeOffer(peer);
    }
    _notify();
  }

  bool _iAmOfferer(String other) => myUid.compareTo(other) < 0;

  Future<void> _makeOffer(_Peer peer) async {
    if (peer.offering) return;
    peer.offering = true;
    try {
      final pc = await _createPc(peer);
      final tr = await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
      peer.sender = tr.sender;
      await peer.attachMic(_micTrack);
      final offer = await pc.createOffer(<String, dynamic>{'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      _send(peer.uid, 'offer', {'rsess': peer.rsess, 'sdp': offer.sdp});
    } catch (_) {
      _closePeer(peer.uid);
    }
  }

  Future<void> _onOffer(String from, String sess, Map<String, dynamic> p) async {
    final sdp = p['sdp'];
    if (p['rsess'] != _sess || sdp is! String || _iAmOfferer(from)) return;
    var peer = _peers[from];
    if (peer == null || peer.rsess != sess || peer.pc != null) {
      // Sesi baru atau sambung ulang: mulai dari koneksi bersih.
      final mic = peer?.remoteMic ?? false;
      final muted = peer?.mutedByMe ?? false;
      if (peer != null) _closePeer(from, notify: false);
      peer = _Peer(uid: from, rsess: sess)
        ..remoteMic = mic
        ..mutedByMe = muted;
      _peers[from] = peer;
    }
    try {
      final pc = await _createPc(peer);
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      peer.remoteSet = true;
      final trs = await pc.getTransceivers();
      for (final t in trs) {
        if (t.receiver.track?.kind == 'audio' || trs.length == 1) {
          await t.setDirection(TransceiverDirection.SendRecv);
          peer.sender = t.sender;
          break;
        }
      }
      await peer.attachMic(_micTrack);
      await peer.drain();
      final answer = await pc.createAnswer(<String, dynamic>{});
      await pc.setLocalDescription(answer);
      _send(from, 'answer', {'rsess': sess, 'sdp': answer.sdp});
    } catch (_) {
      _closePeer(from);
    }
  }

  Future<void> _onAnswer(String from, String sess, Map<String, dynamic> p) async {
    final peer = _peers[from];
    final sdp = p['sdp'];
    if (peer == null || peer.rsess != sess || p['rsess'] != _sess || sdp is! String) return;
    final pc = peer.pc;
    if (pc == null || peer.remoteSet) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      peer.remoteSet = true;
      await peer.drain();
    } catch (_) {
      _closePeer(from);
    }
  }

  Future<void> _onIce(String from, String sess, Map<String, dynamic> p) async {
    if (p['rsess'] != _sess) return;
    var peer = _peers[from];
    if ((peer == null || peer.rsess != sess) && !_iAmOfferer(from)) {
      // ICE dari pembuat offer bisa tiba duluan sebelum offer-nya: simpan dulu.
      final muted = peer?.mutedByMe ?? false;
      if (peer != null) _closePeer(from, notify: false);
      peer = _Peer(uid: from, rsess: sess)..mutedByMe = muted;
      _peers[from] = peer;
    }
    if (peer == null || peer.rsess != sess) return;
    final cand = p['candidate'];
    if (cand is! String || cand.isEmpty || cand.length > 1000) return;
    final mid = p['sdpMid'];
    final idx = p['sdpMLineIndex'];
    await peer.addCandidate(
      RTCIceCandidate(cand, mid is String ? mid : null, idx is num ? idx.toInt() : null),
    );
  }

  // ================================================================ WebRTC

  Future<RTCPeerConnection> _createPc(_Peer peer) async {
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });
    peer.pc = pc;
    pc.onIceCandidate = (c) {
      final cand = c.candidate;
      if (cand == null || cand.isEmpty) return;
      _send(peer.uid, 'ice', {
        'rsess': peer.rsess,
        'candidate': cand,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onTrack = (e) {
      if (e.track.kind != 'audio') return;
      peer.remoteTrack = e.track;
      peer.applyMute(_muteAll);
    };
    pc.onConnectionState = (s) => _onConnState(peer, s);
    return pc;
  }

  void _onConnState(_Peer peer, RTCPeerConnectionState s) {
    if (_disposed || _peers[peer.uid] != peer) return;
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        peer.lostTimer?.cancel();
        if (!peer.connected) {
          peer.connected = true;
          // Sebagian HP mengembalikan suara ke earpiece begitu audio masuk.
          unawaited(_applySpeaker());
          Future<void>.delayed(const Duration(milliseconds: 1200), () {
            if (!_disposed) unawaited(_applySpeaker());
          });
          _notify();
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        peer.lostTimer?.cancel();
        peer.lostTimer = Timer(_reconnectGrace, () {
          if (_peers[peer.uid] == peer) _resetPeer(peer.uid);
        });
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _resetPeer(peer.uid);
        if (!_turnReady) _showNotice('Sebagian suara gagal tersambung (server TURN belum aktif)');
      default:
        break;
    }
  }

  /// Koneksi ke [uid] putus: buang, lalu sambung ulang lewat hello berikutnya.
  void _resetPeer(String uid) {
    final muted = _peers[uid]?.mutedByMe ?? false;
    _closePeer(uid, notify: false);
    if (muted) _pendingMuted.add(uid);
    // Kirim hello langsung supaya pembuat offer segera menyambung ulang.
    _sendHello(uid);
    _notify();
  }

  /// Pilihan "bisukan" yang harus dipasang lagi setelah sambung ulang.
  final Set<String> _pendingMuted = <String>{};

  void _closePeer(String uid, {bool notify = true}) {
    final p = _peers.remove(uid);
    if (p == null) return;
    p.dispose();
    if (notify) _notify();
  }

  Future<void> _pollLevels() async {
    if (_disposed) return;
    var changed = false;
    // Pasang lagi pilihan bisukan setelah sambung ulang.
    if (_pendingMuted.isNotEmpty) {
      for (final uid in _pendingMuted.toList()) {
        final p = _peers[uid];
        if (p != null) {
          p.mutedByMe = true;
          p.applyMute(_muteAll);
          _pendingMuted.remove(uid);
          changed = true;
        }
      }
    }
    for (final p in _peers.values.toList()) {
      final pc = p.pc;
      if (pc == null || !p.connected) continue;
      var level = 0.0;
      try {
        final stats = await pc.getStats();
        for (final r in stats) {
          if (r.type != 'inbound-rtp') continue;
          final v = r.values;
          if (v['kind'] != 'audio' && v['mediaType'] != 'audio') continue;
          final l = v['audioLevel'];
          if (l is num) level = math.max(level, l.toDouble());
        }
      } catch (_) {}
      final speaking = p.remoteMic && level > _speakLevel;
      if (speaking != p.speaking) {
        p.speaking = speaking;
        changed = true;
      }
    }
    var me = false;
    final pc0 = _peers.values.map((p) => p.pc).whereType<RTCPeerConnection>().firstOrNull;
    if (_micOn && pc0 != null) {
      try {
        final stats = await pc0.getStats();
        for (final r in stats) {
          if (r.type != 'media-source') continue;
          final l = r.values['audioLevel'];
          if (l is num && l.toDouble() > _speakLevel) me = true;
        }
      } catch (_) {}
    }
    if (me != _meSpeaking) {
      _meSpeaking = me;
      changed = true;
    }
    if (changed) _notify();
  }

  // ================================================================ bantu

  MediaStreamTrack? get _micTrack {
    final l = _local;
    if (l == null) return null;
    final list = l.getAudioTracks();
    return list.isEmpty ? null : list.first;
  }

  Future<void> _releaseMic() async {
    final local = _local;
    _local = null;
    _micOn = false;
    _meSpeaking = false;
    for (final p in _peers.values) {
      await p.attachMic(null);
    }
    if (local != null) await _stopStream(local);
  }

  static Future<void> _stopStream(MediaStream s) async {
    try {
      for (final t in s.getTracks()) {
        await t.stop();
      }
      await s.dispose();
    } catch (_) {}
  }

  Future<void> _applySpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
  }

  String _errorText(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('permission') || s.contains('notallowed') || s.contains('denied')) {
      return 'Izin mikrofon ditolak. Aktifkan di Setelan > Aplikasi > Zenime > Izin.';
    }
    return 'Mic gagal dibuka';
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

  static String _randomId() {
    final r = math.Random.secure();
    return List<String>.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_started) _send('*', 'bye');
    _disposed = true;
    _hello?.cancel();
    _levels?.cancel();
    _noticeTimer?.cancel();
    _sub?.cancel();
    for (final p in _peers.values) {
      p.dispose();
    }
    _peers.clear();
    final local = _local;
    _local = null;
    if (local != null) unawaited(_stopStream(local));
    if (_started) {
      unawaited(() async {
        try {
          await Helper.setSpeakerphoneOn(false);
          await Helper.setAndroidAudioConfiguration(_kNormalAudio);
        } catch (_) {}
      }());
    }
    super.dispose();
  }
}

/// Mode komunikasi tanpa merebut audio focus (video tetap bersuara).
final AndroidAudioConfiguration _kVoiceAudio = AndroidAudioConfiguration(
  manageAudioFocus: false,
  androidAudioMode: AndroidAudioMode.inCommunication,
  androidAudioStreamType: AndroidAudioStreamType.voiceCall,
  androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.voiceCommunication,
  androidAudioAttributesContentType: AndroidAudioAttributesContentType.speech,
);

final AndroidAudioConfiguration _kNormalAudio = AndroidAudioConfiguration(
  manageAudioFocus: false,
  androidAudioMode: AndroidAudioMode.normal,
  androidAudioStreamType: AndroidAudioStreamType.music,
  androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
  androidAudioAttributesContentType: AndroidAudioAttributesContentType.unknown,
);

/// Satu sambungan suara ke satu anggota lain.
class _Peer {
  _Peer({required this.uid, required this.rsess});

  final String uid;

  /// Id sesi suara milik dia (lihat NobarVoice._sess).
  final String rsess;

  RTCPeerConnection? pc;
  RTCRtpSender? sender;
  MediaStreamTrack? remoteTrack;
  bool remoteSet = false;
  bool offering = false;
  bool connected = false;
  bool remoteMic = false;
  bool speaking = false;
  bool mutedByMe = false;
  Timer? lostTimer;
  final List<RTCIceCandidate> _pending = <RTCIceCandidate>[];

  Future<void> attachMic(MediaStreamTrack? track) async {
    final s = sender;
    if (s == null) return;
    try {
      await s.replaceTrack(track);
    } catch (_) {}
  }

  void applyMute(bool muteAll) {
    final t = remoteTrack;
    if (t == null) return;
    try {
      t.enabled = !(muteAll || mutedByMe);
    } catch (_) {}
  }

  Future<void> addCandidate(RTCIceCandidate c) async {
    final p = pc;
    if (p != null && remoteSet) {
      try {
        await p.addCandidate(c);
      } catch (_) {}
    } else if (_pending.length < 60) {
      _pending.add(c);
    }
  }

  Future<void> drain() async {
    final p = pc;
    if (p == null) return;
    final list = List<RTCIceCandidate>.of(_pending);
    _pending.clear();
    for (final c in list) {
      try {
        await p.addCandidate(c);
      } catch (_) {}
    }
  }

  void dispose() {
    lostTimer?.cancel();
    final p = pc;
    pc = null;
    sender = null;
    remoteTrack = null;
    if (p != null) {
      unawaited(() async {
        try {
          await p.close();
          await p.dispose();
        } catch (_) {}
      }());
    }
  }
}
