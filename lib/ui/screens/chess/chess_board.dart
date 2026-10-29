import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';

// ============================================================================
// Warna papan (slate, kontras untuk bidak putih maupun hitam di tema gelap).
// ============================================================================

class ChessPalette {
  ChessPalette._();

  static const Color light = Color(0xFF8A94AA);
  static const Color dark = Color(0xFF555F76);
  static const Color lastMove = Color(0x73F59E0B); // amber transparan
  static const Color selected = Color(0x8CE4344A); // crimson transparan
  static const Color whiteFill = Color(0xFFF4EFE6);
  static const Color whiteLine = Color(0xFF1B1F2A);
  static const Color blackFill = Color(0xFF151A23);
  static const Color blackLine = Color(0xFFE9E3D8);
  static const Color coordOnLight = Color(0xFF555F76);
  static const Color coordOnDark = Color(0xFF8A94AA);
}

// ============================================================================
// Bidak: digambar sendiri (bukan simbol Unicode, karena ♟ tampil sebagai
// emoji di sebagian HP Android). Koordinat dalam kotak 100x100.
// ============================================================================

class _PieceShape {
  const _PieceShape({required this.body, required this.lines, required this.dots});

  /// Bagian badan; tiap Path diisi terpisah supaya tidak ada lubang.
  final List<Path> body;

  /// Garis detail (diberi warna kontur di atas isi).
  final List<Path> lines;

  /// Titik detail (mata kuda).
  final List<Path> dots;
}

final Map<String, _PieceShape> _shapes = {
  'p': _PieceShape(
    body: [
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(50, 30), radius: 12.5)),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(37, 42, 26, 7), const Radius.circular(3.5))),
      Path()
        ..moveTo(41.0, 48.0)
        ..cubicTo(41.0, 60.0, 34.0, 66.0, 31.0, 75.0)
        ..lineTo(69.0, 75.0)
        ..cubicTo(66.0, 66.0, 59.0, 60.0, 59.0, 48.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 80, 56, 10), const Radius.circular(4))),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 73, 46, 9), const Radius.circular(3))),
    ],
    lines: [],
    dots: [],
  ),
  'r': _PieceShape(
    body: [
      Path()
        ..moveTo(27.0, 14.0)
        ..lineTo(37.0, 14.0)
        ..lineTo(37.0, 22.0)
        ..lineTo(45.0, 22.0)
        ..lineTo(45.0, 14.0)
        ..lineTo(55.0, 14.0)
        ..lineTo(55.0, 22.0)
        ..lineTo(63.0, 22.0)
        ..lineTo(63.0, 14.0)
        ..lineTo(73.0, 14.0)
        ..lineTo(73.0, 34.0)
        ..lineTo(27.0, 34.0)
        ..close(),
      Path()
        ..moveTo(33.0, 33.0)
        ..lineTo(67.0, 33.0)
        ..lineTo(64.0, 75.0)
        ..lineTo(36.0, 75.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 80, 56, 10), const Radius.circular(4))),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 73, 46, 9), const Radius.circular(3))),
    ],
    lines: [
      Path()
        ..moveTo(30.0, 35.0)
        ..lineTo(70.0, 35.0),
      Path()
        ..moveTo(35.0, 68.0)
        ..lineTo(65.0, 68.0),
    ],
    dots: [],
  ),
  'b': _PieceShape(
    body: [
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(50, 11), radius: 5.5)),
      Path()
        ..moveTo(50.0, 15.0)
        ..cubicTo(66.0, 28.0, 68.0, 42.0, 59.0, 52.0)
        ..lineTo(41.0, 52.0)
        ..cubicTo(32.0, 42.0, 34.0, 28.0, 50.0, 15.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(35, 51, 30, 7), const Radius.circular(3.5))),
      Path()
        ..moveTo(41.0, 57.0)
        ..cubicTo(41.0, 64.0, 35.0, 69.0, 32.0, 75.0)
        ..lineTo(68.0, 75.0)
        ..cubicTo(65.0, 69.0, 59.0, 64.0, 59.0, 57.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 80, 56, 10), const Radius.circular(4))),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 73, 46, 9), const Radius.circular(3))),
    ],
    lines: [
      Path()
        ..moveTo(56.0, 26.0)
        ..lineTo(47.0, 38.0),
    ],
    dots: [],
  ),
  'n': _PieceShape(
    body: [
      Path()
        ..moveTo(33.0, 75.0)
        ..cubicTo(33.0, 62.0, 38.0, 55.0, 47.0, 47.0)
        ..cubicTo(41.0, 49.0, 35.0, 52.0, 29.0, 57.0)
        ..cubicTo(23.0, 58.0, 18.0, 52.0, 21.0, 46.0)
        ..cubicTo(28.0, 36.0, 36.0, 28.0, 41.0, 21.0)
        ..lineTo(40.0, 9.0)
        ..lineTo(49.0, 16.0)
        ..lineTo(54.0, 8.0)
        ..lineTo(57.0, 18.0)
        ..cubicTo(72.0, 24.0, 80.0, 40.0, 77.0, 58.0)
        ..cubicTo(76.0, 66.0, 72.0, 71.0, 69.0, 75.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 80, 56, 10), const Radius.circular(4))),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 73, 46, 9), const Radius.circular(3))),
    ],
    lines: [
      Path()
        ..moveTo(25.0, 50.0)
        ..lineTo(29.0, 50.0),
    ],
    dots: [
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(47, 30), radius: 2.6)),
    ],
  ),
  'q': _PieceShape(
    body: [
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(21, 25), radius: 5)),
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(35, 18), radius: 5)),
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(50, 13), radius: 5)),
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(65, 18), radius: 5)),
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(79, 25), radius: 5)),
      Path()
        ..moveTo(30.0, 62.0)
        ..lineTo(21.0, 26.0)
        ..lineTo(31.0, 45.0)
        ..lineTo(35.0, 19.0)
        ..lineTo(43.0, 41.0)
        ..lineTo(50.0, 14.0)
        ..lineTo(57.0, 41.0)
        ..lineTo(65.0, 19.0)
        ..lineTo(69.0, 45.0)
        ..lineTo(79.0, 26.0)
        ..lineTo(70.0, 62.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 60, 38, 7), const Radius.circular(3.5))),
      Path()
        ..moveTo(35.0, 66.0)
        ..lineTo(65.0, 66.0)
        ..lineTo(68.0, 75.0)
        ..lineTo(32.0, 75.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 80, 56, 10), const Radius.circular(4))),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 73, 46, 9), const Radius.circular(3))),
    ],
    lines: [],
    dots: [],
  ),
  'k': _PieceShape(
    body: [
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(46, 3, 8, 22), const Radius.circular(2))),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(39, 9, 22, 7), const Radius.circular(2))),
      Path()
        ..moveTo(50.0, 27.0)
        ..cubicTo(70.0, 20.0, 82.0, 34.0, 73.0, 48.0)
        ..lineTo(67.0, 62.0)
        ..lineTo(33.0, 62.0)
        ..lineTo(27.0, 48.0)
        ..cubicTo(18.0, 34.0, 30.0, 20.0, 50.0, 27.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 60, 38, 7), const Radius.circular(3.5))),
      Path()
        ..moveTo(35.0, 66.0)
        ..lineTo(65.0, 66.0)
        ..lineTo(68.0, 75.0)
        ..lineTo(32.0, 75.0)
        ..close(),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 80, 56, 10), const Radius.circular(4))),
      Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 73, 46, 9), const Radius.circular(3))),
    ],
    lines: [
      Path()
        ..moveTo(50.0, 30.0)
        ..lineTo(50.0, 58.0),
    ],
    dots: [],
  ),
};

/// Satu bidak. [piece] memakai notasi FEN: huruf besar = putih (K Q R B N P),
/// huruf kecil = hitam.
class ChessPieceGlyph extends StatelessWidget {
  const ChessPieceGlyph({super.key, required this.piece, required this.size});

  final String piece;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PiecePainter(piece)),
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter(this.piece);

  final String piece;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _shapes[piece.toLowerCase()];
    if (shape == null) return;
    final white = piece.toUpperCase() == piece;
    final fill = white ? ChessPalette.whiteFill : ChessPalette.blackFill;
    final line = white ? ChessPalette.whiteLine : ChessPalette.blackLine;

    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    // Bayangan lembut di bawah bidak supaya "berdiri" di atas papan.
    canvas.drawOval(
      const Rect.fromLTWH(24, 86, 52, 9),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Kontur dulu (tebal), lalu isi di atasnya: sambungan antarbagian tidak
    // memunculkan garis di dalam siluet.
    final outline = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = StrokeJoin.round;
    final outlineFill = Paint()..color = line;
    for (final p in shape.body) {
      canvas.drawPath(p, outlineFill);
      canvas.drawPath(p, outline);
    }
    final fillPaint = Paint()..color = fill;
    for (final p in shape.body) {
      canvas.drawPath(p, fillPaint);
    }
    final detail = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final p in shape.lines) {
      canvas.drawPath(p, detail);
    }
    for (final p in shape.dots) {
      canvas.drawPath(p, outlineFill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PiecePainter old) => old.piece != piece;
}

// ============================================================================
// Posisi
// ============================================================================

const List<String> _files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

/// Bagian penempatan bidak dari FEN -> map kotak ('e4') ke bidak ('P').
Map<String, String> chessPiecesFromFen(String fen) {
  final out = <String, String>{};
  final placement = fen.split(' ').first;
  final rows = placement.split('/');
  if (rows.length != 8) return out;
  for (var r = 0; r < 8; r++) {
    var f = 0;
    for (final ch in rows[r].split('')) {
      final n = int.tryParse(ch);
      if (n != null) {
        f += n;
      } else if (f < 8) {
        out['${_files[f]}${8 - r}'] = ch;
        f++;
      }
    }
  }
  return out;
}

/// Terapkan langkah UCI ke [pieces] secara lokal (untuk tampilan instan sebelum
/// server menjawab). Menangani rokade, en passant, dan promosi. Server tetap
/// sumber kebenaran; hasil ini diganti begitu respons datang.
Map<String, String> chessApplyLocal(Map<String, String> pieces, String uci) {
  if (uci.length < 4) return pieces;
  final from = uci.substring(0, 2);
  final to = uci.substring(2, 4);
  final moving = pieces[from];
  if (moving == null) return pieces;
  final next = Map<String, String>.from(pieces);
  next.remove(from);

  final isPawn = moving.toLowerCase() == 'p';
  final isKing = moving.toLowerCase() == 'k';
  final dx = _files.indexOf(to[0]) - _files.indexOf(from[0]);

  // En passant: pion pindah diagonal ke kotak kosong.
  if (isPawn && dx != 0 && !pieces.containsKey(to)) {
    next.remove('${to[0]}${from[1]}');
  }
  // Rokade: raja geser 2 kotak, benteng ikut.
  if (isKing && dx.abs() == 2) {
    final rank = from[1];
    if (dx > 0) {
      final rook = next.remove('h$rank');
      if (rook != null) next['f$rank'] = rook;
    } else {
      final rook = next.remove('a$rank');
      if (rook != null) next['d$rank'] = rook;
    }
  }
  var placed = moving;
  if (uci.length == 5) {
    final promo = uci[4];
    placed = moving == moving.toUpperCase() ? promo.toUpperCase() : promo.toLowerCase();
  }
  next[to] = placed;
  return next;
}

/// Kotak raja milik [color] ('w'/'b').
String? chessKingSquare(Map<String, String> pieces, String color) {
  final k = color == 'w' ? 'K' : 'k';
  for (final e in pieces.entries) {
    if (e.value == k) return e.key;
  }
  return null;
}

// ============================================================================
// Papan
// ============================================================================

/// Papan catur interaktif: tap untuk memilih lalu tap tujuan, atau geser
/// bidak langsung. Papan tidak tahu aturan catur: kotak tujuan ([targets])
/// diberikan pemakai dari daftar langkah legal server.
class ChessBoardView extends StatefulWidget {
  const ChessBoardView({
    super.key,
    required this.pieces,
    this.flipped = false,
    this.lastFrom,
    this.lastTo,
    this.moveKey = 0,
    this.checkSquare,
    this.selected,
    this.targets = const <String>{},
    this.canPick,
    this.onSelect,
    this.onMove,
    this.dimmed = false,
  });

  final Map<String, String> pieces;

  /// True = hitam di bawah.
  final bool flipped;
  final String? lastFrom;
  final String? lastTo;

  /// Berubah tiap ada langkah baru; dipakai untuk menganimasikan bidak
  /// dari [lastFrom] ke [lastTo] sekali saja.
  final int moveKey;
  final String? checkSquare;
  final String? selected;
  final Set<String> targets;

  /// Boleh memilih bidak di kotak ini? null = papan hanya untuk dilihat.
  final bool Function(String square)? canPick;
  final ValueChanged<String?>? onSelect;
  final void Function(String from, String to)? onMove;
  final bool dimmed;

  @override
  State<ChessBoardView> createState() => _ChessBoardViewState();
}

class _ChessBoardViewState extends State<ChessBoardView> {
  String? _dragFrom;
  Offset? _dragPos;
  Offset? _dragStart;
  bool _wasSelected = false;
  late int _animatedKey;

  @override
  void initState() {
    super.initState();
    // Langkah terakhir saat layar dibuka tidak dianimasikan ulang.
    _animatedKey = widget.moveKey;
  }

  bool get _interactive => widget.canPick != null;

  String? _squareAt(Offset local, double sq) {
    final c = (local.dx / sq).floor();
    final r = (local.dy / sq).floor();
    if (c < 0 || c > 7 || r < 0 || r > 7) return null;
    final file = widget.flipped ? 7 - c : c;
    final rank = widget.flipped ? r + 1 : 8 - r;
    return '${_files[file]}$rank';
  }

  Offset _originOf(String square, double sq) {
    final file = _files.indexOf(square[0]);
    final rank = int.parse(square[1]);
    final c = widget.flipped ? 7 - file : file;
    final r = widget.flipped ? rank - 1 : 8 - rank;
    return Offset(c * sq, r * sq);
  }

  void _tap(String? s) {
    if (!_interactive || s == null) return;
    final sel = widget.selected;
    if (sel != null && widget.targets.contains(s)) {
      widget.onMove?.call(sel, s);
      return;
    }
    if (sel == s) {
      widget.onSelect?.call(null);
      return;
    }
    if (widget.canPick!(s)) {
      HapticFeedback.selectionClick();
      widget.onSelect?.call(s);
    } else {
      widget.onSelect?.call(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final size = c.maxWidth;
        final sq = size / 8;

        final children = <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _BoardPainter(
                flipped: widget.flipped,
                lastFrom: widget.lastFrom,
                lastTo: widget.lastTo,
                selected: widget.selected,
                checkSquare: widget.checkSquare,
                targets: widget.targets,
                occupied: widget.pieces.keys.toSet(),
                coordStyle: TextStyle(fontSize: sq * 0.2, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ];

        final animate = !reduceMotion &&
            widget.moveKey != _animatedKey &&
            widget.lastFrom != null &&
            widget.lastTo != null;
        if (animate) {
          // Tandai sudah dianimasikan setelah frame ini (tidak setState di build).
          final k = widget.moveKey;
          WidgetsBinding.instance.addPostFrameCallback((_) => _animatedKey = k);
        }

        for (final e in widget.pieces.entries) {
          if (e.key == _dragFrom && _dragPos != null) continue;
          final origin = _originOf(e.key, sq);
          Widget piece = ChessPieceGlyph(piece: e.value, size: sq);
          if (animate && e.key == widget.lastTo) {
            final from = _originOf(widget.lastFrom!, sq);
            piece = TweenAnimationBuilder<Offset>(
              key: ValueKey('mv-${widget.moveKey}'),
              tween: Tween(begin: from - origin, end: Offset.zero),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (_, o, child) => Transform.translate(offset: o, child: child),
              child: piece,
            );
          }
          children.add(Positioned(left: origin.dx, top: origin.dy, width: sq, height: sq, child: piece));
        }

        Widget board = ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(children: children),
        );
        if (widget.dimmed) {
          board = Opacity(opacity: 0.45, child: board);
        }

        // Bidak yang sedang digeser: sedikit lebih besar, mengikuti jari, dan
        // di luar area potong supaya tidak terpotong di tepi papan.
        final dragPiece = _dragFrom == null ? null : widget.pieces[_dragFrom!];
        if (dragPiece != null && _dragPos != null) {
          final big = sq * 1.35;
          board = Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: board),
              Positioned(
                left: _dragPos!.dx - big / 2,
                top: _dragPos!.dy - big * 0.8,
                width: big,
                height: big,
                child: IgnorePointer(child: ChessPieceGlyph(piece: dragPiece, size: big)),
              ),
            ],
          );
        }

        if (!_interactive) return board;

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (t) => t.onTapUp = (d) => _tap(_squareAt(d.localPosition, sq)),
            ),
            _BoardPanRecognizer: GestureRecognizerFactoryWithHandlers<_BoardPanRecognizer>(
              () => _BoardPanRecognizer(),
              (p) {
                // Jari mendarat di bidak sendiri: klaim sentuhan saat itu juga
                // supaya geseran tidak direbut scroll halaman.
                p.shouldClaim = (local) {
                  final s = _squareAt(local, sq);
                  return s != null && widget.pieces.containsKey(s) && widget.canPick!(s);
                };
                p.onStart = (d) {
                  final s = _squareAt(d.localPosition, sq);
                  if (s == null || !widget.pieces.containsKey(s) || !widget.canPick!(s)) return;
                  _wasSelected = widget.selected == s;
                  if (!_wasSelected) {
                    HapticFeedback.selectionClick();
                    widget.onSelect?.call(s);
                  }
                  setState(() {
                    _dragFrom = s;
                    _dragStart = d.localPosition;
                    _dragPos = d.localPosition;
                  });
                };
                p.onUpdate = (d) {
                  if (_dragFrom == null) return;
                  setState(() => _dragPos = d.localPosition);
                };
                p.onEnd = (_) {
                  final from = _dragFrom;
                  final pos = _dragPos;
                  final moved = pos != null && _dragStart != null && (pos - _dragStart!).distance > sq * 0.3;
                  setState(() {
                    _dragFrom = null;
                    _dragPos = null;
                    _dragStart = null;
                  });
                  if (from == null || pos == null) return;
                  final to = _squareAt(pos, sq);
                  if (moved && to != null && to != from && widget.targets.contains(to)) {
                    // Bidak sudah di tujuan, jadi tanpa animasi geser lagi.
                    _animatedKey = widget.moveKey + 1;
                    widget.onMove?.call(from, to);
                  } else if (!moved && _wasSelected) {
                    // Tap lagi bidak yang sudah dipilih = batal pilih.
                    widget.onSelect?.call(null);
                  }
                };
                p.onCancel = () => setState(() {
                  _dragFrom = null;
                  _dragPos = null;
                  _dragStart = null;
                });
              },
            ),
          },
          child: board,
        );
      }),
    );
  }
}

/// Pan yang langsung menang di arena gestur kalau [shouldClaim] true untuk
/// titik sentuh (bidak milik pemain), seperti EagerGestureRecognizer.
class _BoardPanRecognizer extends PanGestureRecognizer {
  bool Function(Offset local)? shouldClaim;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (shouldClaim?.call(event.localPosition) ?? false) {
      resolve(GestureDisposition.accepted);
    }
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.flipped,
    required this.lastFrom,
    required this.lastTo,
    required this.selected,
    required this.checkSquare,
    required this.targets,
    required this.occupied,
    required this.coordStyle,
  });

  final bool flipped;
  final String? lastFrom;
  final String? lastTo;
  final String? selected;
  final String? checkSquare;
  final Set<String> targets;
  final Set<String> occupied;
  final TextStyle coordStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    final lightP = Paint()..color = ChessPalette.light;
    final darkP = Paint()..color = ChessPalette.dark;

    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final file = flipped ? 7 - c : c;
        final rank = flipped ? r + 1 : 8 - r;
        final name = '${_files[file]}$rank';
        final rect = Rect.fromLTWH(c * sq, r * sq, sq, sq);
        final isLight = (file + rank) % 2 == 1;
        canvas.drawRect(rect, isLight ? lightP : darkP);

        if (name == lastFrom || name == lastTo) {
          canvas.drawRect(rect, Paint()..color = ChessPalette.lastMove);
        }
        if (name == selected) {
          canvas.drawRect(rect, Paint()..color = ChessPalette.selected);
        }
        if (name == checkSquare) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = RadialGradient(colors: [
                AppColors.accentViolet.withValues(alpha: 0.95),
                AppColors.accentViolet.withValues(alpha: 0.0),
              ]).createShader(rect),
          );
        }
        if (targets.contains(name)) {
          final center = rect.center;
          if (occupied.contains(name)) {
            // Bisa dimakan: cincin di tepi kotak.
            canvas.drawCircle(
              center,
              sq * 0.44,
              Paint()
                ..color = Colors.black.withValues(alpha: 0.32)
                ..style = PaintingStyle.stroke
                ..strokeWidth = sq * 0.09,
            );
          } else {
            canvas.drawCircle(center, sq * 0.15, Paint()..color = Colors.black.withValues(alpha: 0.30));
          }
        }

        // Koordinat: huruf di baris bawah, angka di kolom kiri.
        final onLight = isLight;
        final style = coordStyle.copyWith(color: onLight ? ChessPalette.coordOnLight : ChessPalette.coordOnDark);
        if (r == 7) {
          final tp = TextPainter(text: TextSpan(text: _files[file], style: style), textDirection: TextDirection.ltr)
            ..layout();
          tp.paint(canvas, Offset(rect.right - tp.width - sq * 0.06, rect.bottom - tp.height - sq * 0.02));
        }
        if (c == 0) {
          final tp = TextPainter(text: TextSpan(text: '$rank', style: style), textDirection: TextDirection.ltr)
            ..layout();
          tp.paint(canvas, Offset(rect.left + sq * 0.06, rect.top + sq * 0.03));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter o) =>
      o.flipped != flipped ||
      o.lastFrom != lastFrom ||
      o.lastTo != lastTo ||
      o.selected != selected ||
      o.checkSquare != checkSquare ||
      !setEquals(o.targets, targets) ||
      !setEquals(o.occupied, occupied) ||
      o.coordStyle != coordStyle;
}

/// Papan mini statis untuk thumbnail di hub Zenime Games.
class ChessBoardPreview extends StatelessWidget {
  const ChessBoardPreview({super.key});

  static const String _fen = 'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R';

  @override
  Widget build(BuildContext context) {
    final pieces = chessPiecesFromFen(_fen);
    return LayoutBuilder(builder: (context, c) {
      final side = math.min(c.maxWidth, c.maxHeight) * 0.92;
      return Center(
        child: SizedBox.square(
          dimension: side,
          child: ChessBoardView(pieces: pieces, lastFrom: 'c7', lastTo: 'c5', moveKey: -1),
        ),
      );
    });
  }
}
