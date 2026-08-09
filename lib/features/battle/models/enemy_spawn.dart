import 'battle_stat_range.dart';

/// 전투 하나에 등장하는 적 한 마리의 스폰 정보.
/// BattleConfig.enemies에 여러 개를 담으면 다수 적 전투가 된다.
class EnemySpawn {
  final String name;
  final String image;
  final BattleStatRange hpRange;
  final BattleStatRange attackRange;

  const EnemySpawn({
    required this.name,
    required this.image,
    required this.hpRange,
    required this.attackRange,
  });
}
