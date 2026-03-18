import '../models/battle_config.dart';
import '../models/battle_drop_item.dart';
import '../models/battle_stat_range.dart';
import '../../../core/constants/asset_paths.dart';

final Map<String, BattleConfig> battleConfigs = {
  'zombie_01': BattleConfig(
    id: 'zombie_01',

    // 적 기본 정보
    enemyName: '좀비',
    enemyImage: CharacterPaths.zombie,
    backgroundImage: BackgroundPaths.battleBg,

    // 전투 문구
    startMessage: '좀비가 길을 막아섰다.',
    winMessage: '좀비를 쓰러뜨렸다.',
    loseMessage: '좀비에게 쓰러졌다...',

    // 적 능력치 랜덤 범위
    enemyHpRange: BattleStatRange(
      min: 1,
      max: 20,
    ),
    enemyAttackRange: BattleStatRange(
      min: 2,
      max: 6,
    ),

    // 드랍 개수 범위
    minDropCount: 0,
    maxDropCount: 2,

    // 드랍 후보 목록
    dropItems: [
      BattleDropItem(
        itemId: 'bandage_01',
        chance: 0.10,
      ),
      BattleDropItem(
        itemId: 'food_01',
        chance: 0.20,
      ),
      BattleDropItem(
        itemId: 'knife_01',
        chance: 0.03,
      ),
    ],

    // 도망 가능 여부 및 성공 확률
    canEscape: true,
    escapeChance: 0.35,
  ),
};