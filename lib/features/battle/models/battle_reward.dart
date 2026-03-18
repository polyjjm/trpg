class BattleReward {
  final List<String> itemIds;
  final int gold;
  final int exp;

  const BattleReward({
    required this.itemIds,
    required this.gold,
    required this.exp,
  });

  factory BattleReward.empty() {
    return const BattleReward(
      itemIds: [],
      gold: 0,
      exp: 0,
    );
  }
}