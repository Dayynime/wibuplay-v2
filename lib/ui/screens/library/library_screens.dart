import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/entities.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/cards.dart';
import '../comic/comic_profile_section.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_screen.dart'
    show ProfileEmptyBox, ProfileSectionHeader, ProfileWatchHistoryRow;

/// Halaman Riwayat & Favorit (dibuka dari tab Menu). Isinya sama persis dengan
/// tab Riwayat / Favorit di Profil, memakai widget & data yang sama.

AppBar _appBar(String title, {List<Widget>? actions}) => AppBar(
      backgroundColor: AppColors.backgroundDark,
      foregroundColor: AppColors.textWhite,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      actions: actions,
    );

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      title: Text(title, style: const TextStyle(color: AppColors.textWhite)),
      content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
          child: const Text('Hapus', style: TextStyle(color: AppColors.textWhite)),
        ),
      ],
    ),
  );
  return ok == true;
}

// ================================================================ riwayat

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(profileHistoryProvider);
    final authUser = ref.watch(authUserProvider).valueOrNull;
    final User? user = (authUser != null && FirebaseConfig.ready) ? authUser : null;
    final premium = user != null && (ref.watch(premiumProvider(user.uid)).valueOrNull ?? false);
    final profile = user == null ? null : ref.watch(chatProfileProvider(user.uid)).valueOrNull;

    final zName = profile?.username.trim() ?? '';
    final name = zName.isNotEmpty
        ? zName
        : (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : 'Pengguna';
    final zAvatar = profile?.avatarUrl ?? '';
    final avatar = zAvatar.isNotEmpty
        ? zAvatar
        : ((user?.photoURL ?? '').isNotEmpty ? user!.photoURL : null);

    final controller = ref.read(profileControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: _appBar(
        'Riwayat Tontonan',
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: 'Hapus semua riwayat',
              icon: const Icon(Icons.delete_sweep, color: AppColors.accentViolet),
              onPressed: () async {
                final ok = await _confirm(
                  context,
                  title: 'Hapus Semua Riwayat?',
                  body: 'Semua riwayat tontonan dan posisi pemutaran akan dihapus dari perangkat.',
                );
                if (ok) await controller.clearAllHistory();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          if (history.isEmpty)
            const ProfileEmptyBox(text: 'Belum ada riwayat tontonan.')
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < history.length; i++) ...[
                    ProfileWatchHistoryRow(
                      key: ValueKey(history[i].id),
                      history: history[i],
                      firebaseUid: user?.uid ?? '',
                      username: name,
                      avatarUrl: avatar,
                      isPremium: premium,
                      onPlay: () => openPlayer(context, history[i].movieId, history[i].episodeId),
                      onDelete: () => controller.deleteHistory(history[i].id),
                    ),
                    if (i != history.length - 1) const SizedBox(height: 22),
                  ],
                ],
              ),
            ),
          const ComicProgressBlock(),
        ],
      ),
    );
  }
}

// ================================================================ favorit

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(profileFavoritesProvider);
    final controller = ref.read(profileControllerProvider);

    Future<void> remove(FavoriteEntity fav) async {
      final ok = await _confirm(
        context,
        title: 'Hapus dari Favorit?',
        body: '"${fav.title}" akan dihapus dari daftar favoritmu.',
      );
      if (ok) await controller.removeFavorite(fav.id);
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: _appBar('Favorit'),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 40),
        children: [
          ProfileSectionHeader(
            icon: Icons.favorite,
            title: 'Favorite Shows',
            trailing: favorites.isEmpty ? null : '${favorites.length} Anime',
          ),
          if (favorites.isEmpty)
            const ProfileEmptyBox(text: 'Belum ada anime favorit.')
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  const gap = 12.0;
                  final cardW = (c.maxWidth - gap * 2) / 3;
                  return Wrap(
                    spacing: gap,
                    runSpacing: 14,
                    children: [
                      for (final fav in favorites)
                        SizedBox(
                          key: ValueKey(fav.id),
                          width: cardW,
                          child: Stack(
                            children: [
                              AnimePosterCard(
                                anime: fav.toAnimeItem(),
                                width: cardW,
                                onTap: () => openDetail(context, fav.id),
                              ),
                              Positioned(
                                top: 6,
                                left: 6,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => remove(fav),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      color: Color(0xB30B0E14),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.errorRed,
                                      size: 17,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          const ComicFavoritesBlock(),
        ],
      ),
    );
  }
}
