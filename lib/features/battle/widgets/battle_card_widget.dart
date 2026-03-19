import 'package:flutter/material.dart';
import '../models/battle_card.dart';

class BattleCardWidget extends StatelessWidget {
  final BattleCard card;
  final bool isFlipped;
  final VoidCallback? onTap;
  final bool dimmed;

  const BattleCardWidget({
    super.key,
    required this.card,
    required this.isFlipped,
    this.onTap,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = isFlipped ? card.frontImagePath : card.backImagePath;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.3 : 1.0,
        child: SizedBox(
          width: 250,
          height: 420,
          child: Image.asset(
            imagePath,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}