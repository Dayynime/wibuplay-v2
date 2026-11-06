import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/nobar_models.dart';
import '../../../data/models/sticker_models.dart';
import '../../components/friend_avatar.dart';
import '../sticker/sticker_widgets.dart';

/// Daftar chat nobar + kolom ketik. Data & kirim diurus nobar_screen.
class NobarChatPanel extends StatefulWidget {
  const NobarChatPanel({
    super.key,
    required this.messages,
    required this.myUid,
    required this.hostUid,
    required this.sending,
    required this.loading,
    required this.onSend,
    required this.bottomPadding,
  });

  final List<NobarChatMessage> messages;
  final String myUid;
  final String hostUid;
  final bool sending;
  final bool loading;

  /// Return true kalau terkirim (kolom ketik dikosongkan).
  final Future<bool> Function(String text) onSend;

  /// Ruang di bawah untuk dock voice yang mengambang.
  final double bottomPadding;

  @override
  State<NobarChatPanel> createState() => _NobarChatPanelState();
}

class _NobarChatPanelState extends State<NobarChatPanel> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _input.text).trim();
    if (text.isEmpty || widget.sending) return;
    final ok = await widget.onSend(text);
    if (ok && override == null && mounted) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    Widget list;
    if (widget.loading && msgs.isEmpty) {
      list = const Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 2.5));
    } else if (msgs.isEmpty) {
      list = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Belum ada chat. Sapa teman nobarmu! 👋',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    } else {
      // reverse: pesan terbaru di bawah & otomatis terlihat.
      list = ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        itemCount: msgs.length,
        itemBuilder: (_, i) {
          final m = msgs[msgs.length - 1 - i];
          final prev = msgs.length - 2 - i >= 0 ? msgs[msgs.length - 2 - i] : null;
          final grouped = prev != null &&
              prev.uid == m.uid &&
              m.createdAt.difference(prev.createdAt).inMinutes < 3;
          return _Bubble(
            message: m,
            mine: m.uid == widget.myUid,
            host: m.uid == widget.hostUid,
            showHeader: !grouped,
          );
        },
      );
    }

    return Column(
      children: [
        Expanded(child: list),
        Container(
          padding: EdgeInsets.fromLTRB(4, 8, 10, 8 + widget.bottomPadding),
          decoration: BoxDecoration(
            color: AppColors.backgroundDarkSecondary,
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              StickerButton(enabled: !widget.sending, onPicked: (t) => _send(t)),
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 300,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  cursorColor: AppColors.accentViolet,
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    hintText: 'Chat ke room...',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: const Color(0x0FFFFFFF),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 42,
                child: Material(
                  color: AppColors.accentViolet,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.sending ? null : _send,
                    child: widget.sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.host, required this.showHeader});

  final NobarChatMessage message;
  final bool mine;
  final bool host;
  final bool showHeader;

  static Color? _parse(String? hex) {
    if (hex == null) return null;
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final sticker = stickerCodeOf(message.message);
    final nameColor = _parse(message.usernameColor) ?? (mine ? AppColors.accentVioletLight : const Color(0xFF7DD3FC));
    final body = sticker != null
        ? StickerView(code: sticker, size: 96)
        : Text(
            message.message,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 14, height: 1.3),
          );

    return Padding(
      padding: EdgeInsets.only(top: showHeader ? 10 : 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: showHeader
                ? FriendAvatar(
                    url: message.avatarUrl,
                    seed: message.uid,
                    label: message.username,
                    size: 32,
                    framed: false,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            mine ? '${message.username} (kamu)' : message.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: nameColor, fontSize: 12.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (host) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0x33F5B301),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'HOST',
                              style: TextStyle(color: Color(0xFFF5B301), fontSize: 9, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Text(
                          _time(message.createdAt),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                if (sticker != null)
                  body
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: mine ? AppColors.accentViolet.withValues(alpha: 0.22) : const Color(0x14FFFFFF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: body,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
