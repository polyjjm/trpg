import 'package:flutter/material.dart';
import '../models/battle_card.dart';

class BattleCardWidget extends StatelessWidget {
  final BattleCard card;
  final bool isFlipped;
  final VoidCallback? onTap;
  final bool dimmed;
  final double width;

  const BattleCardWidget({
    super.key,
    required this.card,
    required this.isFlipped,
    required this.width,
    this.onTap,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = isFlipped ? card.frontImagePath : card.backImagePath;
    final height = width * 1.68;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.3 : 1.0,
        child: SizedBox(
          width: width,
          height: height,
          child: Image.asset(
            imagePath,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}