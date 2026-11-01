import 'package:flutter/material.dart';

import '../../data/level_badge_cache.dart';
import 'game_badges.dart' show LevelBadge;
import 'level_badge_styles.dart';
import 'profile_badges.dart' show LevelPin;

/// Gaya badge level yang dikenal app versi ini; id lain jatuh ke bawaan.
LevelBadgeStyle? levelBadgeStyleOrNull(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final s in LevelBadgeStyle.values) {
    if (s.id == id) return s;
  }
  return null;
}

/// Badge level milik user [uid]: pakai gaya yang dibeli user itu di shop
/// ([LevelStyledBadge]), atau badge level bawaan kalau belum memasang.
class UserLevelBadge extends StatelessWidget {
  const UserLevelBadge({
    super.key,
    required this.uid,
    required this.level,
    this.height,
    this.progress,
    this.pin = false,
  });

  final String uid;
  final int level;

  /// Tinggi badge; null = ukuran bawaan (16 untuk badge dari shop).
  final double? height;

  /// Progress XP ke level berikutnya (0..1) untuk gaya Hex Core / Energy Bar.
  final double? progress;

  /// Tampilan bawaan pakai [LevelPin] (pin di bawah avatar profil).
  final bool pin;

  @override
  Widget build(BuildContext context) {
    final cache = LevelBadgeCache.instance;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        final style = uid.isEmpty ? null : levelBadgeStyleOrNull(cache.styleFor(uid));
        if (style != null) {
          return LevelStyledBadge(
            key: ValueKey(style),
            level: level,
            style: style,
            height: height ?? 16,
            progress: progress,
          );
        }
        if (pin) return LevelPin(level: level, height: height ?? 22);
        return LevelBadge(level: level, height: height);
      },
    );
  }
}
