import 'battle_drop_item.dart';
import 'battle_stat_range.dart';

class BattleConfig {
  final String id;

  // 적 기본 정보
  final String enemyName;
  final String enemyImage;
  final String backgroundImage;

  // 전투 문구
  final String startMessage;
  final String winMessage;
  final String loseMessage;

  // 적 능력치 랜덤 범위
  final BattleStatRange enemyHpRange;
  final BattleStatRange enemyAttackRange;

  // 드랍 관련
  final int minDropCount;
  final int maxDropCount;
  final List<BattleDropItem> dropItems;

  // 도망 관련
  final bool canEscape;
  final double escapeChance;

  const BattleConfig({
    required this.id,
    required this.enemyName,
    required this.enemyImage,
    required this.backgroundImage,
    required this.startMessage,
    required this.winMessage,
    required this.loseMessage,
    required this.enemyHpRange,
    required this.enemyAttackRange,
    required this.minDropCount,
    required this.maxDropCount,
    required this.dropItems,
    required this.canEscape,
    required this.escapeChance,
  });
}