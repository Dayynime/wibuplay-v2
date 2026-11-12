import 'package:flutter/material.dart';

import '../../../core/wp_video.dart';

/// Satu baris subtitle.
class SubtitleCue {
  const SubtitleCue(this.startMs, this.endMs, this.text);

  final int startMs;
  final int endMs;
  final String text;
}

final RegExp _time = RegExp(
  r'(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3})\s*-->\s*(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3})',
);
final RegExp _tags = RegExp(r'<[^>]+>|\{\\[^}]*\}');

int _ms(String? h, String m, String s, String f) {
  final frac = int.parse(f.padRight(3, '0').substring(0, 3));
  return ((int.tryParse(h ?? '0') ?? 0) * 3600 + int.parse(m) * 60 + int.parse(s)) * 1000 + frac;
}

/// Parser SRT dan WebVTT (subtitle MovieBox umumnya SRT).
List<SubtitleCue> parseSubtitles(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceFirst('﻿', '').split('\n');
  final cues = <SubtitleCue>[];
  for (var i = 0; i < lines.length; i++) {
    final m = _time.firstMatch(lines[i]);
    if (m == null) continue;
    final start = _ms(m.group(1), m.group(2)!, m.group(3)!, m.group(4)!);
    final end = _ms(m.group(5), m.group(6)!, m.group(7)!, m.group(8)!);
    final text = <String>[];
    var j = i + 1;
    while (j < lines.length && lines[j].trim().isNotEmpty) {
      text.add(lines[j].replaceAll(_tags, '').trim());
      j++;
    }
    i = j;
    final t = text.where((e) => e.isNotEmpty).join('\n');
    if (t.isNotEmpty && end > start) cues.add(SubtitleCue(start, end, t));
  }
  cues.sort((a, b) => a.startMs.compareTo(b.startMs));
  return cues;
}

/// Teks subtitle di atas video, ikut posisi [video]. Tidak menangkap sentuhan.
class SubtitleLayer extends StatefulWidget {
  const SubtitleLayer({
    super.key,
    required this.video,
    required this.cues,
    this.large = false,
    this.raised = false,
  });

  final WpVideoController video;
  final List<SubtitleCue> cues;

  /// Fullscreen: huruf lebih besar.
  final bool large;

  /// Naikkan sedikit saat kontrol tampil supaya tidak tertutup seekbar.
  final bool raised;

  @override
  State<SubtitleLayer> createState() => _SubtitleLayerState();
}

class _SubtitleLayerState extends State<SubtitleLayer> {
  String _text = '';
  int _hint = 0;

  @override
  void initState() {
    super.initState();
    widget.video.addListener(_update);
    _update();
  }

  @override
  void didUpdateWidget(covariant SubtitleLayer old) {
    super.didUpdateWidget(old);
    if (old.video != widget.video) {
      old.video.removeListener(_update);
      widget.video.addListener(_update);
    }
    if (old.cues != widget.cues) {
      _hint = 0;
      _update();
    }
  }

  @override
  void dispose() {
    widget.video.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final cues = widget.cues;
    final pos = widget.video.value.position.inMilliseconds;
    var text = '';
    if (cues.isNotEmpty) {
      // Mulai dari indeks terakhir (posisi biasanya maju pelan-pelan).
      var i = _hint.clamp(0, cues.length - 1);
      if (cues[i].startMs > pos) i = 0;
      while (i < cues.length && cues[i].endMs < pos) {
        i++;
      }
      if (i < cues.length) {
        _hint = i;
        if (cues[i].startMs <= pos) text = cues[i].text;
      }
    }
    if (text != _text && mounted) setState(() => _text = text);
  }

  @override
  Widget build(BuildContext context) {
    if (_text.isEmpty) return const SizedBox.shrink();
    final size = widget.large ? 20.0 : 14.0;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.fromLTRB(24, 0, 24, widget.raised ? (widget.large ? 84 : 52) : (widget.large ? 28 : 12)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: size,
                height: 1.3,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
