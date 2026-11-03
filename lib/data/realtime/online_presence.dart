import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/supabase_config.dart';

/// Siapa saja yang sedang membuka Zenime, real-time lewat Supabase Realtime
/// Presence (protokol Phoenix, sama dengan ChatRealtimeClient).
///
/// Satu koneksi per app selama user login & app di foreground (dinyalakan /
/// dimatikan oleh BanWatcher). Server mengirim `presence_state` saat join
/// lalu `presence_diff` setiap ada yang masuk / keluar, jadi daftar online
/// & jumlahnya berubah seketika tanpa polling.
///
/// Catatan: kunci presence diumumkan oleh app sendiri (login Firebase tidak
/// diverifikasi Realtime), jadi ini hanya untuk tampilan. "Aktif X menit
/// lalu" diambil dari tabel user_last_seen yang dicatat server.
class OnlinePresence {
  OnlinePresence._();

  static final OnlinePresence instance = OnlinePresence._();

  static const String _topic = 'realtime:zenime-online';
  static final RegExp _uidRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// uid -> jumlah perangkat yang sedang online dengan uid itu.
  final ValueNotifier<Map<String, int>> online = ValueNotifier<Map<String, int>>(const {});

  /// false sampai daftar pertama dari server diterima.
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  String? _uid;
  bool _run = false;
  int _retry = 0;
  int _ref = 0;
  int _gen = 0;
  String? _joinRef;

  bool isOnline(String uid) => (online.value[uid] ?? 0) > 0;
  int get count => online.value.length;

  String _nextRef() => (++_ref).toString();

  /// Mulai (atau ganti akun). Aman dipanggil berulang.
  void start(String uid) {
    if (!_uidRe.hasMatch(uid)) return;
    if (_run && _uid == uid) return;
    _uid = uid;
    _run = true;
    _retry = 0;
    _connect();
  }

  /// Keluar dari presence (app ke background / logout). Yang lain langsung
  /// melihat user ini offline.
  void stop() {
    _run = false;
    _gen++;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    ready.value = false;
    online.value = const {};
  }

  void _connect() {
    if (!_run) return;
    final gen = ++_gen;
    _heartbeat?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    final wsUrl = SupabaseConfig.url.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://') +
        '/realtime/v1/websocket?apikey=${SupabaseConfig.anonKey}&vsn=1.0.0';
    try {
      final ch = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = ch;
      ch.ready.then((_) {
        if (gen != _gen || !_run) return;
        _retry = 0;
        _join(ch);
        _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
          if (gen != _gen || !_run) return;
          _send(ch, {'topic': 'phoenix', 'event': 'heartbeat', 'payload': <String, dynamic>{}, 'ref': _nextRef()});
        });
      }).catchError((Object _) {
        if (gen == _gen) _scheduleReconnect();
      });
      _sub?.cancel();
      _sub = ch.stream.listen(
        (data) {
          if (gen == _gen && data is String) _onFrame(ch, data);
        },
        onError: (Object _) {
          if (gen == _gen) _scheduleReconnect();
        },
        onDone: () {
          if (gen == _gen && _run) _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _send(WebSocketChannel ch, Map<String, dynamic> msg) {
    try {
      ch.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _join(WebSocketChannel ch) {
    _joinRef = _nextRef();
    _send(ch, {
      'topic': _topic,
      'event': 'phx_join',
      'payload': {
        'config': {
          'broadcast': {'self': false, 'ack': false},
          'presence': {'key': _uid, 'enabled': true},
          'postgres_changes': <dynamic>[],
          'private': false,
        },
      },
      'ref': _joinRef,
      'join_ref': _joinRef,
    });
  }

  void _track(WebSocketChannel ch) {
    _send(ch, {
      'topic': _topic,
      'event': 'presence',
      'payload': {
        'type': 'presence',
        'event': 'track',
        'payload': {'uid': _uid, 'at': DateTime.now().toUtc().toIso8601String()},
      },
      'ref': _nextRef(),
      'join_ref': _joinRef,
    });
  }

  void _onFrame(WebSocketChannel ch, String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['topic'] != _topic) return;
      switch (j['event']) {
        case 'phx_reply':
          final reply = j['payload'];
          if (j['ref'] == _joinRef && reply is Map && reply['status'] == 'ok') _track(ch);
        case 'presence_state':
          final st = j['payload'];
          if (st is Map) {
            final next = <String, int>{};
            st.forEach((k, v) {
              final n = _metaCount(v);
              if (k is String && _uidRe.hasMatch(k) && n > 0) next[k] = n;
            });
            online.value = next;
            ready.value = true;
          }
        case 'presence_diff':
          final diff = j['payload'];
          if (diff is Map) {
            final next = Map<String, int>.from(online.value);
            final joins = diff['joins'];
            final leaves = diff['leaves'];
            if (joins is Map) {
              joins.forEach((k, v) {
                if (k is String && _uidRe.hasMatch(k)) next[k] = (next[k] ?? 0) + math.max<int>(1, _metaCount(v));
              });
            }
            if (leaves is Map) {
              leaves.forEach((k, v) {
                if (k is! String) return;
                final n = (next[k] ?? 0) - math.max<int>(1, _metaCount(v));
                if (n > 0) {
                  next[k] = n;
                } else {
                  next.remove(k);
                }
              });
            }
            online.value = next;
            ready.value = true;
          }
        case 'phx_error':
        case 'phx_close':
          if (_run) _scheduleReconnect();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Presence frame error: $e');
    }
  }

  static int _metaCount(Object? v) {
    if (v is Map && v['metas'] is List) return (v['metas'] as List).length;
    return 0;
  }

  void _scheduleReconnect() {
    if (!_run) return;
    _gen++;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    final secs = math.min(30, 1 << math.min(_retry, 5));
    _retry++;
    _reconnect = Timer(Duration(seconds: secs), _connect);
  }
}
