import 'package:flutter/material.dart';
import '../models/battle_card.dart';
import 'battle_card_widget.dart';

class BattleCardSelectRow extends StatelessWidget {
  final List<BattleCard> cards;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  const BattleCardSelectRow({
    super.key,
    required this.cards,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final cardCount = cards.length;

        double spacing = maxWidth * 0.012;
        if (spacing < 4) spacing = 4;
        if (spacing > 12) spacing = 12;

        const horizontalPadding = 8.0;
        final usableWidth = maxWidth - (horizontalPadding * 2);
        final totalSpacing = spacing * (cardCount - 1);

        double cardWidth = (usableWidth - totalSpacing) / cardCount;

        if (cardWidth > 170) {
          cardWidth = 170;
        }

        if (cardWidth < 52) {
          cardWidth = 52;
        }

        final rowWidth = (cardWidth * cardCount) + totalSpacing;

        return Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: rowWidth > usableWidth
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: SizedBox(
                width: rowWidth < usableWidth ? usableWidth : rowWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(cards.length, (index) {
                    final card = cards[index];
                    final isSelected = selectedIndex == index;
                    final isAnotherCardSelected =
                        selectedIndex != null && selectedIndex != index;

                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == cardCount - 1 ? 0 : spacing,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        transform: Matrix4.identity()
                          ..translate(0.0, isSelected ? -10.0 : 0.0),
                        child: BattleCardWidget(
                          card: card,
                          isFlipped: false,
                          width: cardWidth,
                          onTap: () => onSelect(index),
                          dimmed: isAnotherCardSelected,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}