import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/sticker_models.dart';
import '../../../data/repository/admin_repository.dart' show AdminException;
import '../../../data/repository/sticker_repository.dart';
import '../../../providers.dart';
import '../../components/net_image.dart';

/// Sama dengan AdminRun di admin_screen.dart (loading + banner + refresh).
typedef StickerAdminRun = Future<void> Function(
  Future<void> Function() action,
  String okMessage,
);

const List<(String, String)> _filters = [
  ('pending', 'Menunggu'),
  ('approved', 'Aktif'),
  ('rejected', 'Ditolak'),
  ('removed', 'Diturunkan'),
];

/// Tab "Stiker" di Panel Admin (developer & admin): setujui / tolak stiker
/// upload user Premium, dan turunkan stiker aktif. Server mengecek ulang role.
class AdminStickerTab extends ConsumerStatefulWidget {
  const AdminStickerTab({
    super.key,
    required this.refresh,
    required this.busy,
    required this.onAction,
  });

  final ValueListenable<int> refresh;
  final bool busy;
  final StickerAdminRun onAction;

  @override
  ConsumerState<AdminStickerTab> createState() => _AdminStickerTabState();
}

class _AdminStickerTabState extends ConsumerState<AdminStickerTab> {
  String _filter = 'pending';
  List<AdminSticker> _items = const [];
  bool _loading = true;
  bool _hasMore = false;
  String? _error;

  StickerRepository get _repo => ref.read(stickerRepositoryProvider);

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
        _items = more ? [..._items, ...page] : page;
        _hasMore = page.length >= 30;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is StickerException ? e.message : 'Gagal memuat daftar';
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String ok) => widget.onAction(() async {
        try {
          await action();
        } on StickerException catch (e) {
          throw AdminException(e.message);
        }
        ref.invalidate(stickerCatalogProvider);
      }, ok);

  Future<String?> _askReason(String title, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: c,
          maxLength: 120,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Kirim', style: TextStyle(color: Color(0xFFFF8A98))),
          ),
        ],
      ),
    ).whenComplete(c.dispose);
  }

  Future<void> _approve(AdminSticker s) =>
      _run(() => _repo.adminReview(s.id, 'approve'), 'Stiker "${s.name}" disetujui');

  Future<void> _reject(AdminSticker s) async {
    final reason = await _askReason('Tolak stiker?', 'Alasan (dikirim ke pembuat)');
    if (reason == null) return;
    await _run(() => _repo.adminReview(s.id, 'reject', reason: reason), 'Stiker "${s.name}" ditolak');
  }

  Future<void> _remove(AdminSticker s) async {
    final reason = await _askReason('Turunkan stiker?', 'Alasan (opsional)');
    if (reason == null) return;
    await _run(() => _repo.adminReview(s.id, 'remove', reason: reason), 'Stiker "${s.name}" diturunkan');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              for (final (id, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _filter == id,
                    onSelected: (_) {
                      if (_filter == id) return;
                      setState(() => _filter = id);
                      _load();
                    },
                    selectedColor: AppColors.accentViolet,
                    backgroundColor: AppColors.surfaceDark,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: _filter == id ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3));
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            TextButton(onPressed: _load, child: const Text('Coba lagi')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _filter == 'pending' ? 'Tidak ada stiker yang menunggu review.' : 'Kosong.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accentViolet,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return TextButton(
              onPressed: _loading ? null : () => _load(more: true),
              child: const Text('Muat lebih banyak'),
            );
          }
          return _card(_items[i]);
        },
      ),
    );
  }

  Widget _card(AdminSticker s) {
    final url = s.imageUrl;
    final kb = s.sizeBytes == null ? '' : ' · ${(s.sizeBytes! / 1024).toStringAsFixed(0)} KB';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(6),
            child: url == null
                ? const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted)
                : NetImage(url, fit: BoxFit.contain),
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
                  style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'oleh ${s.uploaderName}$kb',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                Text(
                  'Pack: ${s.pack ?? kStickerNoPack}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                ),
                Text(
                  'Kode ${s.code}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                if (s.rejectReason != null && s.rejectReason!.isNotEmpty)
                  Text(
                    'Alasan: ${s.rejectReason}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                const SizedBox(height: 8),
                if (s.status == 'pending')
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.busy ? null : () => _reject(s),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF8A98),
                            side: const BorderSide(color: Color(0x66FF5468)),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Tolak'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: widget.busy || url == null ? null : () => _approve(s),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.successGreen,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Setujui'),
                        ),
                      ),
                    ],
                  )
                else if (s.status == 'approved')
                  OutlinedButton.icon(
                    onPressed: widget.busy ? null : () => _remove(s),
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    label: const Text('Turunkan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF8A98),
                      side: const BorderSide(color: Color(0x66FF5468)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
