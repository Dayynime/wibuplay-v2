import '../../core/constants.dart';

class EpisodeItem {
  const EpisodeItem({
    this.id,
    this.index,
    this.image,
    this.title,
    this.views,
    this.isNew,
  });

  final String? id;
  final String? index;
  final String? image;
  final String? title;
  final String? views;

  /// Dibiarkan dynamic (server tidak konsisten: bool/int/string).
  final dynamic isNew;

  String get imageUrl => buildFullUrl(image);
}
