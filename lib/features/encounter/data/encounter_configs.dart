import '../../../core/constants/asset_paths.dart';
import '../models/encounter_config.dart';

final Map<String, EncounterConfig> encounterConfigs = {
  'zombie_01': EncounterConfig(
    id: 'zombie_01',
    enemyName: '좀비',
    enemyImage: CharacterPaths.zombie,
    description: '좀비가 길을 막아섰다.',
    attackSuccessChance: 0.6,
    escapeChance: 0.4,
  ),

  // battle_configs.dart의 raider_01(약탈자 두 명 다수 적 전투)을 텍스트 조우로 이식.
  // 다수 적 구조는 텍스트 시스템에서 의미가 없어 단일 적 조우로 단순화했고,
  // 원본의 낮은 도망 확률(사람은 쉽게 놓아주지 않는다는 설정)만 그대로 가져왔다.
  'raider_01': EncounterConfig(
    id: 'raider_01',
    enemyName: '약탈자',
    // TODO: 약탈자 전용 이미지 애셋 필요 — 우선 좀비 이미지를 재사용한다.
    enemyImage: CharacterPaths.zombie,
    description: '약탈자가 앞을 가로막았다.',
    attackSuccessChance: 0.6,
    escapeChance: 0.2,
  ),
};
