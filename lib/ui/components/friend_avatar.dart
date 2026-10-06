import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'role_badges.dart';

/// Avatar bulat: foto kalau ada, kalau tidak avatar otomatis (warna + inisial).
class FriendAvatar extends StatelessWidget {
  const FriendAvatar({
    super.key,
    required this.url,
    required this.seed,
    required this.label,
    required this.size,
  });

  final String? url;
  final String seed;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
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
