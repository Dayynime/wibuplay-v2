import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// Geser ke kanan untuk membalas: bubble ikut bergeser, ikon + tulisan
/// "Reply" muncul di kiri, lepas jari setelah melewati batas = reply terpicu.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.child, required this.onReply});

  final Widget child;
  final VoidCallback onReply;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  static const double _trigger = 64;
  static const double _max = 96;

  double _dx = 0;
  bool _dragging = false;
  bool _buzzed = false;

  void _onUpdate(DragUpdateDetails d) {
    final next = (_dx + d.delta.dx).clamp(0.0, _max);
    if (!_buzzed && next >= _trigger) {
      _buzzed = true;
      HapticFeedback.selectionClick();
    }
    if (next < _trigger) _buzzed = false;
    setState(() => _dx = next);
  }

  void _onEnd([DragEndDetails? _]) {
    final fire = _dx >= _trigger;
    setState(() {
      _dragging = false;
      _dx = 0;
      _buzzed = false;
    });
    if (fire) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onEnd,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: progress,
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.reply, size: 18, color: AppColors.accentVioletLight),
                  SizedBox(width: 4),
                  Text(
                    'Reply',
                    style: TextStyle(color: AppColors.accentVioletLight, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
