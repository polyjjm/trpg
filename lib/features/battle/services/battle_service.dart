import '../models/battle_card.dart';
import 'dart:math';

class BattleService {
  final Random _random = Random();

  List<BattleCard> getBattleCards() {
    final cards = [
      BattleCard(
        type: BattleCardType.fail,
        frontImagePath: 'assets/images/system/failCard.png',
      ),
      BattleCard(
        type: BattleCardType.lightAttack,
        frontImagePath: 'assets/images/system/lightAttackCard.png',
      ),
      BattleCard(
        type: BattleCardType.attack,
        frontImagePath: 'assets/images/system/attackCard.png',
      ),
      BattleCard(
        type: BattleCardType.attack,
        frontImagePath: 'assets/images/system/attackCard.png',
      ),
      BattleCard(
        type: BattleCardType.heavyAttack,
        frontImagePath: 'assets/images/system/heavyAttackCard.png',
      ),
    ];

    cards.shuffle(_random); // 🔥 랜덤 섞기

    return cards;
  }

  BattleCard getFailCard() {
    return const BattleCard(
      type: BattleCardType.fail,
      frontImagePath: 'assets/images/system/failCard.png',
    );
  }
}