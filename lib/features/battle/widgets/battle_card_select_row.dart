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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(cards.length, (index) {
        final isSelected = selectedIndex == index;
        final isAnotherCardSelected =
            selectedIndex != null && selectedIndex != index;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: BattleCardWidget(
            card: cards[index],
            isFlipped: isSelected,
            dimmed: isAnotherCardSelected,
            onTap: () => onSelect(index),
          ),
        );
      }),
    );
  }
}