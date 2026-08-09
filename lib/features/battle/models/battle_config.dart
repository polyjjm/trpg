import 'battle_drop_item.dart';
import 'enemy_spawn.dart';

class BattleConfig {
  final String id;

  // 적 스폰 목록. 한 마리면 기존과 동일한 1:1 전투, 여러 마리면 다수 적 전투가 된다.
  final List<EnemySpawn> enemies;
  final String backgroundImage;

  // 전투 문구
  final String startMessage;
  final String winMessage;
  final String loseMessage;

  // 드랍 관련
  final int minDropCount;
  final int maxDropCount;
  final List<BattleDropItem> dropItems;

  // 경험치 보상 범위
  final int minExp;
  final int maxExp;

  // 도망 관련
  final bool canEscape;
  final double escapeChance;

  const BattleConfig({
    required this.id,
    required this.enemies,
    required this.backgroundImage,
    required this.startMessage,
    required this.winMessage,
    required this.loseMessage,
    required this.minDropCount,
    required this.maxDropCount,
    required this.dropItems,
    required this.minExp,
    required this.maxExp,
    required this.canEscape,
    required this.escapeChance,
  });
}