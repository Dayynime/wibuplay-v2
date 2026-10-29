import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/supabase_config.dart';

/// Supabase Realtime **Broadcast** untuk catur: mendengarkan satu topik
/// (`chess-game-<id>` atau `chess-user-<uid>`). Edge Function `chess-game`
/// mengirim "ping" ke topik ini setiap ada perubahan; isi ping TIDAK dipercaya,
/// pemakai cukup memuat ulang data dari server. Karena itu tabel catur tidak
/// perlu masuk publikasi Realtime.
///
/// Pola koneksi sama dengan PrivateChatRealtimeClient (heartbeat 25 detik,
/// auto-reconnect dengan backoff).
class ChessRealtimeClient {
  ChessRealtimeClient(this.topic, {this.onJoined});

  /// Nama topik tanpa awalan `realtime:` (sama dengan yang dipakai server).
  final String topic;

  /// Dipanggil tiap (re)join berhasil, buat memuat ulang yang mungkin kelewat.
  final VoidCallback? onJoined;

  final StreamController<Map<String, dynamic>> _pings =
      StreamController<Map<String, dynamic>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _shouldRun = false;
  bool _joined = false;
  int _retry = 0;
  int _ref = 0;
  int _generation = 0;
  String? _joinRef;

  String get _fullTopic => 'realtime:$topic';

  /// Ping dari server (payload hanya petunjuk, jangan dipercaya).
  Stream<Map<String, dynamic>> get pings => _pings.stream;

  /// True selama channel sudah join; kalau false, pemakai sebaiknya polling.
  bool get isJoined => _joined;

  String _nextRef() => (++_ref).toString();

  void start() {
    if (_shouldRun) return;
    _shouldRun = true;
    _retry = 0;
    _connect();
  }

  Future<void> stop() async {
    _shouldRun = false;
    _joined = false;
    _generation++;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (!_pings.isClosed) await _pings.close();
  }

  void _connect() {
    if (!_shouldRun) return;
    final gen = ++_generation;
    _joined = false;
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
      'topic': _fullTopic,
      'event': 'phx_join',
      'payload': {
        'config': {
          'broadcast': {'self': false, 'ack': false},
          'presence': {'key': ''},
          'postgres_changes': <dynamic>[],
          'private': false,
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
      if (json is! Map || json['topic'] != _fullTopic) return;
      final event = json['event'];
      if (event == 'phx_reply') {
        if (json['ref'] == _joinRef) {
          final payload = json['payload'];
          if (payload is Map && payload['status'] == 'ok') {
            _joined = true;
            onJoined?.call();
          }
        }
        return;
      }
      if (event == 'phx_close' || event == 'phx_error') {
        _scheduleReconnect();
        return;
      }
      if (event != 'broadcast') return;
      final payload = json['payload'];
      final inner = payload is Map ? payload['payload'] : null;
      if (!_pings.isClosed) {
        _pings.add(inner is Map ? Map<String, dynamic>.from(inner) : const <String, dynamic>{});
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Chess RT frame error: $e');
    }
  }

  void _scheduleReconnect() {
    if (!_shouldRun) return;
    _joined = false;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    final delayMs = math.min(30000, 1000 * (1 << math.min(_retry, 5)));
    _retry++;
    _reconnect = Timer(Duration(milliseconds: delayMs), () {
      if (_shouldRun) _connect();
    });
  }
}
