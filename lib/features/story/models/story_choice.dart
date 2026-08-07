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

class StoryChoice {
  final String text;
  final String? nextNodeId;
  final StoryBattleTrigger? battleTrigger;

  const StoryChoice({
    required this.text,
    this.nextNodeId,
    this.battleTrigger,
  }) : assert(
          (nextNodeId != null) != (battleTrigger != null),
          'StoryChoice must set exactly one of nextNodeId or battleTrigger',
        );

  bool get triggersBattle => battleTrigger != null;
}
