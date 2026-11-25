import 'package:flutter/material.dart';

import '../../data/name_deco_cache.dart';
import 'name_deco_styles.dart';

/// Nama user [uid]: pakai Dekorasi Nama yang dibeli user itu di shop
/// ([NameDecoText]), atau [Text] biasa dengan [style] kalau belum memasang.
///
/// Dekorasi beranimasi di semua tempat (chat, komentar, profil, leaderboard,
/// teman, clan); [animate] = false menggambarnya diam. Animasi otomatis
/// berhenti kalau "kurangi animasi" di HP aktif.
class UserNameText extends StatelessWidget {
  const UserNameText({
    super.key,
    required this.uid,
    required this.name,
    required this.style,
    this.animate = true,
    this.maxLines = 1,
    this.textAlign,
    this.decoScale = 1,
  });

  final String uid;
  final String name;

  /// Gaya teks nama biasa; ukuran hurufnya juga dipakai untuk dekorasi.
  final TextStyle style;
  final bool animate;
  final int maxLines;
  final TextAlign? textAlign;

  /// Pengali ukuran huruf dekorasi (huruf Orbitron lebih lebar dari bawaan).
  final double decoScale;

  @override
  Widget build(BuildContext context) {
    final cache = NameDecoCache.instance;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        final deco = uid.isEmpty || name.isEmpty ? null : NameDecoStyle.fromId(cache.styleFor(uid));
        if (deco != null) {
          return NameDecoText(
            key: ValueKey(deco),
            name: name,
            style: deco,
            fontSize: (style.fontSize ?? 14) * decoScale,
            animate: animate,
          );
        }
        return Text(
          name,
          style: style,
          maxLines: maxLines,
          textAlign: textAlign,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
