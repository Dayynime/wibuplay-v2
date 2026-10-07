/// Model komik (port ComicModels.kt). Dipakai bareng oleh semua sumber:
/// tiap sumber (Bacakomik, Westmanga) dipetakan ke model ini, jadi layar
/// Komik / Detail / Reader tidak perlu tahu datanya dari mana.

String? _str(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return null;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

List<Map<String, dynamic>> _maps(Object? v) => (v is List ? v : const [])
    .whereType<Map>()
    .map((m) => Map<String, dynamic>.from(m))
    .toList();

/// Satu kartu komik di daftar (latest / populer / search / genre).
class ComicListItem {
  const ComicListItem({
    this.title = '',
    this.slug = '',
    this.cover,
    this.chapter,
    this.date,
    this.rating,
    this.type,
  });

  final String title;
  final String slug;
  final String? cover;
  final String? chapter;
  final String? date;
  final String? rating;
  final String? type;

  ComicListItem copyWith({String? slug}) => ComicListItem(
        title: title,
        slug: slug ?? this.slug,
        cover: cover,
        chapter: chapter,
        date: date,
        rating: rating,
        type: type,
      );

  factory ComicListItem.fromJson(Map<String, dynamic> j) => ComicListItem(
        title: _str(j['title']) ?? '',
        slug: _str(j['slug']) ?? '',
        cover: _str(j['cover']),
        chapter: _str(j['chapter']),
        date: _str(j['date']),
        rating: _str(j['rating']),
        type: _str(j['type']),
      );
}

class ComicListResponse {
  const ComicListResponse({
    this.komikList,
    this.hasNextPage,
    this.currentPage,
  });

  final List<ComicListItem>? komikList;
  final bool? hasNextPage;
  final int? currentPage;

  ComicListResponse copyWith({List<ComicListItem>? komikList}) => ComicListResponse(
        komikList: komikList ?? this.komikList,
        hasNextPage: hasNextPage,
        currentPage: currentPage,
      );

  factory ComicListResponse.fromJson(Map<String, dynamic> j) => ComicListResponse(
        komikList: _maps(j['komikList']).map(ComicListItem.fromJson).toList(),
        hasNextPage: j['hasNextPage'] is bool ? j['hasNextPage'] as bool : null,
        currentPage: _int(j['currentPage']),
      );
}

class ComicGenreRef {
  const ComicGenreRef({this.title = '', this.slug = ''});

  final String title;
  final String slug;

  factory ComicGenreRef.fromJson(Map<String, dynamic> j) =>
      ComicGenreRef(title: _str(j['title']) ?? '', slug: _str(j['slug']) ?? '');
}

/// PENTING: field `title` chapter dari Bacakomik SELALU kosong; nomor chapter
/// diambil dari slug lewat [extractChapterLabel].
class ComicChapterRef {
  const ComicChapterRef({this.title = '', this.slug = '', this.date});

  final String title;
  final String slug;
  final String? date;

  /// Pakai `title` kalau sumbernya mengisi (Westmanga), kalau kosong
  /// (Bacakomik) diekstrak dari slug.
  String get displayLabel => title.trim().isNotEmpty ? title : extractChapterLabel(slug);

  factory ComicChapterRef.fromJson(Map<String, dynamic> j) => ComicChapterRef(
        title: _str(j['title']) ?? '',
        slug: _str(j['slug']) ?? '',
        date: _str(j['date']),
      );
}

class ComicDetail {
  const ComicDetail({
    this.title,
    this.cover,
    this.rating,
    this.otherTitle,
    this.status,
    this.type,
    this.author,
    this.artist,
    this.release,
    this.series,
    this.reader,
    this.synopsis,
    this.genres,
    this.chapters,
  });

  final String? title;
  final String? cover;
  final String? rating;
  final String? otherTitle;
  final String? status;
  final String? type;
  final String? author;
  final String? artist;
  final String? release;
  final String? series;
  final String? reader;
  final String? synopsis;
  final List<ComicGenreRef>? genres;
  final List<ComicChapterRef>? chapters;

  factory ComicDetail.fromJson(Map<String, dynamic> j) => ComicDetail(
        title: _str(j['title']),
        cover: _str(j['cover']),
        rating: _str(j['rating']),
        otherTitle: _str(j['otherTitle']),
        status: _str(j['status']),
        type: _str(j['type']),
        author: _str(j['author']),
        artist: _str(j['artist']),
        release: _str(j['release']),
        series: _str(j['series']),
        reader: _str(j['reader']),
        synopsis: _str(j['synopsis']),
        genres: _maps(j['genres']).map(ComicGenreRef.fromJson).toList(),
        chapters: _maps(j['chapters']).map(ComicChapterRef.fromJson).toList(),
      );
}

/// Isi satu chapter (daftar URL gambar + navigasi prev/next).
class ComicChapterResponse {
  const ComicChapterResponse({this.title, this.images, this.next, this.prev});

  final String? title;
  final List<String>? images;
  final String? next;
  final String? prev;

  factory ComicChapterResponse.fromJson(Map<String, dynamic> j) {
    final nav = j['navigation'] is Map
        ? Map<String, dynamic>.from(j['navigation'] as Map)
        : const <String, dynamic>{};
    return ComicChapterResponse(
      title: _str(j['title']),
      images: (j['images'] is List ? j['images'] as List : const [])
          .whereType<String>()
          .toList(),
      next: _str(nav['next']),
      prev: _str(nav['prev']),
    );
  }
}

class ComicGenreItem {
  const ComicGenreItem({this.title = '', this.slug = ''});

  final String title;
  final String slug;

  factory ComicGenreItem.fromJson(Map<String, dynamic> j) =>
      ComicGenreItem(title: _str(j['title']) ?? '', slug: _str(j['slug']) ?? '');
}

/// Nomor/label chapter dari slug, karena `title` dari Bacakomik selalu kosong.
///   "nano-machine-chapter-325"       -> "Chapter 325"
///   "one-piece-chapter-1052-5"       -> "Chapter 1052.5" (selingan/desimal)
///   "judul-chapter-179-5-bahasa-indonesia" -> "Chapter 179.5"
String extractChapterLabel(String slug) {
  final match = RegExp(
    r'chapter-([0-9]+(?:-[0-9]+)?)(?:-bahasa-indonesia)?(?:\.[0-9]+)*$',
  ).firstMatch(slug);
  if (match == null) {
    final t = slug.replaceAll('-', ' ');
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }
  final parts = match.group(1)!.split('-');
  final number = parts.length == 2 ? '${parts[0]}.${parts[1]}' : parts[0];
  return 'Chapter $number';
}
