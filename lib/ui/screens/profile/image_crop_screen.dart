import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';

enum CropShape { avatar, banner }

/// Pratinjau + atur posisi foto profil / banner sebelum diupload.
///
/// - JPG/PNG/WebP: geser & cubit (zoom) di dalam bingkai, hasilnya dipotong
///   persis sesuai bingkai lalu dikecilkan (avatar 512x512, banner 1280x720).
/// - GIF: pratinjau saja (tidak bisa digeser) supaya animasinya tidak rusak.
///
/// Return path file siap upload, atau null kalau dibatalkan.
class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({super.key, required this.path, required this.shape, this.isGif = false});

  final String path;
  final CropShape shape;
  final bool isGif;

  /// Rasio banner (lebar / tinggi).
  static const double bannerAspect = 16 / 9;

  static Future<String?> open(
    BuildContext context, {
    required String path,
    required CropShape shape,
    bool isGif = false,
  }) {
    return Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(path: path, shape: shape, isGif: isGif),
      ),
    );
  }

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final TransformationController _tc = TransformationController();

  String? _prepPath; // gambar yang sudah diputar sesuai EXIF & dikecilkan
  int _iw = 0;
  int _ih = 0;
  String? _error;
  bool _saving = false;

  // Ukuran bingkai & ukuran gambar di layar (untuk hitung area potong).
  Size _frame = Size.zero;
  double _baseScale = 1;
  bool _positioned = false;

  bool get _isAvatar => widget.shape == CropShape.avatar;

  @override
  void initState() {
    super.initState();
    if (widget.isGif) {
      _prepPath = widget.path;
    } else {
      _prepare();
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final r = await compute(_prepareJob, widget.path);
      if (!mounted) return;
      if (r == null) {
        setState(() => _error = 'Format gambar tidak didukung');
        return;
      }
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/crop_src_${DateTime.now().microsecondsSinceEpoch}.png');
      await f.writeAsBytes(r[0] as Uint8List, flush: true);
      if (!mounted) return;
      setState(() {
        _prepPath = f.path;
        _iw = r[1] as int;
        _ih = r[2] as int;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal membuka gambar');
    }
  }

  /// Posisi awal: gambar menutupi bingkai, di tengah.
  void _initPosition(Size frame) {
    if (_positioned || _iw == 0) return;
    _positioned = true;
    final cw = _iw * _baseScale;
    final ch = _ih * _baseScale;
    final m = Matrix4.translationValues(-(cw - frame.width) / 2, -(ch - frame.height) / 2, 0);
    // Jangan ubah controller di tengah build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tc.value = m;
    });
  }

  Future<void> _save() async {
    if (widget.isGif) {
      Navigator.pop(context, widget.path);
      return;
    }
    final src = _prepPath;
    if (src == null || _frame == Size.zero) return;
    setState(() => _saving = true);

    // Area yang terlihat di bingkai -> koordinat piksel gambar.
    final m = _tc.value;
    final k = m.getMaxScaleOnAxis();
    final tx = m.getTranslation().x;
    final ty = m.getTranslation().y;
    final s = k * _baseScale;
    var x = (-tx / s).round();
    var y = (-ty / s).round();
    var w = (_frame.width / s).round();
    var h = (_frame.height / s).round();
    x = x.clamp(0, math.max(0, _iw - 1));
    y = y.clamp(0, math.max(0, _ih - 1));
    w = w.clamp(1, _iw - x);
    h = h.clamp(1, _ih - y);

    try {
      final outW = _isAvatar ? 512 : 1280;
      final outH = _isAvatar ? 512 : (1280 / ImageCropScreen.bannerAspect).round();
      final r = await compute(_cropJob, <Object>[src, x, y, w, h, outW, outH]);
      if (r == null) throw Exception();
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/crop_${DateTime.now().microsecondsSinceEpoch}.${r[1]}');
      await out.writeAsBytes(r[0] as Uint8List, flush: true);
      if (mounted) Navigator.pop(context, out.path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Gagal memotong gambar';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _isAvatar ? 'Atur Foto Profil' : 'Atur Banner',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: AppColors.textSecondary))
                    : _prepPath == null
                        ? const CircularProgressIndicator(color: AppColors.accentViolet)
                        : LayoutBuilder(builder: (context, c) => _frameView(c)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.isGif
                    ? 'GIF ditampilkan di tengah dan tidak bisa digeser supaya animasinya tetap utuh.'
                    : 'Geser untuk atur posisi, cubit untuk zoom.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0x59FFFFFF)),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _saving || _prepPath == null || _error != null ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentViolet,
                          shape: const StadiumBorder(),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Pakai', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frameView(BoxConstraints c) {
    final maxW = c.maxWidth - 32;
    final maxH = c.maxHeight - 16;
    double fw;
    double fh;
    if (_isAvatar) {
      fw = math.min(maxW, math.min(maxH, 320));
      fh = fw;
    } else {
      fw = maxW;
      fh = fw / ImageCropScreen.bannerAspect;
    }
    final frame = Size(fw, fh);
    final radius = _isAvatar ? BorderRadius.circular(fw / 2) : BorderRadius.circular(16);

    Widget content;
    if (widget.isGif) {
      content = Image.file(File(_prepPath!), width: fw, height: fh, fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      _frame = frame;
      _baseScale = math.max(fw / _iw, fh / _ih);
      _initPosition(frame);
      content = InteractiveViewer(
        transformationController: _tc,
        constrained: false,
        minScale: 1,
        maxScale: 5,
        boundaryMargin: EdgeInsets.zero,
        clipBehavior: Clip.none,
        child: SizedBox(
          width: _iw * _baseScale,
          height: _ih * _baseScale,
          child: Image.file(File(_prepPath!), fit: BoxFit.fill, gaplessPlayback: true),
        ),
      );
    }

    return Container(
      width: fw,
      height: fh,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(width: fw, height: fh, child: content),
      ),
    );
  }
}

// ---------------------------------------------------------------- isolate

/// Putar sesuai EXIF & kecilkan ke sisi terpanjang 2048 supaya ringan digeser.
List<Object>? _prepareJob(String path) {
  var image = img.decodeImage(File(path).readAsBytesSync());
  if (image == null) return null;
  image = img.bakeOrientation(image);
  const maxSide = 2048;
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }
  return <Object>[Uint8List.fromList(img.encodePng(image, level: 1)), image.width, image.height];
}

/// Potong area [x,y,w,h] lalu ubah ke ukuran akhir [outW]x[outH].
List<Object>? _cropJob(List<Object> a) {
  final image = img.decodeImage(File(a[0] as String).readAsBytesSync());
  if (image == null) return null;
  var out = img.copyCrop(image, x: a[1] as int, y: a[2] as int, width: a[3] as int, height: a[4] as int);
  out = img.copyResize(out, width: a[5] as int, height: a[6] as int, interpolation: img.Interpolation.cubic);
  if (out.hasAlpha) {
    return <Object>[Uint8List.fromList(img.encodePng(out)), 'png'];
  }
  return <Object>[Uint8List.fromList(img.encodeJpg(out, quality: 85)), 'jpg'];
}
