import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/supabase_config.dart';
import '../models/chat_models.dart';

/// Event dari Supabase Realtime untuk tabel `global_chat_messages`.
abstract class ChatRealtimeEvent {
  const ChatRealtimeEvent();
}

class ChatInserted extends ChatRealtimeEvent {
  const ChatInserted(this.message);
  final ChatMessage message;
}

class ChatDeleted extends ChatRealtimeEvent {
  const ChatDeleted(this.id);
  final int id;
}

/// Port ChatRealtimeClient.kt: ngomong langsung protokol Phoenix Channel
/// (postgres_changes INSERT + DELETE), heartbeat 25 detik, auto-reconnect
/// dengan backoff.
class ChatRealtimeClient {
  ChatRealtimeClient();

  static const String _topic = 'realtime:public:global_chat_messages';

  final StreamController<ChatRealtimeEvent> _events =
      StreamController<ChatRealtimeEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _shouldRun = false;
  int _retry = 0;
  int _ref = 0;
  int _generation = 0;

  Stream<ChatRealtimeEvent> get events => _events.stream;

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
    await _events.close();
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
    final join = {
      'topic': _topic,
      'event': 'phx_join',
      'payload': {
        'config': {
          'postgres_changes': [
            {'event': 'INSERT', 'schema': 'public', 'table': 'global_chat_messages'},
            {'event': 'DELETE', 'schema': 'public', 'table': 'global_chat_messages'},
          ],
        },
      },
      'ref': _nextRef(),
    };
    channel.sink.add(jsonEncode(join));
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
      if (json is! Map || json['event'] != 'postgres_changes') return;
      final payload = json['payload'];
      if (payload is! Map) return;
      final data = payload['data'];
      if (data is! Map) return;
      switch (data['type']) {
        case 'INSERT':
          final record = data['record'];
          if (record is Map) {
            _events.add(ChatInserted(ChatMessage.fromJson(Map<String, dynamic>.from(record))));
          }
          break;
        case 'DELETE':
          final old = data['old_record'];
          if (old is Map) {
            final id = (old['id'] as num?)?.toInt();
            if (id != null) _events.add(ChatDeleted(id));
          }
          break;
      }
    } catch (_) {
      // Frame lain (phx_reply, dll) aman diabaikan.
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
