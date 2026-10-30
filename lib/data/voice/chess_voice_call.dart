import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/chess_models.dart';
import '../realtime/chess_realtime_client.dart';

/// Status panggilan suara di layar catur.
enum ChessVoiceState {
  /// Tidak ada panggilan.
  idle,

  /// Aku menelepon, menunggu lawan mengangkat.
  outgoing,

  /// Lawan menelepon, menunggu aku angkat / tolak.
  incoming,

  /// Sudah diangkat, sedang menyambungkan suara.
  connecting,

  /// Tersambung, bisa ngobrol.
  connected,
}

/// Panggilan suara 1 lawan 1 di permainan catur (WebRTC, audio saja).
///
/// Suara mengalir langsung antar-HP (atau lewat server TURN kalau jaringan
/// tidak memungkinkan). Sinyal panggilan (undang, angkat, SDP, ICE) dikirim
/// lewat Realtime Broadcast di topik permainan, event `voice`. Pesan hanya
/// diterima kalau `from` = lawan dan `to` = aku; topiknya memakai id
/// permainan (UUID acak) yang cuma diketahui kedua pemain.
///
/// Mic hanya hidup selama panggilan berlangsung, dan panggilan otomatis
/// ditutup saat layar catur ditutup.
class ChessVoiceCall extends ChangeNotifier {
  ChessVoiceCall({
    required this.myUid,
    required this.opponentUid,
    required this.rt,
    required this.fetchIce,
  }) {
    _sub = rt.messages.where((m) => m.event == 'voice').listen(_onMessage);
  }

  final String myUid;
  final String opponentUid;
  final ChessRealtimeClient rt;
  final Future<ChessVoiceIce> Function() fetchIce;

  static const Duration _ringTimeout = Duration(seconds: 30);
  static const Duration _reconnectGrace = Duration(seconds: 10);

  ChessVoiceState _state = ChessVoiceState.idle;
  bool _muted = false;
  bool _speaker = true;
  bool _remoteMuted = false;
  String? _notice;
  DateTime? _connectedAt;
  bool _turnReady = true;

  String? _callId;
  RTCPeerConnection? _pc;
  MediaStream? _local;
  final List<RTCIceCandidate> _pendingRemote = <RTCIceCandidate>[];
  bool _remoteSet = false;

  StreamSubscription<ChessRtMessage>? _sub;
  Timer? _ringTimer;
  Timer? _reinvite;
  Timer? _disconnectTimer;
  Timer? _noticeTimer;
  Timer? _vibe;
  bool _disposed = false;

  ChessVoiceState get state => _state;
  bool get muted => _muted;
  bool get speakerOn => _speaker;
  bool get remoteMuted => _remoteMuted;

  /// Pesan singkat (mis. "Lawan menolak panggilan"), hilang sendiri.
  String? get notice => _notice;
  DateTime? get connectedAt => _connectedAt;
  bool get isBusy => _state != ChessVoiceState.idle;

  // ================================================================ aksi

  /// Telepon lawan.
  Future<void> start() async {
    if (_state != ChessVoiceState.idle) return;
    _callId = _newCallId();
    _setState(ChessVoiceState.outgoing);
    try {
      await _prepare();
    } catch (e) {
      _end(_errorText(e));
      return;
    }
    if (_state != ChessVoiceState.outgoing) return; // dibatalkan saat menyiapkan
    if (!_send('invite')) {
      _end('Belum tersambung ke server. Coba lagi sebentar.');
      return;
    }
    // Kirim ulang undangan berkala: lawan yang baru membuka layar catur tetap
    // menerima dering selama masih dalam batas waktu.
    _reinvite = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_state == ChessVoiceState.outgoing) _send('invite');
    });
    _ringTimer = Timer(_ringTimeout, () {
      if (_state == ChessVoiceState.outgoing) {
        _send('cancel');
        _end('Lawan tidak menjawab');
      }
    });
  }

  /// Angkat panggilan masuk.
  Future<void> accept() async {
    if (_state != ChessVoiceState.incoming) return;
    await _answerCall();
  }

  /// Tolak panggilan masuk.
  void decline() {
    if (_state != ChessVoiceState.incoming) return;
    _send('decline');
    _end(null);
  }

  /// Tutup / batalkan panggilan.
  void hangUp() {
    switch (_state) {
      case ChessVoiceState.idle:
        return;
      case ChessVoiceState.incoming:
        decline();
        return;
      case ChessVoiceState.outgoing:
        _send('cancel');
        _end(null);
        return;
      case ChessVoiceState.connecting:
      case ChessVoiceState.connected:
        _send('bye');
        _end('Panggilan selesai');
        return;
    }
  }

  void toggleMute() {
    final local = _local;
    if (local == null) return;
    _muted = !_muted;
    for (final t in local.getAudioTracks()) {
      t.enabled = !_muted;
    }
    _send('mute', {'muted': _muted});
    _notify();
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    _notify();
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
  }

  // ================================================================ WebRTC

  Future<void> _prepare() async {
    if (_pc != null) return;
    final ice = await fetchIce();
    _turnReady = ice.turnReady;
    final servers = <Map<String, dynamic>>[
      ...ice.iceServers,
      // Cadangan STUN publik (dipakai HP, bukan server).
      {
        'urls': ['stun:stun.l.google.com:19302'],
      },
    ];

    final local = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    if (_disposed || _state == ChessVoiceState.idle) {
      // Dibatalkan saat minta izin mic.
      for (final t in local.getTracks()) {
        await t.stop();
      }
      await local.dispose();
      throw const _Cancelled();
    }
    _local = local;

    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;
    for (final t in local.getAudioTracks()) {
      await pc.addTrack(t, local);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      _send('ice', {
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onConnectionState = _onConnectionState;

    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
  }

  /// Sisi yang mengangkat membuat offer; sisi penelepon menjawab.
  Future<void> _answerCall() async {
    _stopRinging();
    _setState(ChessVoiceState.connecting);
    try {
      await _prepare();
    } catch (e) {
      if (e is! _Cancelled) _send('decline');
      _end(_errorText(e));
      return;
    }
    if (_state != ChessVoiceState.connecting) return;
    _send('accept');
    try {
      final pc = _pc!;
      final offer = await pc.createOffer(<String, dynamic>{'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      _send('offer', {'sdp': offer.sdp});
    } catch (e) {
      _send('bye');
      _end('Gagal memulai panggilan');
    }
  }

  void _onConnectionState(RTCPeerConnectionState s) {
    if (_disposed) return;
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _disconnectTimer?.cancel();
        if (_state != ChessVoiceState.connected) {
          _connectedAt ??= DateTime.now();
          HapticFeedback.mediumImpact();
          _setState(ChessVoiceState.connected);
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // Jaringan goyang sebentar: tunggu dulu sebelum menutup.
        _disconnectTimer?.cancel();
        _disconnectTimer = Timer(_reconnectGrace, () {
          if (_state == ChessVoiceState.connected || _state == ChessVoiceState.connecting) {
            _send('bye');
            _end('Sambungan suara terputus');
          }
        });
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _send('bye');
        _end(_turnReady
            ? 'Sambungan suara gagal. Coba lagi.'
            : 'Sambungan suara gagal. Server panggilan belum aktif.');
      default:
        break;
    }
  }

  Future<void> _drainCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    final list = List<RTCIceCandidate>.of(_pendingRemote);
    _pendingRemote.clear();
    for (final c in list) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  // ================================================================ sinyal

  bool _send(String type, [Map<String, dynamic> extra = const {}]) {
    final call = _callId;
    if (call == null) return false;
    return rt.send('voice', <String, dynamic>{
      'from': myUid,
      'to': opponentUid,
      'call': call,
      'type': type,
      ...extra,
    });
  }

  Future<void> _onMessage(ChessRtMessage m) async {
    if (_disposed) return;
    final p = m.payload;
    if (p['from'] != opponentUid || p['to'] != myUid) return;
    final call = p['call'];
    final type = p['type'];
    if (call is! String || call.isEmpty || call.length > 64 || type is! String) return;

    if (type == 'invite') {
      switch (_state) {
        case ChessVoiceState.idle:
          _callId = call;
          _setState(ChessVoiceState.incoming);
          _startRinging();
          return;
        case ChessVoiceState.outgoing:
          if (call == _callId) return;
          // Saling menelepon bersamaan: yang uid-nya lebih kecil mengangkat
          // panggilan lawan, yang lain menunggu.
          if (myUid.compareTo(opponentUid) < 0) {
            _reinvite?.cancel();
            _ringTimer?.cancel();
            _callId = call;
            _setState(ChessVoiceState.incoming);
            await _answerCall();
          }
          return;
        default:
          return; // undangan ulang dari panggilan yang sama, abaikan
      }
    }

    if (call != _callId) return;
    final pc = _pc;

    switch (type) {
      case 'cancel':
        if (_state == ChessVoiceState.incoming) _end('Panggilan tak terjawab');
      case 'decline':
        if (_state == ChessVoiceState.outgoing) _end('Lawan menolak panggilan');
      case 'bye':
        if (_state != ChessVoiceState.idle) _end('Lawan menutup panggilan');
      case 'accept':
        if (_state == ChessVoiceState.outgoing) {
          _reinvite?.cancel();
          _ringTimer?.cancel();
          _setState(ChessVoiceState.connecting);
        }
      case 'offer':
        await _onOffer(pc, p['sdp']);
      case 'answer':
        await _onAnswer(pc, p['sdp']);
      case 'ice':
        await _onIce(pc, p);
      case 'mute':
        _remoteMuted = p['muted'] == true;
        _notify();
    }
  }

  Future<void> _onOffer(RTCPeerConnection? pc, Object? sdp) async {
    if (pc == null || sdp is! String || _state != ChessVoiceState.connecting) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _remoteSet = true;
      await _drainCandidates();
      final answer = await pc.createAnswer(<String, dynamic>{});
      await pc.setLocalDescription(answer);
      _send('answer', {'sdp': answer.sdp});
    } catch (_) {
      _send('bye');
      _end('Gagal menyambungkan suara');
    }
  }

  Future<void> _onAnswer(RTCPeerConnection? pc, Object? sdp) async {
    if (pc == null || sdp is! String || _remoteSet) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      _remoteSet = true;
      await _drainCandidates();
    } catch (_) {
      _send('bye');
      _end('Gagal menyambungkan suara');
    }
  }

  Future<void> _onIce(RTCPeerConnection? pc, Map<String, dynamic> p) async {
    final cand = p['candidate'];
    if (cand is! String || cand.isEmpty || cand.length > 1000) return;
    final mid = p['sdpMid'];
    final idx = p['sdpMLineIndex'];
    final c = RTCIceCandidate(cand, mid is String ? mid : null, idx is num ? idx.toInt() : null);
    if (pc != null && _remoteSet) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    } else if (_pendingRemote.length < 50) {
      _pendingRemote.add(c);
    }
  }

  // ================================================================ bantu

  void _startRinging() {
    _ringTimer?.cancel();
    _ringTimer = Timer(_ringTimeout, () {
      if (_state == ChessVoiceState.incoming) _end('Panggilan tak terjawab');
    });
    _vibe?.cancel();
    HapticFeedback.heavyImpact();
    var n = 0;
    _vibe = Timer.periodic(const Duration(milliseconds: 1200), (t) {
      if (_state != ChessVoiceState.incoming || ++n > 20) {
        t.cancel();
        return;
      }
      HapticFeedback.heavyImpact();
    });
  }

  void _stopRinging() {
    _ringTimer?.cancel();
    _vibe?.cancel();
  }

  String _newCallId() {
    final r = math.Random.secure();
    return List<String>.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  String? _errorText(Object e) {
    if (e is _Cancelled) return null;
    final s = e.toString().toLowerCase();
    if (s.contains('permission') || s.contains('notallowed') || s.contains('denied')) {
      return 'Izin mikrofon ditolak. Aktifkan di Setelan > Aplikasi > Zenime > Izin.';
    }
    final msg = e.toString().replaceFirst('Exception: ', '').trim();
    return msg.isEmpty || msg.length > 120 ? 'Panggilan suara gagal dimulai' : msg;
  }

  void _setState(ChessVoiceState s) {
    _state = s;
    _notify();
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
  }

  /// Tutup semua sumber daya panggilan dan kembali ke idle.
  void _end(String? notice) {
    _stopRinging();
    _reinvite?.cancel();
    _disconnectTimer?.cancel();
    final pc = _pc;
    final local = _local;
    _pc = null;
    _local = null;
    _pendingRemote.clear();
    _remoteSet = false;
    _callId = null;
    _muted = false;
    _remoteMuted = false;
    _connectedAt = null;
    _state = ChessVoiceState.idle;
    _showNotice(notice);
    _notify();
    unawaited(() async {
      try {
        if (local != null) {
          for (final t in local.getTracks()) {
            await t.stop();
          }
          await local.dispose();
        }
        await pc?.close();
        await pc?.dispose();
      } catch (_) {}
    }());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_state != ChessVoiceState.idle) {
      if (_state == ChessVoiceState.incoming) {
        _send('decline');
      } else if (_state == ChessVoiceState.outgoing) {
        _send('cancel');
      } else {
        _send('bye');
      }
    }
    _disposed = true;
    _end(null);
    _noticeTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
