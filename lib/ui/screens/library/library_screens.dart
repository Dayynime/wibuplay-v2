import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/comic/comic_providers.dart';
import '../../../data/local/entities.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/cards.dart';
import '../comic/comic_profile_section.dart';
import '../profile/profile_controller.dart';
import '../../glass/glass.dart';
import '../profile/profile_screen.dart'
    show ProfileEmptyBox, ProfileWatchHistoryRow;

/// Halaman Riwayat & Favorit (dibuka dari tab Menu). Dipisah per tab:
/// anime dan komik tidak dicampur. Widget & data sama dengan tab di Profil.

/// Tab pil (gaya sama dengan tab Spin/Koleksiku).
class _LibraryTabs extends StatelessWidget {
  const _LibraryTabs({required this.labels, required this.selected, required this.onChanged});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: i == selected
                        ? const LinearGradient(colors: [AppColors.accentViolet, Color(0xFFFF6B4A)])
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == selected ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

PreferredSizeWidget _appBar(String title, {List<Widget>? actions}) => GlassAppBar(
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

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _tab = 0; // 0 = nonton, 1 = baca komik

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(profileHistoryProvider);
    final comicCount = ref.watch(comicStoreProvider).progress.length;
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

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: _appBar(
        'Riwayat',
        actions: [
          if (_tab == 0 && history.isNotEmpty)
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
      body: Column(
        children: [
          _LibraryTabs(
            labels: [
              history.isEmpty ? 'Nonton' : 'Nonton (${history.length})',
              comicCount == 0 ? 'Baca Komik' : 'Baca Komik ($comicCount)',
            ],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _tab == 1
                  ? ListView(
                      key: const ValueKey('komik'),
                      padding: const EdgeInsets.only(bottom: 40),
                      children: const [ComicProgressBlock(showHeader: false)],
                    )
                  : ListView(
                      key: const ValueKey('nonton'),
                      padding: const EdgeInsets.only(top: 4, bottom: 40),
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
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================ favorit

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  int _tab = 0; // 0 = anime, 1 = komik

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(profileFavoritesProvider);
    final comicCount = ref.watch(comicStoreProvider).favorites.length;
    final controller = ref.read(profileControllerProvider);

    Future<void> remove(FavoriteEntity fav) async {
      final ok = await _confirm(
        context,
        title: 'Hapus dari Favorit?',
        body: '"${fav.title}" akan dihapus dari daftar favoritmu.',
      );
      if (ok) await controller.removeFavorite(fav.id);
    }

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: _appBar('Favorit'),
      body: Column(
        children: [
          _LibraryTabs(
            labels: [
              favorites.isEmpty ? 'Anime' : 'Anime (${favorites.length})',
              comicCount == 0 ? 'Komik' : 'Komik ($comicCount)',
            ],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _tab == 1
                  ? ListView(
                      key: const ValueKey('komik'),
                      padding: const EdgeInsets.only(bottom: 40),
                      children: const [ComicFavoritesBlock(showHeader: false, grid: true)],
                    )
                  : ListView(
                      key: const ValueKey('anime'),
                      padding: const EdgeInsets.only(top: 4, bottom: 40),
                      children: [
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
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
