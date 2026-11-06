import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/sticker_models.dart';
import '../../../data/repository/sticker_repository.dart';
import '../../../providers.dart';
import '../../components/net_image.dart';
import '../../glass/glass.dart';

/// Upload stiker (khusus Premium) + daftar "Stiker saya" dengan status review.
class StickerUploadScreen extends ConsumerStatefulWidget {
  const StickerUploadScreen({super.key});

  @override
  ConsumerState<StickerUploadScreen> createState() => _StickerUploadScreenState();
}

class _StickerUploadScreenState extends ConsumerState<StickerUploadScreen> {
  final _picker = ImagePicker();
  final _name = TextEditingController();
  final _pack = TextEditingController();
  XFile? _picked;
  int _pickedSize = 0;
  bool _uploading = false;
  double _progress = 0;

  List<MySticker>? _mine;
  String? _mineError;

  StickerRepository get _repo => ref.read(stickerRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void dispose() {
    _name.dispose();
    _pack.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadMine() async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _mineError = 'Login dulu untuk melihat stiker kamu');
      return;
    }
    try {
      final list = await _repo.mine();
      if (mounted) {
        setState(() {
          _mine = list;
          _mineError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _mineError = e.toString());
    }
  }

  Future<void> _pick() async {
    // Tanpa maxWidth/quality: kalau di-resize picker, GIF jadi gambar diam.
    final x = await _picker.pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (x == null || !mounted) return;
    final size = await x.length();
    final mime = await StickerRepository.detectMime(x.path);
    if (!mounted) return;
    if (mime == null) {
      _snack('File harus PNG, JPG, WebP, atau GIF.');
      return;
    }
    if (size > StickerRepository.maxUploadBytes) {
      _snack('Ukuran maksimal 1 MB. Kompres dulu file-nya.');
      return;
    }
    setState(() {
      _picked = x;
      _pickedSize = size;
      if (_name.text.trim().isEmpty) {
        final base = x.name.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
        var n = base.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
        if (n.length > 30) n = n.substring(0, 30).trim();
        _name.text = n;
      }
    });
  }

  Future<void> _upload() async {
    final x = _picked;
    if (x == null || _uploading) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Kasih nama stiker dulu');
      return;
    }
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      await _repo.upload(
        filePath: x.path,
        name: name,
        pack: _pack.text,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _picked = null;
        _name.clear();
      });
      _snack('Stiker terkirim! Tunggu direview developer ya.');
      _loadMine();
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(myPremiumProvider);
    final isPremium = premium.valueOrNull ?? false;

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        title: const Text('Upload Stiker', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: RefreshIndicator(
        color: AppColors.accentViolet,
        onRefresh: _loadMine,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _uploadCard(isPremium, premium.isLoading),
            const SizedBox(height: 22),
            const Text(
              'Stiker saya',
              style: TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ..._mineList(),
          ],
        ),
      ),
    );
  }

  Widget _uploadCard(bool isPremium, bool loading) {
    final picked = _picked;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isPremium && !loading)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1FF5B301),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x55F5B301)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.workspace_premium, color: Color(0xFFF5B301), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Upload stiker khusus pengguna Premium. Semua orang tetap bisa memakai stiker yang sudah disetujui.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          Center(
            child: GestureDetector(
              onTap: isPremium && !_uploading ? _pick : null,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                clipBehavior: Clip.antiAlias,
                child: picked == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 38,
                            color: isPremium ? AppColors.accentVioletLight : AppColors.textMuted,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pilih gambar',
                            style: TextStyle(
                              color: isPremium ? AppColors.textSecondary : AppColors.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(8),
                        child: Image.file(File(picked.path), fit: BoxFit.contain, cacheWidth: 300),
                      ),
              ),
            ),
          ),
          if (picked != null) ...[
            const SizedBox(height: 6),
            Text(
              '${(_pickedSize / 1024).toStringAsFixed(0)} KB · ketuk gambar untuk ganti',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            enabled: isPremium && !_uploading,
            maxLength: 30,
            style: const TextStyle(color: Colors.white),
            cursorColor: AppColors.accentViolet,
            decoration: InputDecoration(
              labelText: 'Nama stiker',
              labelStyle: const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: const Color(0x0DFFFFFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _pack,
            enabled: isPremium && !_uploading,
            maxLength: 24,
            style: const TextStyle(color: Colors.white),
            cursorColor: AppColors.accentViolet,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Pack (opsional)',
              hintText: 'mis. Wowo, Kucing Lucu',
              helperText: 'Stiker sejenis dikumpulkan di satu pack. Kosong = Lainnya',
              helperStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              labelStyle: const TextStyle(color: AppColors.textSecondary),
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: const Color(0x0DFFFFFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          _packSuggestions(isPremium),
          const SizedBox(height: 8),
          if (_uploading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 6,
                color: AppColors.accentViolet,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentViolet,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: isPremium && picked != null && !_uploading ? _upload : null,
            icon: const Icon(Icons.cloud_upload_outlined, size: 20),
            label: Text(_uploading ? 'Mengupload...' : 'Kirim untuk direview'),
          ),
          const SizedBox(height: 10),
          const Text(
            'PNG, JPG, WebP, atau GIF (boleh bergerak), maks 1 MB. Stiker direview developer dulu '
            'sebelum bisa dipakai semua orang. Maks 100 upload per hari.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  /// Pack yang sudah ada di katalog (terbanyak dulu), ketuk = isi kolom pack.
  Widget _packSuggestions(bool enabled) {
    final catalog = ref.watch(stickerCatalogProvider).valueOrNull;
    if (catalog == null) return const SizedBox.shrink();
    final counts = <String, (String, int)>{};
    for (final s in catalog.values) {
      final p = s.pack;
      if (p == null) continue;
      counts.update(p.toLowerCase(), (v) => (v.$1, v.$2 + 1), ifAbsent: () => (p, 1));
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    final list = counts.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    final typed = _pack.text.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (label, n) in list.take(12))
            ActionChip(
              label: Text('$label · $n'),
              onPressed: !enabled || _uploading
                  ? null
                  : () => setState(() => _pack.text = label),
              visualDensity: VisualDensity.compact,
              backgroundColor:
                  typed == label.toLowerCase() ? AppColors.accentViolet : const Color(0x0FFFFFFF),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              labelStyle: TextStyle(
                color: typed == label.toLowerCase() ? Colors.white : AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _mineList() {
    if (_mineError != null) {
      return [
        Text(_mineError!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        TextButton(onPressed: _loadMine, child: const Text('Coba lagi')),
      ];
    }
    final mine = _mine;
    if (mine == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
        ),
      ];
    }
    if (mine.isEmpty) {
      return const [
        Text('Belum ada stiker yang kamu upload.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ];
    }
    return [for (final s in mine) _MyStickerRow(s)];
  }
}

class _MyStickerRow extends StatelessWidget {
  const _MyStickerRow(this.s);

  final MySticker s;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (s.status) {
      'approved' => ('Disetujui', AppColors.successGreen),
      'rejected' => ('Ditolak', const Color(0xFFFF8A98)),
      'removed' => ('Diturunkan', AppColors.textMuted),
      _ => ('Menunggu review', AppColors.warningAmber),
    };
    final url = s.url;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 52,
            child: url != null
                ? NetImage(url, fit: BoxFit.contain)
                : const Icon(Icons.image_outlined, color: AppColors.textMuted, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Pack: ${s.pack ?? kStickerNoPack}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                if (s.rejectReason != null && s.rejectReason!.isNotEmpty && s.status != 'approved')
                  Text(
                    s.rejectReason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
