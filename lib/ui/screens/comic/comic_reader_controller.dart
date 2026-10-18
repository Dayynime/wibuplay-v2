import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/comic/comic_providers.dart';
import '../../../data/models/comic_models.dart';
import '../../../data/repository/comic_repository.dart';

/// Argumen reader: chapter yang dibuka + komik asalnya.
class ComicReaderArgs {
  const ComicReaderArgs({
    required this.chapterSlug,
    required this.comicKey,
    this.title,
    this.cover,
  });

  final String chapterSlug;
  final String comicKey;
  final String? title;
  final String? cover;

  @override
  bool operator ==(Object other) =>
      other is ComicReaderArgs &&
      other.chapterSlug == chapterSlug &&
      other.comicKey == comicKey &&
      other.title == title &&
      other.cover == cover;

  @override
  int get hashCode => Object.hash(chapterSlug, comicKey, title, cover);
}

class ComicReaderState {
  const ComicReaderState({
    required this.currentSlug,
    this.chapter,
    this.isLoading = true,
    this.error,
    this.initialPosition,
  });

  /// Slug chapter yang sedang terbaca: dipakai buat judul & tombol prev/next.
  final String currentSlug;
  final ComicChapterResponse? chapter;
  final bool isLoading;
  final String? error;

  /// (indeks item, alignment) awal buat chapter yang dibuka SEKARANG.
  /// null = masih menunggu data progress tersimpan. Dipulihkan HANYA kalau
  /// masuk persis di chapter yang sama dengan progress terakhir (mis. lewat
  /// "Lanjutkan Baca"); buka chapter lain manual selalu mulai dari atas.
  final (int, double)? initialPosition;

  ComicReaderState copyWith({
    String? currentSlug,
    ComicChapterResponse? chapter,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearChapter = false,
    (int, double)? initialPosition,
  }) {
    return ComicReaderState(
      currentSlug: currentSlug ?? this.currentSlug,
      chapter: clearChapter ? null : (chapter ?? this.chapter),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      initialPosition: initialPosition ?? this.initialPosition,
    );
  }
}

/// Port ComicReaderViewModel.kt.
class ComicReaderController
    extends AutoDisposeFamilyNotifier<ComicReaderState, ComicReaderArgs> {
  bool _alive = true;
  int _token = 0;

  ComicRepository get _repo => ref.read(comicRepositoryProvider);

  @override
  ComicReaderState build(ComicReaderArgs arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future.microtask(_init);
    return ComicReaderState(currentSlug: arg.chapterSlug);
  }

  Future<void> _init() async {
    final saved = await _repo.getProgressOnce(arg.comicKey);
    if (!_alive) return;
    final pos = (saved != null && saved.chapterSlug == arg.chapterSlug)
        ? (saved.scrollItemIndex, saved.scrollAlignment)
        : (0, 0.0);
    state = state.copyWith(initialPosition: pos);
    await _fetch(arg.chapterSlug);
  }

  void loadChapter(String chapterSlug) {
    state = ComicReaderState(
      currentSlug: chapterSlug,
      initialPosition: (0, 0.0),
    );
    _fetch(chapterSlug);
  }

  Future<void> _fetch(String chapterSlug) async {
    final token = ++_token;
    try {
      final res = await _repo.getChapter(arg.comicKey, chapterSlug);
      if (!_alive || token != _token) return;
      state = state.copyWith(chapter: res, isLoading: false, clearError: true);
      final label = _labelOf(res, chapterSlug);
      final pos = state.initialPosition ?? (0, 0.0);
      _persist(chapterSlug, label, pos.$1, pos.$2);
    } catch (e) {
      if (!_alive || token != _token) return;
      state = state.copyWith(
        isLoading: false,
        clearChapter: true,
        error: errorMessage(e, 'Gagal memuat chapter.'),
      );
    }
  }

  String _labelOf(ComicChapterResponse? chapter, String slug) {
    final t = chapter?.title;
    return t != null && t.trim().isNotEmpty ? t : extractChapterLabel(slug);
  }

  /// Dipanggil layar tiap posisi scroll berubah (sudah di-debounce di sisi
  /// UI), biar "Lanjutkan Baca" balik ke posisi yang persis sama.
  void updateScrollPosition(int index, double alignment) {
    if (!_alive || state.chapter == null) return;
    _persist(state.currentSlug, _labelOf(state.chapter, state.currentSlug), index, alignment);
  }

  void _persist(String chapterSlug, String label, int index, double alignment) {
    _repo.saveProgress(
      comicSlug: arg.comicKey,
      comicTitle: arg.title ?? arg.comicKey,
      comicCover: arg.cover,
      chapterSlug: chapterSlug,
      chapterLabel: label,
      scrollItemIndex: index,
      scrollAlignment: alignment,
    );
  }
}

final comicReaderControllerProvider = NotifierProvider.autoDispose
    .family<ComicReaderController, ComicReaderState, ComicReaderArgs>(
  ComicReaderController.new,
);
