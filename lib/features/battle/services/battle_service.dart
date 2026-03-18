import 'dart:math';

import '../models/battle_config.dart';
import '../models/battle_drop_item.dart';
import '../models/battle_reward.dart';
import '../models/battle_unit.dart';

class BattleService {
  final Random _random = Random();

  BattleUnit createEnemy(BattleConfig config) {
    final int hp = _randomInRange(
      config.enemyHpRange.min,
      config.enemyHpRange.max,
    );

    final int attack = _randomInRange(
      config.enemyAttackRange.min,
      config.enemyAttackRange.max,
    );

    return BattleUnit(
      name: config.enemyName,
      maxHp: hp,
      hp: hp,
      attack: attack,
    );
  }

  BattleReward createReward(BattleConfig config) {
    final List<String> droppedItems = [];

    final int dropCount = _randomInRange(
      config.minDropCount,
      config.maxDropCount,
    );

    final List<BattleDropItem> shuffledDrops =
    List<BattleDropItem>.from(config.dropItems)..shuffle(_random);

    for (final drop in shuffledDrops) {
      if (droppedItems.length >= dropCount) {
        break;
      }

      final double roll = _random.nextDouble();
      if (roll <= drop.chance) {
        droppedItems.add(drop.itemId);
      }
    }

    return BattleReward(
      itemIds: droppedItems,
      gold: 0,
      exp: 0,
    );
  }

  bool tryEscape(BattleConfig config) {
    if (!config.canEscape) {
      return false;
    }

    return _random.nextDouble() <= config.escapeChance;
  }

  int _randomInRange(int min, int max) {
    if (min >= max) {
      return min;
    }
    return min + _random.nextInt(max - min + 1);
  }
}