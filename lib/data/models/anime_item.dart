import '../../core/constants.dart';

class AnimeItem {
  const AnimeItem({
    this.id,
    this.title,
    this.synopsis,
    this.genre,
    this.status,
    this.type,
    this.year,
    this.day,
    this.views,
    this.favorites,
    this.imagePoster,
    this.imageCover,
    this.studio,
    this.airedStart,
    this.airedEnd,
    this.time,
    this.keyTime,
  });

  final String? id;
  final String? title;
  final String? synopsis;
  final String? genre;
  final String? status;
  final String? type;
  final String? year;
  final String? day;
  final String? views;
  final String? favorites;
  final String? imagePoster;
  final String? imageCover;
  final String? studio;
  final String? airedStart;
  final String? airedEnd;

  /// Teks relatif dari server (mis. "2 jam lagi") dan jam tayang
  /// "yyyy-MM-dd HH:mm:ss". Dipakai halaman jadwal.
  final String? time;
  final String? keyTime;

  String get posterUrl => buildFullUrl(imagePoster);

  /// Cover jatuh ke poster kalau kosong (sama seperti getCoverUrl() Kotlin).
  String get coverUrl => buildFullUrl(imageCover ?? imagePoster);
}
