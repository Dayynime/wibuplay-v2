import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/api/comic_network.dart';
import '../../../data/models/comic_models.dart';
import '../../components/common_components.dart';
import 'comic_reader_controller.dart';

/// Port ComicReaderScreen.kt: baca komik = daftar gambar vertikal selebar
/// layar. Tap layar menyembunyikan/menampilkan bar atas & bawah, tombol
/// prev/next ganti chapter di layar yang sama, dan posisi scroll disimpan
/// (debounce 600 ms) supaya "Lanjutkan Baca" kembali persis ke tempat berhenti.
class ComicReaderScreen extends ConsumerWidget {
  const ComicReaderScreen({super.key, required this.args, required this.onBackClick});

  final ComicReaderArgs args;
  final VoidCallback onBackClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(comicReaderControllerProvider(args));
    final ctrl = ref.read(comicReaderControllerProvider(args).notifier);

    final chapter = ui.chapter;
    final title = (chapter?.title ?? '').trim().isNotEmpty
        ? chapter!.title!
        : extractChapterLabel(ui.currentSlug);

    final Widget body;
    if (ui.error != null) {
      body = Column(
        children: [
          _TopBar(title: title, onBack: onBackClick),
          Expanded(
            child: Center(
              child: ErrorState(
                message: ui.error!,
                onRetry: () => ctrl.loadChapter(ui.currentSlug),
              ),
            ),
          ),
        ],
      );
    } else if (ui.isLoading || chapter == null || ui.initialPosition == null) {
      body = Column(
        children: [
          _TopBar(title: title, onBack: onBackClick),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accentViolet),
            ),
          ),
        ],
      );
    } else {
      body = _ReaderBody(
        // Ganti chapter = state baru (posisi awal & bar di-reset).
        key: ValueKey(ui.currentSlug),
        title: title,
        chapter: chapter,
        initialPosition: ui.initialPosition!,
        onBack: onBackClick,
        onPosition: ctrl.updateScrollPosition,
        onPrev: chapter.prev == null ? null : () => ctrl.loadChapter(chapter.prev!),
        onNext: chapter.next == null ? null : () => ctrl.loadChapter(chapter.next!),
      );
    }

    return Scaffold(backgroundColor: Colors.black, body: body);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderBody extends StatefulWidget {
  const _ReaderBody({
    super.key,
    required this.title,
    required this.chapter,
    required this.initialPosition,
    required this.onBack,
    required this.onPosition,
    required this.onPrev,
    required this.onNext,
  });

  final String title;
  final ComicChapterResponse chapter;
  final (int, double) initialPosition;
  final VoidCallback onBack;
  final void Function(int index, double alignment) onPosition;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  State<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends State<_ReaderBody> {
  final ItemScrollController _items = ItemScrollController();
  final ScrollOffsetController _offset = ScrollOffsetController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  Timer? _debounce;
  bool _showBars = true;

  List<String> get _images => widget.chapter.images ?? const [];

  /// Gambar + satu item penutup (tombol chapter berikutnya).
  int get _itemCount => _images.length + 1;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);

    // Alignment negatif (item sudah tergulir sebagian ke atas) tidak bisa
    // dipakai sebagai initialAlignment, jadi item dibuka dari tepi atasnya
    // lalu digeser sisanya.
    final align = widget.initialPosition.$2;
    if (align < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (!mounted) return;
        final h = MediaQuery.sizeOf(context).height;
        try {
          await _offset.animateScroll(
            offset: -align * h,
            duration: const Duration(milliseconds: 1),
          );
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _positions.itemPositions.removeListener(_onPositions);
    super.dispose();
  }

  void _onPositions() {
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    // Item pertama yang masih kelihatan di layar.
    ItemPosition? first;
    for (final p in positions) {
      if (p.itemTrailingEdge > 0 && (first == null || p.index < first.index)) {
        first = p;
      }
    }
    if (first == null) return;
    final index = first.index;
    final leading = first.itemLeadingEdge;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      widget.onPosition(index, leading > 0 ? 0.0 : leading);
    });
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    if (images.isEmpty) {
      return Column(
        children: [
          _TopBar(title: widget.title, onBack: widget.onBack),
          const Expanded(
            child: Center(
              child: EmptyState(
                title: 'Chapter Kosong',
                subtitle: 'Gambar chapter ini tidak tersedia.',
                icon: Icons.menu_book_outlined,
              ),
            ),
          ),
        ],
      );
    }

    final (startIndex, _) = widget.initialPosition;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showBars = !_showBars),
            child: ScrollablePositionedList.builder(
              itemCount: _itemCount,
              initialScrollIndex: startIndex.clamp(0, _itemCount - 1),
              itemScrollController: _items,
              scrollOffsetController: _offset,
              itemPositionsListener: _positions,
              itemBuilder: (context, i) {
                if (i == images.length) {
                  return _EndOfChapter(
                    onPrev: widget.onPrev,
                    onNext: widget.onNext,
                    bottomInset: bottomInset,
                  );
                }
                return ComicPage(key: ValueKey(images[i]), url: images[i]);
              },
            ),
          ),
        ),
        // Bar atas
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_showBars,
            child: AnimatedSlide(
              offset: _showBars ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _showBars ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: _TopBar(title: widget.title, onBack: widget.onBack),
              ),
            ),
          ),
        ),
        // Bar bawah: sebelumnya / berikutnya
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_showBars,
            child: AnimatedSlide(
              offset: _showBars ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _showBars ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.88),
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
                  child: Row(
                    children: [
                      Expanded(
                        child: _NavButton(
                          icon: Icons.chevron_left_rounded,
                          label: 'Sebelumnya',
                          onTap: widget.onPrev,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NavButton(
                          icon: Icons.chevron_right_rounded,
                          label: 'Berikutnya',
                          trailingIcon: true,
                          onTap: widget.onNext,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingIcon = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool trailingIcon;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? Colors.white : Colors.white.withValues(alpha: 0.3);
    final text = Text(
      label,
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
    );
    return Material(
      color: enabled ? AppColors.accentViolet : AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: trailingIcon
                ? [text, Icon(icon, color: color, size: 22)]
                : [Icon(icon, color: color, size: 22), text],
          ),
        ),
      ),
    );
  }
}

class _EndOfChapter extends StatelessWidget {
  const _EndOfChapter({
    required this.onPrev,
    required this.onNext,
    required this.bottomInset,
  });

  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 32, 24, 32 + bottomInset),
      child: Column(
        children: [
          const Text(
            'Akhir chapter',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (onNext != null)
            _NavButton(
              icon: Icons.chevron_right_rounded,
              label: 'Chapter berikutnya',
              trailingIcon: true,
              onTap: onNext,
            )
          else
            const Text(
              'Belum ada chapter berikutnya',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
          if (onPrev != null) ...[
            const SizedBox(height: 10),
            _NavButton(
              icon: Icons.chevron_left_rounded,
              label: 'Chapter sebelumnya',
              onTap: onPrev,
            ),
          ],
        ],
      ),
    );
  }
}

/// Satu halaman komik: selebar layar, tinggi mengikuti rasio gambar.
/// Placeholder rasio 0.7 supaya list tidak loncat saat gambar masuk. Gagal
/// dimuat -> otomatis coba lagi 2x (jeda 2 dtk), lalu tap manual.
class ComicPage extends StatefulWidget {
  const ComicPage({super.key, required this.url});

  final String url;

  @override
  State<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends State<ComicPage> {
  static const int _maxAutoRetry = 2;

  int _attempt = 0;
  int _autoRetries = 0;
  Timer? _retryTimer;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _onError(Object error) {
    if (_autoRetries >= _maxAutoRetry || _retryTimer?.isActive == true) return;
    _autoRetries++;
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _attempt++);
    });
  }

  void _manualRetry() {
    _autoRetries = 0;
    setState(() => _attempt++);
  }

  String _reason(Object error) {
    try {
      final code = (error as dynamic).statusCode;
      if (code is int) return 'Kode $code';
    } catch (_) {}
    return 'Periksa koneksi';
  }

  @override
  Widget build(BuildContext context) {
    final url = ComicNetwork.normalizeImageUrl(widget.url);
    if (url == null) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final px = (mq.size.width * mq.devicePixelRatio).round().clamp(360, 1440);

    return CachedNetworkImage(
      key: ValueKey('$url#$_attempt'),
      imageUrl: url,
      httpHeaders: ComicNetwork.imageHeaders,
      width: double.infinity,
      fit: BoxFit.fitWidth,
      memCacheWidth: px,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: Duration.zero,
      errorListener: _onError,
      placeholder: (_, __) => const AspectRatio(
        aspectRatio: 0.7,
        child: ColoredBox(
          color: Color(0xFF0B0B10),
          child: Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.accentViolet,
              ),
            ),
          ),
        ),
      ),
      errorWidget: (_, __, error) => GestureDetector(
        onTap: _manualRetry,
        child: AspectRatio(
          aspectRatio: 0.7,
          child: ColoredBox(
            color: const Color(0xFF0B0B10),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined,
                      color: AppColors.textMuted, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'Gagal memuat gambar (${_reason(error)})',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ketuk untuk coba lagi',
                    style: TextStyle(
                      color: AppColors.accentViolet,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
