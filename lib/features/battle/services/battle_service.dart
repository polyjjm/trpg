import '../../../core/constants/asset_paths.dart';
import '../models/battle_card.dart';
import 'dart:math';

class BattleService {
  final Random _random = Random();

  // [밸런스 조정] 예전엔 5장 중 실패 카드가 1장(20%)이라 매 턴 1/5 확률로 턴을
  // 통째로 날렸다. 공격 카드(공격) 한 장을 더 추가해 6장 중 1장(약 16.7%)으로
  // 낮춰, 실패 체감은 줄이면서도 완전히 없애지는 않았다(순수 운 요소는 유지).
  List<BattleCard> getBattleCards() {
    final cards = [
      BattleCard(
        type: BattleCardType.fail,
        frontImagePath: UiPaths.failCard,
      ),
      BattleCard(
        type: BattleCardType.lightAttack,
        frontImagePath: UiPaths.lightAttackCard,
      ),
      BattleCard(
        type: BattleCardType.attack,
        frontImagePath: UiPaths.attackCard,
      ),
      BattleCard(
        type: BattleCardType.attack,
        frontImagePath: UiPaths.attackCard,
      ),
      BattleCard(
        type: BattleCardType.attack,
        frontImagePath: UiPaths.attackCard,
      ),
      BattleCard(
        type: BattleCardType.heavyAttack,
        frontImagePath: UiPaths.heavyAttackCard,
      ),
    ];

    cards.shuffle(_random); // 🔥 랜덤 섞기

    return cards;
  }

  BattleCard getFailCard() {
    return const BattleCard(
      type: BattleCardType.fail,
      frontImagePath: UiPaths.failCard,
    );
  }
}