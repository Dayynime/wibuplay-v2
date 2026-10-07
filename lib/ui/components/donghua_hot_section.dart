import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../data/models/anichin_models.dart';
import '../screens/donghua/donghua_widgets.dart';
import 'common_components.dart';

const Color _rankGold = Color(0xFFFFB300);

/// Section "Donghua" di Beranda gaya bento: #1 besar di kiri, #2 & #3
/// bertumpuk di kanan. Port DonghuaHotSection.kt.
/// Data: 3 kartu pertama dari Anichin (API-nya belum punya rating/views).
class DonghuaHotSection extends StatelessWidget {
  const DonghuaHotSection({
    super.key,
    required this.cards,
    required this.onCardClick,
    required this.onSeeAllClick,
  });

  final List<AnichinCard> cards;
  final ValueChanged<String> onCardClick;
  final VoidCallback onSeeAllClick;

  @override
  Widget build(BuildContext context) {
    final top = cards.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    void tap(AnichinCard c) {
      final slug = c.slug;
      if (slug != null && slug.isNotEmpty) onCardClick(slug);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Donghua',
            actionText: 'Lihat semua',
            onActionClick: onSeeAllClick,
          ),
          SizedBox(
            height: 360,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _HotCard(rank: 1, card: top[0], onTap: () => tap(top[0])),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      children: [
                        for (var i = 1; i < top.length; i++) ...[
                          if (i > 1) const SizedBox(height: 10),
                          Expanded(
                            child: _HotCard(
                              rank: i + 1,
                              card: top[i],
                              onTap: () => tap(top[i]),
                            ),
                          ),
                        ],
                        // Kalau data cuma 2, sisakan ruang biar kartu #2 tidak melar.
                        if (top.length == 2) ...[
                          const SizedBox(height: 10),
                          const Spacer(),
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

class _HotCard extends StatelessWidget {
  const _HotCard({required this.rank, required this.card, required this.onTap});

  final int rank;
  final AnichinCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = cleanMeta(card.type);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF26233A)),
            // Backdrop: poster yang sama, diburamkan dan digelapkan.
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Opacity(opacity: 0.55, child: DonghuaImage(card.thumbnail)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 40, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DonghuaImage(card.thumbnail),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.85),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (card.eps != null)
                            Positioned(
                              left: 8,
                              bottom: 6,
                              child: Text(
                                'Eps ${card.eps}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (type != null)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  type,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cardTitle(card),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: rank == 1 ? 14 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // Badge peringkat
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: const BoxDecoration(
                  color: _rankGold,
                  borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                ),
                child: Text(
                  '#$rank',
                  style: const TextStyle(
                    color: Color(0xFF1A1200),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
