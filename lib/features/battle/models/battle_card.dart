enum BattleCardType {
  attack,
  lightAttack,
  heavyAttack,
  fail,
}

class BattleCard {
  final BattleCardType type;
  final String frontImagePath;
  final String backImagePath;

  const BattleCard({
    required this.type,
    required this.frontImagePath,
    this.backImagePath = 'assets/images/system/backCard.png',
  });

  String get label {
    switch (type) {
      case BattleCardType.attack:
        return 'ATTACK';
      case BattleCardType.lightAttack:
        return 'LIGHT ATTACK';
      case BattleCardType.heavyAttack:
        return 'HEAVY ATTACK';
      case BattleCardType.fail:
        return 'FAIL';
    }
  }
}