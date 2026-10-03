import '../../core/constants.dart';

class CuplixItem {
  const CuplixItem({
    required this.id,
    this.caption,
    this.urlThumbnail,
    this.idEpisode,
    this.idMovie,
    this.anime,
    this.episode,
    this.timeStart,
    this.timeEnd,
    this.countViews,
    this.countLikes,
    this.countComments,
    this.username,
  });

  final String id;
  final String? caption;
  final String? urlThumbnail;
  final String? idEpisode;
  final String? idMovie;
  final String? anime;
  final String? episode;
  final String? timeStart;
  final String? timeEnd;
  final String? countViews;
  final String? countLikes;
  final String? countComments;
  final String? username;

  String get thumbnailUrl => buildFullUrl(urlThumbnail);

  int get timeStartMs => int.tryParse(timeStart ?? '') ?? 0;
  int get timeEndMs => int.tryParse(timeEnd ?? '') ?? 0;
}
