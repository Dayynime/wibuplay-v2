import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/anime_item.dart';
import '../../components/common_components.dart';
import '../../components/net_image.dart';
import '../../components/poster_holder.dart';
import '../../components/shimmer.dart';
import 'schedule_controller.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Port ScheduleScreen.kt.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, required this.onAnimeClick});

  final ValueChanged<String> onAnimeClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(scheduleControllerProvider);
    final notifier = ref.read(scheduleControllerProvider.notifier);

    final Widget body;
    if (ui.isLoading) {
      body = const _ScheduleLoadingSkeleton();
    } else if (ui.error != null) {
      body = Center(
        child: ErrorState(
          message: ui.error!,
          onRetry: () => notifier.loadSchedule(ui.selectedDay),
        ),
      );
    } else if (ui.items.isEmpty) {
      body = Center(
        child: EmptyState(
          title: 'Tidak Ada Jadwal',
          subtitle: 'Belum ada anime rilis terjadwal pada hari ${ui.selectedDay}',
          icon: Icons.calendar_today_outlined,
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 135),
        itemCount: ui.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final anime = ui.items[i];
          return ScheduleAnimeCard(
            anime: anime,
            onTap: () {
              final id = anime.id;
              if (id != null) onAnimeClick(id);
            },
          );
        },
      );
    }

    return ColoredBox(
      color: AppColors.backgroundDark,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Jadwal Rilis',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Jadwal penayangan episode baru setiap harinya',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  for (var i = 0; i < ScheduleController.days.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    GenreChip(
                      text: ScheduleController.days[i],
                      isSelected: ui.selectedDay == ScheduleController.days[i],
                      onTap: () => notifier.onDaySelected(ScheduleController.days[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Port ScheduleAnimeCard.
class ScheduleAnimeCard extends StatelessWidget {
  const ScheduleAnimeCard({super.key, required this.anime, required this.onTap});

  final AnimeItem anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: AppShapes.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          PosterTransitionHolder.url = anime.posterUrl;
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: AppColors.surfaceCard,
                      child: NetImage(anime.posterUrl),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentViolet.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              anime.status ?? 'Airing',
                              style: const TextStyle(
                                color: AppColors.accentViolet,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!_blank(anime.type)) ...[
                            const SizedBox(width: 6),
                            Text(
                              '• ${anime.type}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        anime.title ?? 'Anime',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 19 / 14,
                        ),
                      ),
                      if (!_blank(anime.genre)) ...[
                        const SizedBox(height: 4),
                        Text(
                          anime.genre!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (!_blank(anime.views)) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.visibility_outlined,
                              size: 12,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${anime.views} tayangan',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleLoadingSkeleton extends StatelessWidget {
  const _ScheduleLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: AppShapes.card,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 80, height: 115, borderRadius: BorderRadius.circular(12)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 60, height: 16, borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 8),
                    FractionallySizedBox(
                      widthFactor: 0.9,
                      child: ShimmerBox(height: 18, borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(height: 6),
                    FractionallySizedBox(
                      widthFactor: 0.5,
                      child: ShimmerBox(height: 14, borderRadius: BorderRadius.circular(4)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
