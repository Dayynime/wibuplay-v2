import '../../core/constants.dart';

class MediaGalleryItem {
  const MediaGalleryItem({this.id, this.image, this.title});

  final String? id;
  final String? image;
  final String? title;

  String get fullImageUrl => buildFullUrl(image);
}
