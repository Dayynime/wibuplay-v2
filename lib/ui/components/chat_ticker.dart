import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/chat_models.dart';
import '../../data/realtime/chat_realtime_client.dart';
import '../../providers.dart';
import '../app_routes.dart';
import '../screens/chat/chat_screen.dart';

/// Strip chat global di Beranda: pesan terbaru bergeser pelan ke kiri
/// (berulang tanpa putus), pesan baru masuk lewat realtime. Disembunyikan
/// kalau belum ada pesan / gagal memuat. Tap membuka layar Chat.
class ChatTicker extends ConsumerStatefulWidget {
  const ChatTicker({super.key});

  @override
  ConsumerState<ChatTicker> createState() => _ChatTickerState();
}

class _ChatTickerState extends ConsumerState<ChatTicker>
    with SingleTickerProviderStateMixin {
  static const int _maxItems = 10;
  static const double _pxPerSecond = 28;

  final ScrollController _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  ChatRealtimeClient? _realtime;
  StreamSubscription<ChatRealtimeEvent>? _sub;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  Timer? _resumeTimer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _load();
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _ticker?.dispose();
    _sub?.cancel();
    _realtime?.stop();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(chatRepositoryProvider).getMessages(limit: _maxItems);
      if (!mounted) return;
      setState(() => _messages = list.where(_shown).toList());
    } catch (_) {
      // Gagal muat: strip tetap tersembunyi.
    }
    if (!mounted) return;
    final client = ChatRealtimeClient();
    _realtime = client;
    _sub = client.events.listen(_onEvent);
    client.start();
  }

  bool _shown(ChatMessage m) => m.message.trim().isNotEmpty || m.isVoice;

  void _onEvent(ChatRealtimeEvent e) {
    if (!mounted) return;
    if (e is ChatInserted) {
      final msg = e.message;
      if (!_shown(msg) || _messages.any((m) => m.id == msg.id)) return;
      var next = [..._messages, msg];
      if (next.length > _maxItems) next = next.sublist(next.length - _maxItems);
      setState(() => _messages = next);
    } else if (e is ChatDeleted) {
      setState(() => _messages = _messages.where((m) => m.id != e.id).toList());
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_paused || _messages.isEmpty || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.offset + _pxPerSecond * dt);
  }

  void _pause() {
    _resumeTimer?.cancel();
    _paused = true;
  }

  void _resumeSoon() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 2), () => _paused = false);
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _messages;
    if (msgs.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push<void>(fadeRoute(const ChatScreen())),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.accentViolet,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline, size: 17, color: AppColors.textWhite),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Listener(
                onPointerDown: (_) => _pause(),
                onPointerUp: (_) => _resumeSoon(),
                onPointerCancel: (_) => _resumeSoon(),
                child: ClipRect(
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    // itemCount null = daftar berulang tanpa ujung.
                    itemBuilder: (context, i) => _chip(msgs[i % msgs.length]),
                  ),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 22, color: AppColors.textWhite),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _chip(ChatMessage m) {
    final text = m.isVoice ? '🎤 Pesan suara' : m.message.trim().replaceAll('\n', ' ');
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${m.username}: $text',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textWhite, fontSize: 12),
        ),
      ),
    );
  }
}
