import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/sticker_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/net_image.dart';
import 'sticker_upload_screen.dart';

// ============================================================================
// Stiker di pesan
// ============================================================================

/// Gambar stiker untuk pesan yang isinya "[stiker:KODE]".
/// Kode yang tidak ada di katalog (belum/tidak disetujui) tampil sebagai teks.
class StickerView extends ConsumerWidget {
  const StickerView({super.key, required this.code, this.size = 120});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stickerByCodeProvider(code));
    return s.when(
      loading: () => SizedBox.square(
        dimension: size,
        child: Center(
          child: Icon(Icons.image_outlined, size: size * 0.3, color: AppColors.textMuted),
        ),
      ),
      error: (_, __) => _missing(),
      data: (st) {
        if (st == null) return _missing();
        return Semantics(
          label: 'Stiker ${st.name}',
          image: true,
          child: SizedBox.square(
            dimension: size,
            child: NetImage(st.url, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  Widget _missing() => const Text(
        '🖼️ Stiker tidak tersedia',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
      );
}

// ============================================================================
// Tombol stiker di kolom ketik
// ============================================================================

/// Tombol ikon stiker. [onPicked] menerima teks pesan stiker siap kirim.
class StickerButton extends StatelessWidget {
  const StickerButton({super.key, required this.onPicked, this.enabled = true, this.size = 40});

  final ValueChanged<String> onPicked;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: 'Stiker',
        padding: EdgeInsets.zero,
        onPressed: !enabled
            ? null
            : () async {
                final code = await showStickerPicker(context);
                if (code != null) onPicked(stickerMessage(code));
              },
        icon: const Icon(Icons.emoji_emotions_outlined, color: AppColors.textSecondary, size: 24),
      ),
    );
  }
}

// ============================================================================
// Lembar pilih stiker
// ============================================================================

const String _kRecentKey = 'sticker_recent_v1';
const int _kRecentMax = 16;

Future<List<String>> _loadRecent() async {
  try {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kRecentKey) ?? const [];
  } catch (_) {
    return const [];
  }
}

Future<void> _pushRecent(String code) async {
  try {
    final p = await SharedPreferences.getInstance();
    final list = [code, ...(p.getStringList(_kRecentKey) ?? const <String>[]).where((c) => c != code)];
    await p.setStringList(_kRecentKey, list.take(_kRecentMax).toList());
  } catch (_) {}
}

/// Buka lembar stiker. Return kode stiker yang dipilih (null = batal).
Future<String?> showStickerPicker(BuildContext context) {
  FocusScope.of(context).unfocus();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _StickerSheet(),
  );
}

class _StickerSheet extends ConsumerStatefulWidget {
  const _StickerSheet();

  @override
  ConsumerState<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends ConsumerState<_StickerSheet> {
  List<String> _recent = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Muat ulang katalog tiap lembar dibuka (stiker baru langsung muncul).
    Future.microtask(() => ref.invalidate(stickerCatalogProvider));
    unawaited(_loadRecent().then((r) {
      if (mounted) setState(() => _recent = r);
    }));
  }

  void _pick(Sticker s) {
    HapticFeedback.selectionClick();
    unawaited(_pushRecent(s.code));
    Navigator.pop(context, s.code);
  }

  Future<void> _openUpload() async {
    final nav = Navigator.of(context);
    nav.pop();
    await nav.push<void>(fadeRoute(const StickerUploadScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final catalog = ref.watch(stickerCatalogProvider);
    final q = _query.trim().toLowerCase();

    Widget body = catalog.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Stiker gagal dimuat', style: TextStyle(color: AppColors.textSecondary)),
            TextButton(
              onPressed: () => ref.invalidate(stickerCatalogProvider),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
      data: (map) {
        if (map.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 32),
            child: Text(
              'Belum ada stiker. Pengguna Premium bisa upload stiker sendiri lewat tombol + di atas!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          );
        }
        final all = map.values.where((s) => q.isEmpty || s.name.toLowerCase().contains(q)).toList();
        final recent = q.isEmpty ? _recent.map((c) => map[c]).whereType<Sticker>().toList() : const <Sticker>[];
        return CustomScrollView(
          shrinkWrap: true,
          slivers: [
            if (recent.isNotEmpty) ...[
              _label('Terakhir dipakai'),
              _grid(recent),
            ],
            _label(q.isEmpty ? 'Semua stiker' : 'Hasil pencarian'),
            if (all.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Tidak ada stiker dengan nama itu.', style: TextStyle(color: AppColors.textSecondary)),
                ),
              )
            else
              _grid(all),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          ],
        );
      },
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * 0.7),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      'Stiker',
                      style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _openUpload,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text('Upload'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  cursorColor: AppColors.accentViolet,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cari stiker',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: const Color(0x0FFFFFFF),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      );

  Widget _grid(List<Sticker> list) => SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final s = list[i];
          return Tooltip(
            message: s.name,
            child: Material(
              color: const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _pick(s),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: NetImage(s.url, fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      );
}
