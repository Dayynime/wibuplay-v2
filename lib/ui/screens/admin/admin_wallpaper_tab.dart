import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/wallpaper_models.dart';
import '../../../data/repository/admin_repository.dart' show AdminException;
import '../../../data/repository/wallpaper_repository.dart';
import '../../../providers.dart';
import '../../components/role_badges.dart' show ZenimeRole;

/// Sama dengan AdminRun di admin_screen.dart (loading + banner + refresh).
typedef WallpaperAdminRun = Future<void> Function(
  Future<void> Function() action,
  String okMessage,
);

const Color _border = Color(0x14FFFFFF);

/// Bobot default per rarity saat approve (bisa diubah admin).
const Map<WallpaperRarity, int> _defaultWeight = {
  WallpaperRarity.common: 1000,
  WallpaperRarity.rare: 300,
  WallpaperRarity.epic: 80,
  WallpaperRarity.legendary: 20,
  WallpaperRarity.mythic: 5,
};

const List<(String, String)> _filters = [
  ('pending', 'Pending'),
  ('active', 'Aktif'),
  ('inactive', 'Nonaktif'),
  ('rejected', 'Ditolak'),
  ('removed', 'Takedown'),
];

/// Tab "Wallpaper" di Panel Admin.
///
/// - Moderator: upload (masuk pending) & lihat upload miliknya sendiri.
/// - Admin/Developer: upload, approve (set rarity & bobot), tolak,
///   aktif/nonaktif dari pool spin, edit, takedown.
/// Semua dicek ULANG di server; gating di sini cuma menyembunyikan tombol.
class AdminWallpaperTab extends ConsumerStatefulWidget {
  const AdminWallpaperTab({
    super.key,
    required this.role,
    required this.refresh,
    required this.busy,
    required this.onAction,
  });

  final ZenimeRole role;
  final ValueListenable<int> refresh;
  final bool busy;
  final WallpaperAdminRun onAction;

  @override
  ConsumerState<AdminWallpaperTab> createState() => _AdminWallpaperTabState();
}

class _AdminWallpaperTabState extends ConsumerState<AdminWallpaperTab> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _name = TextEditingController();

  String _filter = 'pending';
  List<AdminWallpaper> _items = const [];
  List<AdminUploadJob> _jobs = const [];
  bool _hasMore = false;
  bool _loading = true;
  String? _error;

  XFile? _picked;
  int _pickedSize = 0;
  double? _progress;

  bool get _canReview => widget.role == ZenimeRole.developer || widget.role == ZenimeRole.admin;

  WallpaperRepository get _repo => ref.read(wallpaperRepositoryProvider);

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_reload);
    Future.microtask(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_reload);
    _name.dispose();
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.adminList(_filter, offset: more ? _items.length : 0);
      if (!mounted) return;
      setState(() {
        _items = more ? [..._items, ...page.items] : page.items;
        _jobs = page.jobs;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is WallpaperException ? e.message : 'Gagal memuat daftar';
      });
    }
  }

  /// Bungkus aksi repo supaya pesan errornya tampil di banner Panel Admin.
  Future<void> _run(Future<void> Function() action, String ok) => widget.onAction(() async {
        try {
          await action();
        } on WallpaperException catch (e) {
          throw AdminException(e.message);
        }
      }, ok);

  // ------------------------------------------------------------ upload

  Future<void> _pick() async {
    // Tanpa maxWidth/quality: kalau di-resize picker, GIF berubah jadi JPEG statis.
    final x = await _picker.pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (x == null || !mounted) return;
    final size = await x.length();
    final mime = await WallpaperRepository.detectMime(x.path);
    if (!mounted) return;
    if (mime == null) {
      _snack('File harus GIF atau WebP (animasi).');
      return;
    }
    if (size > WallpaperRepository.maxUploadBytes) {
      _snack('Ukuran maksimal 5 MB. Kompres dulu file-nya.');
      return;
    }
    setState(() {
      _picked = x;
      _pickedSize = size;
      if (_name.text.trim().isEmpty) {
        final base = x.name.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
        _name.text = base.replaceAll(RegExp(r'[^A-Za-z0-9 ._!?()&+-]'), ' ').trim();
        if (_name.text.length > 40) _name.text = _name.text.substring(0, 40).trim();
      }
    });
  }

  Future<void> _upload() async {
    final x = _picked;
    final name = _name.text.trim();
    if (x == null) return;
    if (name.isEmpty || name.length > 40) {
      _snack('Nama wallpaper 1-40 karakter.');
      return;
    }
    await _run(() async {
      try {
        await _repo.uploadWallpaper(
          filePath: x.path,
          name: name,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
        if (mounted) {
          setState(() {
            _picked = null;
            _name.clear();
          });
        }
      } finally {
        if (mounted) setState(() => _progress = null);
      }
    }, 'Upload berhasil. Server sedang mengonversi, cek di bagian Proses.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------ review

  Future<void> _approveOrEdit(AdminWallpaper w, {required bool approve}) async {
    final r = await showDialog<_ReviewResult>(
      context: context,
      builder: (_) => _ReviewDialog(item: w, approve: approve),
    );
    if (r == null) return;
    await _run(
      () => _repo.adminReview(
        w.id,
        approve ? 'approve' : 'update',
        rarity: r.rarity,
        weight: r.weight,
        name: r.name == w.name ? null : r.name,
      ),
      approve ? 'Wallpaper disetujui & masuk pool spin' : 'Wallpaper diperbarui',
    );
  }

  Future<void> _confirm(AdminWallpaper w, String action, String title, String body, String ok) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title, style: const TextStyle(color: AppColors.textWhite, fontSize: 17)),
        content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() => _repo.adminReview(w.id, action), ok);
  }

  void _openPreview(AdminWallpaper w) {
    final url = w.fileUrl ?? w.previewUrl;
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceDark,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${w.name} • ${w.width ?? '?'}x${w.height ?? '?'} • ${w.frames ?? '?'} frame • '
                '${((w.bytes ?? 0) / 1024).toStringAsFixed(0)} KB',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.accentViolet,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _uploadCard(),
          if (_jobs.isNotEmpty) ...[const SizedBox(height: 12), _jobsCard()],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (key, label) in _filters)
                ChoiceChip(
                  label: Text(label),
                  selected: _filter == key,
                  onSelected: (_) {
                    if (_filter == key) return;
                    setState(() => _filter = key);
                    _load();
                  },
                  selectedColor: AppColors.accentViolet,
                  backgroundColor: AppColors.surfaceDark,
                  labelStyle: TextStyle(
                    color: _filter == key ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  side: const BorderSide(color: _border),
                  showCheckmark: false,
                ),
            ],
          ),
          if (!_canReview)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Sebagai moderator kamu cuma melihat upload milikmu. Upload baru perlu disetujui admin.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          if (_loading && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
            )
          else if (_error != null && _items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Column(
                children: [
                  Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
                  TextButton(onPressed: _load, child: const Text('Coba lagi')),
                ],
              ),
            )
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('Belum ada wallpaper di sini.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else ...[
            for (final w in _items) _itemCard(w),
            if (_hasMore)
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => _load(more: true),
                  child: const Text('Muat lagi'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: child,
      );

  Widget _uploadCard() {
    final picked = _picked;
    final uploading = _progress != null;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wallpaper, color: AppColors.accentViolet, size: 20),
              SizedBox(width: 8),
              Text(
                'Upload Wallpaper',
                style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'GIF / WebP, maks 5 MB, resolusi 160x90 s/d 1920x1920. Server otomatis '
            'mengonversi ke WebP 720px 15fps dan memotong durasi maks 6 detik.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.busy || uploading ? null : _pick,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0x59FFFFFF)),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text(picked == null ? 'Pilih file' : 'Ganti file'),
          ),
          if (picked != null) ...[
            const SizedBox(height: 8),
            Text(
              '${picked.name} • ${(_pickedSize / 1024).toStringAsFixed(0)} KB',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              maxLength: 40,
              enabled: !uploading,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9 ._!?'()&+\-]")),
              ],
              style: const TextStyle(color: AppColors.textWhite),
              decoration: const InputDecoration(
                labelText: 'Nama wallpaper',
                counterStyle: TextStyle(color: AppColors.textMuted),
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            if (uploading) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: _progress, color: AppColors.accentViolet),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.busy || uploading ? null : _upload,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentViolet,
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(uploading ? 'Mengupload ${((_progress ?? 0) * 100).round()}%' : 'Upload'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _jobsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Proses upload kamu',
            style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final j in _jobs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    j.status == 'failed' ? Icons.error_outline : Icons.hourglass_top,
                    size: 16,
                    color: j.status == 'failed' ? AppColors.errorRed : AppColors.warningAmber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      j.status == 'failed'
                          ? '${j.name}: ${j.error ?? 'gagal'}'
                          : '${j.name}: ${j.status == 'queued' ? 'antre' : 'dikonversi'}…',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const Text(
            'Tarik ke bawah untuk memperbarui.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(AdminWallpaper w) {
    final busy = widget.busy;
    final actions = <Widget>[];
    if (_canReview) {
      switch (w.status) {
        case 'pending':
          actions.addAll([
            _action('Setujui', Icons.check, AppColors.successGreen, busy ? null : () => _approveOrEdit(w, approve: true)),
            _action('Tolak', Icons.close, AppColors.errorRed, busy ? null : () => _confirm(w, 'reject', 'Tolak wallpaper?', 'File akan dihapus permanen.', 'Wallpaper ditolak')),
          ]);
        case 'approved':
          actions.addAll([
            _action('Edit', Icons.edit, Colors.white, busy ? null : () => _approveOrEdit(w, approve: false)),
            if (w.isActive)
              _action('Nonaktifkan', Icons.pause_circle_outline, AppColors.warningAmber, busy ? null : () => _confirm(w, 'deactivate', 'Nonaktifkan?', 'Wallpaper keluar dari pool spin, tapi pemiliknya tetap bisa memakai.', 'Wallpaper dinonaktifkan'))
            else
              _action('Aktifkan', Icons.play_circle_outline, AppColors.successGreen, busy ? null : () => _confirm(w, 'activate', 'Aktifkan?', 'Wallpaper masuk lagi ke pool spin.', 'Wallpaper diaktifkan')),
            _action('Takedown', Icons.block, AppColors.errorRed, busy ? null : () => _confirm(w, 'remove', 'Takedown wallpaper?', 'File dihapus dan hilang dari SEMUA komentar (${w.ownerCount} pemilik). Pakai ini untuk konten yang melanggar.', 'Wallpaper di-takedown')),
          ]);
      }
    }

    final statusText = switch (w.status) {
      'pending' => 'Pending',
      'approved' => w.isActive ? 'Aktif' : 'Nonaktif',
      'rejected' => 'Ditolak',
      'removed' => 'Takedown',
      _ => w.status,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openPreview(w),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 120,
                      height: 68,
                      child: w.previewUrl == null
                          ? const ColoredBox(
                              color: AppColors.surfaceVariantDark,
                              child: Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted),
                            )
                          : CachedNetworkImage(
                              imageUrl: w.previewUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  const ColoredBox(color: AppColors.surfaceVariantDark),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _pill(w.rarity.label, w.rarity.color),
                          _pill(statusText, AppColors.textMuted),
                          if (w.status == 'approved') _pill('bobot ${w.weight}', AppColors.textMuted),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'oleh ${w.uploaderName ?? 'Tanpa username'}'
                        '${w.status == 'approved' ? ' • ${w.ownerCount} pemilik' : ''}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  Widget _action(String label, IconData icon, Color color, VoidCallback? onTap) => OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
}

// -------------------------------------------------------------- dialog review

class _ReviewResult {
  const _ReviewResult(this.rarity, this.weight, this.name);

  final WallpaperRarity rarity;
  final int weight;
  final String name;
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.item, required this.approve});

  final AdminWallpaper item;
  final bool approve;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late WallpaperRarity _rarity = widget.item.rarity;
  late final TextEditingController _weight = TextEditingController(
    text: '${widget.approve ? _defaultWeight[widget.item.rarity] : widget.item.weight}',
  );
  late final TextEditingController _name = TextEditingController(text: widget.item.name);
  String? _error;

  @override
  void dispose() {
    _weight.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final w = int.tryParse(_weight.text.trim());
    final n = _name.text.trim();
    if (w == null || w < 1 || w > 100000) {
      setState(() => _error = 'Bobot harus angka 1-100000');
      return;
    }
    if (n.isEmpty || n.length > 40) {
      setState(() => _error = 'Nama 1-40 karakter');
      return;
    }
    Navigator.pop(context, _ReviewResult(_rarity, w, n));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: Text(
        widget.approve ? 'Setujui wallpaper' : 'Edit wallpaper',
        style: const TextStyle(color: AppColors.textWhite, fontSize: 17),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: 40,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9 ._!?'()&+\-]")),
              ],
              style: const TextStyle(color: AppColors.textWhite),
              decoration: const InputDecoration(labelText: 'Nama'),
            ),
            const Text('Rarity', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in WallpaperRarity.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _rarity == r,
                    showCheckmark: false,
                    selectedColor: r.color,
                    backgroundColor: AppColors.surfaceDark,
                    labelStyle: TextStyle(
                      color: _rarity == r ? Colors.white : r.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    onSelected: (_) => setState(() {
                      _rarity = r;
                      if (widget.approve) _weight.text = '${_defaultWeight[r]}';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _weight,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              style: const TextStyle(color: AppColors.textWhite),
              decoration: const InputDecoration(
                labelText: 'Bobot peluang',
                helperText: 'Makin besar makin sering keluar. Peluang = bobot / total bobot pool.',
                helperMaxLines: 2,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.errorRed, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
          onPressed: _submit,
          child: Text(widget.approve ? 'Setujui' : 'Simpan'),
        ),
      ],
    );
  }
}
