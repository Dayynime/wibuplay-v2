
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/anime_item.dart';
import 'net_image.dart';

/// Port TopHitsRow.kt: carousel poster yang membesar di tengah (skala
/// 1.0 -> 0.82, alpha 1.0 -> 0.65), snap ke tengah, mulai dari item tengah,
/// ketuk poster non-tengah = geser ke tengah, ketuk poster tengah = buka.
class TopHitsRow extends StatefulWidget {
  const TopHitsRow({super.key, required this.items, required this.onItemClick});

  final List<AnimeItem> items;
  final ValueChanged<AnimeItem> onItemClick;

  @override
  State<TopHitsRow> createState() => _TopHitsRowState();
}

class _TopHitsRowState extends State<TopHitsRow> {
  static const double _itemWidth = 148;
  static const double _gap = 16;

  PageController? _controller;
  double _lastWidth = -1;
  int _focused = 0;

  int get _startIndex => (widget.items.length - 1) ~/ 2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final w = MediaQuery.sizeOf(context).width;
    if (_controller == null || (w - _lastWidth).abs() > 0.5) {
      final page = _controller?.hasClients == true
          ? (_controller!.page ?? _focused.toDouble()).round()
          : (_controller == null ? _startIndex : _focused);
      _controller?.dispose();
      _lastWidth = w;
      _focused = page;
      _controller = PageController(
        initialPage: page,
        viewportFraction: ((_itemWidth + _gap) / w).clamp(0.2, 1.0).toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final controller = _controller;
    if (items.isEmpty || controller == null) return const SizedBox.shrink();

    return SizedBox(
      height: 295,
      child: PageView.builder(
        controller: controller,
        itemCount: items.length,
        clipBehavior: Clip.none,
        onPageChanged: (i) => setState(() => _focused = i),
        itemBuilder: (context, index) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              double page = _focused.toDouble();
              if (controller.hasClients && controller.position.haveDimensions) {
                page = controller.page ?? page;
              }
              // Jarak dari tengah dalam piksel logis (1 halaman = item + gap)
              final distancePx = (page - index).abs() * (_itemWidth + _gap);
              final fraction = (distancePx / (_itemWidth * 1.5)).clamp(0.0, 1.0).toDouble();
              final scale = 1.0 - fraction * 0.18;
              final alpha = 1.0 - fraction * 0.35;
              final translateY = fraction * 14 - 6;
              final isFocused = index == _focused;

              return Center(
                child: Opacity(
                  opacity: alpha,
                  child: Transform.translate(
                    offset: Offset(0, translateY),
                    child: Transform.scale(
                      scale: scale,
                      child: _TopHitItem(
                        anime: items[index],
                        rank: index + 1,
                        isFocused: isFocused,
                        onTap: () {
                          if (isFocused) {
                            widget.onItemClick(items[index]);
                          } else {
                            controller.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TopHitItem extends StatefulWidget {
  const _TopHitItem({
    required this.anime,
    required this.rank,
    required this.isFocused,
    required this.onTap,
  });

  final AnimeItem anime;
  final int rank;
  final bool isFocused;
  final VoidCallback onTap;

  @override
  State<_TopHitItem> createState() => _TopHitItemState();
}

class _TopHitItemState extends State<_TopHitItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.isFocused;
    final titleColor = f ? AppColors.textWhite : AppColors.textMuted.withValues(alpha: 0.55);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: SizedBox(
          width: _TopHitsRowState._itemWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: AppShapes.card,
                  child: ColoredBox(
                    color: AppColors.surfaceCard,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(widget.anime.posterUrl),
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 56,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xCC1E1B2E)],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: f ? 28 : 24,
                            height: f ? 28 : 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: f ? AppColors.accentViolet : const Color(0xAA1E1B2E),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '#${widget.rank}',
                              style: TextStyle(
                                color: AppColors.textWhite,
                                fontSize: f ? 12 : 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    color: titleColor,
                    fontSize: f ? 13 : 12,
                    fontWeight: f ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  child: Text(
                    widget.anime.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                height: 3,
                width: f ? 36 : 0,
                decoration: BoxDecoration(
                  color: AppColors.accentViolet,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

