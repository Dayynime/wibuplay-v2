import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'role_badges.dart';
import 'avatar_frame.dart';

/// Avatar bulat: foto kalau ada, kalau tidak avatar otomatis (warna + inisial).
class FriendAvatar extends StatelessWidget {
  const FriendAvatar({
    super.key,
    required this.url,
    required this.seed,
    required this.label,
    required this.size,
    this.framed = true,
  });

  final String? url;

  /// firebase_uid pemilik avatar (juga dipakai untuk warna avatar otomatis).
  final String seed;
  final String label;
  final double size;

  /// Tampilkan border avatar milik [seed].
  final bool framed;

  @override
  Widget build(BuildContext context) {
    if (framed && seed.isNotEmpty) {
      return FramedAvatar(
        uid: seed,
        size: size,
        child: FriendAvatar(url: url, seed: seed, label: label, size: size, framed: false),
      );
    }
    final has = url != null && url!.isNotEmpty;
    final fallback = GeneratedAvatar(seed: seed, label: label, size: size);
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.surfaceVariantDark,
          child: has
              ? CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }
}
