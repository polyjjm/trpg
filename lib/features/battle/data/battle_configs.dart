import '../models/battle_config.dart';
import '../models/battle_drop_item.dart';
import '../models/battle_stat_range.dart';
import '../models/enemy_spawn.dart';
import '../../../core/constants/asset_paths.dart';

final Map<String, BattleConfig> battleConfigs = {
  'zombie_01': BattleConfig(
    id: 'zombie_01',

    // 적 스폰 목록 (현재는 좀비 한 마리 — 1:1 전투)
    //
    // [밸런스 조정 - 좀비_01]
    // 카드 데미지가 플레이어 공격력에 비례하게 된 뒤(공격력 8 기준 약공격 6 / 공격 8 / 강공격 11,
    // 실패 카드 제외 평균 8.2)로 다시 계산해 보면:
    //  - hp를 1~20(평균 10.5)으로 두면 평균 1.5턴 만에 끝나 "한 방 컷"이 흔해진다.
    //    → 14~30(평균 22)으로 올려 실패 카드를 포함한 평균 데미지(약 6.8/턴) 기준
    //      평균 3턴 안팎으로 끝나도록 늘렸다.
    //  - 기존 공격 2~6은 플레이어 방어력 5를 적용하면(최소 피해 1 보정) 최댓값조차
    //    6-5=1로 항상 고정 피해 1만 들어가 방어력 시스템이 무의미했다.
    //    → 6~14(평균 10)로 올려 방어력 적용 후에도 1~9(평균 5) 사이로 실제 편차가 생기게 했다.
    //      플레이어 체력 30 기준 평균 3턴 전투에서 기대 피해량은 약 15 정도라 여유 있게
    //      버틸 수 있고, 최댓값(9)을 연속으로 맞아도 즉사하지 않는다.
    enemies: [
      EnemySpawn(
        name: '좀비',
        image: CharacterPaths.zombie,
        hpRange: BattleStatRange(
          min: 14,
          max: 30,
        ),
        attackRange: BattleStatRange(
          min: 6,
          max: 14,
        ),
      ),
    ],
    backgroundImage: BackgroundPaths.battleBg,

    // 전투 문구
    startMessage: '좀비가 길을 막아섰다.',
    winMessage: '좀비를 쓰러뜨렸다.',
    loseMessage: '좀비에게 쓰러졌다...',

    // 드랍 개수 범위 (적 한 마리당 굴리는 범위)
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

    // 경험치 보상 범위 (적 한 마리당 굴려서 합산)
    // 전투가 평균 3턴 안팎으로 길어진 만큼(예전 대비 위험 부담 증가) 판당 경험치도 함께
    // 올려 성장 속도 체감을 비슷하게 맞췄다. 레벨업 필요 경험치는 20(1→2레벨) 기준
    // 평균 2판 정도면 다음 레벨에 도달한다.
    minExp: 8,
    maxExp: 16,

    // 도망 가능 여부 및 성공 확률
    // 전투 위험도가 올라간 만큼 도망 성공률도 소폭(0.35 → 0.4) 올려, 상성이 나쁠 때
    // 빠져나갈 여지를 조금 더 넉넉하게 뒀다.
    canEscape: true,
    escapeChance: 0.4,
  ),

  // [약탈자_01] 좀비와는 다른 결의 위협 — 좀비 아포칼립스 세계관에서는 좀비뿐 아니라
  // 다른 생존자와의 충돌도 생존을 위협한다. 두 명이 함께 등장하는 다수 적 전투(prompt 5의
  // 다수 적 구조 활용) 예시이기도 하다.
  'raider_01': BattleConfig(
    id: 'raider_01',

    // 적 스폰 목록 — 약탈자 두 명이 함께 등장한다.
    //
    // [밸런스 설계 - 약탈자_01]
    // 좀비 한 마리(공격 6~14, 평균 10)와 다른 느낌을 주기 위해 개개인의 공격력은 낮췄지만
    // (4~10, 평균 7) 두 명이 각자 턴마다 공격하므로 체감 압박은 비슷하거나 더 크다.
    // 대신 hp는 좀비보다 낮게(10~18, 평균 14 x 2마리) 잡아 "약하지만 여러 명"인 인간 적의
    // 느낌을 살렸다. 사람인 만큼 쉽게 물러서지 않는다는 설정으로 도망 확률도 좀비(0.4)보다
    // 훨씬 낮은 0.2로 잡았다 — 한 번 마주치면 끝까지 쫓아오는 끈질긴 상대.
    enemies: [
      EnemySpawn(
        name: '약탈자 A',
        // TODO: 약탈자 전용 이미지 애셋 필요
        image: CharacterPaths.zombie,
        hpRange: BattleStatRange(
          min: 10,
          max: 18,
        ),
        attackRange: BattleStatRange(
          min: 4,
          max: 10,
        ),
      ),
      EnemySpawn(
        name: '약탈자 B',
        // TODO: 약탈자 전용 이미지 애셋 필요
        image: CharacterPaths.zombie,
        hpRange: BattleStatRange(
          min: 10,
          max: 18,
        ),
        attackRange: BattleStatRange(
          min: 4,
          max: 10,
        ),
      ),
    ],
    backgroundImage: BackgroundPaths.battleBg,

    // 전투 문구
    startMessage: '약탈자 두 명이 앞을 가로막았다.',
    winMessage: '약탈자들을 물리쳤다.',
    loseMessage: '약탈자들에게 당하고 말았다...',

    // 드랍 개수 범위 (적 한 마리당 굴리는 범위) — 두 명분이 합산되므로 좀비보다 낮게 잡았다.
    minDropCount: 0,
    maxDropCount: 1,

    // 드랍 후보 목록 — 무장한 생존자답게 칼 드랍 확률을 좀비보다 높였다.
    dropItems: [
      BattleDropItem(
        itemId: 'bandage_01',
        chance: 0.15,
      ),
      BattleDropItem(
        itemId: 'food_01',
        chance: 0.15,
      ),
      BattleDropItem(
        itemId: 'knife_01',
        chance: 0.08,
      ),
    ],

    // 경험치 보상 범위 (적 한 마리당 굴려서 합산) — 두 명분이라 좀비보다 조금 낮게 잡아도
    // 합산하면 좀비 한 마리보다 더 짭짤하다.
    minExp: 6,
    maxExp: 12,

    // 도망 가능 여부 및 성공 확률 — 위 설계 메모 참고: 사람 상대는 쉽게 놓아주지 않는다.
    canEscape: true,
    escapeChance: 0.2,
  ),
};