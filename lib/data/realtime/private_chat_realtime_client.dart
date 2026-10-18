import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/supabase_config.dart';
import '../models/friend_models.dart';

/// Supabase Realtime (Postgres Changes) buat DM: cuma mendengarkan INSERT di
/// `private_messages` yang `recipient_uid`-nya = user ini (filter di server).
/// Pesan yang DIKIRIM sendiri tidak lewat sini (sudah ada dari response POST).
/// Port PrivateChatRealtimeClient.kt; pola koneksi sama dengan
/// ChatRealtimeClient (heartbeat 25 detik, auto-reconnect dengan backoff).
///
/// SYARAT: tabel sudah masuk publication realtime (sudah diurus
/// private_chat_setup.sql di Zenime).
class PrivateChatRealtimeClient {
  PrivateChatRealtimeClient(this.myUid, {this.onJoined});

  final String myUid;

  /// Dipanggil tiap (re)join berhasil, buat memuat ulang pesan yang kelewat.
  final VoidCallback? onJoined;

  final StreamController<PrivateMessage> _incoming =
      StreamController<PrivateMessage>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _shouldRun = false;
  int _retry = 0;
  int _ref = 0;
  int _generation = 0;
  String? _joinRef;

  String get _topic => 'realtime:public:private_messages:$myUid';

  Stream<PrivateMessage> get incoming => _incoming.stream;

  String _nextRef() => (++_ref).toString();

  void start() {
    if (_shouldRun) return;
    _shouldRun = true;
    _retry = 0;
    _connect();
  }

  Future<void> stop() async {
    _shouldRun = false;
    _generation++;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    await _incoming.close();
  }

  void _connect() {
    if (!_shouldRun) return;
    final gen = ++_generation;
    try {
      _channel?.sink.close();
    } catch (_) {}
    final wsUrl = SupabaseConfig.url
            .replaceFirst('https://', 'wss://')
            .replaceFirst('http://', 'ws://') +
        '/realtime/v1/websocket?apikey=${SupabaseConfig.anonKey}&vsn=1.0.0';
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = channel;
      channel.ready.then((_) {
        if (gen != _generation || !_shouldRun) return;
        _retry = 0;
        _join(channel);
        _startHeartbeat(channel, gen);
      }).catchError((Object _) {
        if (gen == _generation) _scheduleReconnect();
      });
      _sub?.cancel();
      _sub = channel.stream.listen(
        (data) {
          if (gen == _generation && data is String) _handleFrame(data);
        },
        onError: (Object _) {
          if (gen == _generation) _scheduleReconnect();
        },
        onDone: () {
          if (gen == _generation && _shouldRun) _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _join(WebSocketChannel channel) {
    _joinRef = _nextRef();
    channel.sink.add(jsonEncode({
      'topic': _topic,
      'event': 'phx_join',
      'payload': {
        'config': {
          'postgres_changes': [
            {
              'event': 'INSERT',
              'schema': 'public',
              'table': 'private_messages',
              'filter': 'recipient_uid=eq.$myUid',
            },
          ],
        },
      },
      'ref': _joinRef,
    }));
  }

  void _startHeartbeat(WebSocketChannel channel, int gen) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      if (gen != _generation || !_shouldRun) return;
      try {
        channel.sink.add(jsonEncode({
          'topic': 'phoenix',
          'event': 'heartbeat',
          'payload': <String, dynamic>{},
          'ref': _nextRef(),
        }));
      } catch (_) {}
    });
  }

  void _handleFrame(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return;
      final event = json['event'];
      if (event == 'phx_reply') {
        if (json['topic'] == _topic && json['ref'] == _joinRef) {
          final payload = json['payload'];
          if (payload is Map && payload['status'] == 'ok') onJoined?.call();
        }
        return;
      }
      if (event != 'postgres_changes') return;
      final payload = json['payload'];
      final data = payload is Map ? payload['data'] : null;
      if (data is! Map || data['type'] != 'INSERT') return;
      final record = data['record'];
      if (record is Map && !_incoming.isClosed) {
        _incoming.add(PrivateMessage.fromJson(Map<String, dynamic>.from(record)));
      }
    } catch (e) {
      // Frame lain: aman diabaikan.
      if (kDebugMode) debugPrint('DM RT frame error: $e');
    }
  }

  void _scheduleReconnect() {
    if (!_shouldRun) return;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    final delayMs = math.min(30000, 1000 * (1 << math.min(_retry, 5)));
    _retry++;
    _reconnect = Timer(Duration(milliseconds: delayMs), () {
      if (_shouldRun) _connect();
    });
  }
}
