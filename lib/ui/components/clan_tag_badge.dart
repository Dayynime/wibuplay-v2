import 'package:flutter/material.dart';

import '../../data/clan_badge_cache.dart';
import 'clan_badge_styles.dart';
import 'game_badges.dart' show ClanRainbowBadge;
import 'profile_badges.dart' show ClanNameTag;

/// Badge yang dimiliki app versi ini. Id lain (desain baru di server yang
/// belum ada di app lama) jatuh ke tampilan bawaan, bukan ke gaya acak.
ClanBadgeStyle? clanBadgeStyleOrNull(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final s in ClanBadgeStyle.values) {
    if (s.id == id) return s;
  }
  return null;
}

/// Tag clan dengan badge yang dipasang clan itu (lihat [ClanStyledBadge]).
/// Clan yang belum memasang badge tampil seperti sebelumnya:
/// [ClanRainbowBadge] (atau [ClanNameTag] kalau [nameTag] = true).
///
/// Pakai [ClanTagBadge] kalau cuma tahu teks tag (badge dicari lewat
/// [ClanBadgeCache]); pakai [ClanTagBadge.known] kalau badge clan sudah
/// diketahui (mis. dari objek Clan) supaya tidak perlu request lagi.
class ClanTagBadge extends StatelessWidget {
  const ClanTagBadge({
    super.key,
    required this.text,
    this.height,
    this.onTap,
    this.nameTag = false,
  })  : styleId = null,
        _known = false;

  const ClanTagBadge.known({
    super.key,
    required this.text,
    required this.styleId,
    this.height,
    this.onTap,
    this.nameTag = false,
  }) : _known = true;

  final String text;

  /// Tinggi badge; null = ukuran bawaan (16 untuk badge khusus).
  final double? height;
  final VoidCallback? onTap;

  /// Tampilan bawaan pakai [ClanNameTag] (header profil), bukan [ClanRainbowBadge].
  final bool nameTag;
  final String? styleId;
  final bool _known;

  @override
  Widget build(BuildContext context) {
    if (_known) {
      ClanBadgeCache.instance.prime(text, styleId);
      return _render(clanBadgeStyleOrNull(styleId));
    }
    final cache = ClanBadgeCache.instance;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) => _render(clanBadgeStyleOrNull(cache.styleFor(text))),
    );
  }

  Widget _render(ClanBadgeStyle? style) {
    if (style != null) {
      return ClanStyledBadge(
        key: ValueKey(style),
        text: text.toUpperCase(),
        style: style,
        height: height ?? 16,
        onTap: onTap,
      );
    }
    if (nameTag) return ClanNameTag(text: text, height: height ?? 20, onTap: onTap);
    final badge = ClanRainbowBadge(text: text, height: height);
    return onTap == null ? badge : GestureDetector(onTap: onTap, child: badge);
  }
}
