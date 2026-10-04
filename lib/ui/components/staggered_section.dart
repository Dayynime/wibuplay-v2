import 'dart:async';

import 'package:flutter/material.dart';

/// Port StaggeredSection (HomeScreen.kt): fade + geser 35px ke atas, 300ms,
/// dengan delay per section. Kalau [visible] sudah true saat pertama dibuat
/// (mis. item yang baru ter-scroll masuk), langsung tampil tanpa animasi,
/// sama seperti AnimatedVisibility di Compose.
class StaggeredSection extends StatefulWidget {
  const StaggeredSection({
    super.key,
    required this.visible,
    required this.delayMs,
    required this.child,
  });

  final bool visible;
  final int delayMs;
  final Widget child;

  @override
  State<StaggeredSection> createState() => _StaggeredSectionState();
}

class _StaggeredSectionState extends State<StaggeredSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.visible ? 1.0 : 0.0,
  );
  Timer? _timer;

  @override
  void didUpdateWidget(StaggeredSection old) {
    super.didUpdateWidget(old);
    if (!old.visible && widget.visible) {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    } else if (old.visible && !widget.visible) {
      _timer?.cancel();
      _c.value = 0.0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = Curves.easeOut.transform(_c.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 35 / dpr),
            child: child,
          ),
        );
      },
    );
  }
}
