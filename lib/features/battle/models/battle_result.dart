import 'battle_reward.dart';

enum BattleOutcome {
  win,
  lose,
  escape,
}

class BattleResult {
  final BattleOutcome outcome;
  final String battleId;
  final BattleReward reward;
  final List<String> usedItemIds;

  const BattleResult({
    required this.outcome,
    required this.battleId,
    required this.reward,
    required this.usedItemIds,
  });

  bool get isWin => outcome == BattleOutcome.win;
  bool get isLose => outcome == BattleOutcome.lose;
  bool get isEscaped => outcome == BattleOutcome.escape;
}