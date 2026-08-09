import '../../../core/constants/asset_paths.dart';

/// 텍스트 기반 조우(인카운터) 정의.
/// 카드 기반 전투(BattlePage)와 달리 좀비/일반 적과의 가벼운 조우를
/// 텍스트 + 선택지만으로 처리할 때 사용한다.
class EncounterConfig {
  final String id;
  final String enemyName;
  final String enemyImage;
  final String backgroundImage;
  final String description;

  /// 공격 선택 시 성공 확률.
  final double attackSuccessChance;

  /// 도망 선택 시 성공 확률.
  final double escapeChance;

  const EncounterConfig({
    required this.id,
    required this.enemyName,
    required this.enemyImage,
    required this.description,
    this.backgroundImage = BackgroundPaths.battleBg,
    this.attackSuccessChance = 0.6,
    this.escapeChance = 0.4,
  });
}
