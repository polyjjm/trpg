class StoryBattleTrigger {
  final String battleId;
  final String winNodeId;
  final String loseNodeId;
  final String escapeNodeId;

  const StoryBattleTrigger({
    required this.battleId,
    required this.winNodeId,
    required this.loseNodeId,
    required this.escapeNodeId,
  });
}

class StoryMerchantTrigger {
  final String nextNodeId;

  const StoryMerchantTrigger({
    required this.nextNodeId,
  });
}

/// 카드 기반 BattlePage 대신 텍스트 조우(EncounterPage)를 여는 트리거.
/// 사망(하트 0)은 진행 리셋으로 이어지므로 loseNodeId가 필요 없다.
class StoryEncounterTrigger {
  final String encounterId;
  final String winNodeId;
  final String escapeNodeId;

  const StoryEncounterTrigger({
    required this.encounterId,
    required this.winNodeId,
    required this.escapeNodeId,
  });
}

class StoryChoice {
  final String text;
  final String? nextNodeId;
  final StoryBattleTrigger? battleTrigger;
  final StoryMerchantTrigger? merchantTrigger;
  final StoryEncounterTrigger? encounterTrigger;

  const StoryChoice({
    required this.text,
    this.nextNodeId,
    this.battleTrigger,
    this.merchantTrigger,
    this.encounterTrigger,
  }) : assert(
          (nextNodeId != null ? 1 : 0) +
                  (battleTrigger != null ? 1 : 0) +
                  (merchantTrigger != null ? 1 : 0) +
                  (encounterTrigger != null ? 1 : 0) ==
              1,
          'StoryChoice must set exactly one of nextNodeId, battleTrigger, '
          'merchantTrigger, or encounterTrigger',
        );

  bool get triggersBattle => battleTrigger != null;
  bool get triggersMerchant => merchantTrigger != null;
  bool get triggersEncounter => encounterTrigger != null;
}
