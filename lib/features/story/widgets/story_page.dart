import 'package:flutter/material.dart';
import 'package:sotry_trpg/features/panel/widgets/panel_handle_button.dart';
import 'typewriter_text.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/state/game_state_scope.dart';
import '../../battle/data/battle_configs.dart';
import '../../battle/models/battle_result.dart';
import '../../battle/pages/battle_page.dart';
import '../data/story_nodes.dart';
import '../models/story_choice.dart';

class StoryPage extends StatefulWidget {
  const StoryPage({super.key});

  @override
  State<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> {
  String? _typedNodeId;
  bool _showChoices = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final currentNodeId = GameStateScope.of(context).currentNodeId;
    if (_typedNodeId != currentNodeId) {
      _typedNodeId = currentNodeId;
      _showChoices = false;
    }
  }

  Future<void> _handleBattleChoice(StoryBattleTrigger trigger) async {
    final config = battleConfigs[trigger.battleId];
    if (config == null) return;

    final gameState = GameStateScope.of(context);

    final result = await Navigator.push<BattleResult>(
      context,
      MaterialPageRoute(
        builder: (_) => BattlePage(config: config),
      ),
    );

    if (!mounted || result == null) return;

    gameState.applyBattleResult(result);

    final nextNodeId = switch (result.outcome) {
      BattleOutcome.win => trigger.winNodeId,
      BattleOutcome.lose => trigger.loseNodeId,
      BattleOutcome.escape => trigger.escapeNodeId,
    };

    gameState.goToNode(nextNodeId);

    if (!mounted) return;

    final rewardText = result.reward.itemIds.isEmpty
        ? '획득한 아이템 없음'
        : '획득 아이템: ${result.reward.itemIds.join(', ')}';

    final message = switch (result.outcome) {
      BattleOutcome.win => '전투 승리. 남은 HP: ${result.remainHp} / $rewardText',
      BattleOutcome.escape => '전투에서 도망쳤다.',
      BattleOutcome.lose => '전투에서 패배했다.',
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleNodeChoice(String nextNodeId) {
    GameStateScope.of(context).goToNode(nextNodeId);
  }

  void _handleRestart() {
    GameStateScope.of(context).resetProgress(storyStartNodeId);
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    const Color ivory = Color(0xFFE2D4BF);
    const Color softLine = Color(0x99CDBDA7);

    final currentNodeId = GameStateScope.of(context).currentNodeId;
    final node = storyNodes[currentNodeId]!;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              node.backgroundImage,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.22),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.08),
                    Colors.black.withOpacity(0.18),
                    Colors.black.withOpacity(0.48),
                    Colors.black.withOpacity(0.78),
                  ],
                  stops: const [0.0, 0.32, 0.68, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.10),
                    Colors.black.withOpacity(0.45),
                  ],
                  stops: const [0.45, 0.78, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          node.dayLabel,
                          style: TextStyle(
                            fontSize: 18,
                            letterSpacing: 3.5,
                            color: ivory.withOpacity(0.95),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          node.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: ivory,
                            shadows: const [
                              Shadow(
                                offset: Offset(0, 2),
                                blurRadius: 18,
                                color: Colors.black87,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withOpacity(0.22),
                            Colors.black.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 1.2,
                            height: 118,
                            margin: const EdgeInsets.only(top: 4, right: 16),
                            color: softLine.withOpacity(0.45),
                          ),
                          Expanded(
                            child: TypewriterText(
                              key: ValueKey(node.id),
                              text: node.text,
                              speed: const Duration(milliseconds: 45),
                              style: TextStyle(
                                fontSize: 21,
                                height: 1.5,
                                color: ivory.withOpacity(0.97),
                                fontWeight: FontWeight.w400,
                                shadows: const [
                                  Shadow(
                                    offset: Offset(0, 2),
                                    blurRadius: 10,
                                    color: Colors.black87,
                                  ),
                                ],
                              ),
                              onComplete: () {
                                if (!mounted) return;
                                setState(() {
                                  _showChoices = true;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  AnimatedOpacity(
                    opacity: _showChoices ? 1 : 0,
                    duration: const Duration(milliseconds: 500),
                    child: IgnorePointer(
                      ignoring: !_showChoices,
                      child: Column(
                        children: node.isEnding
                            ? [
                                _buildChoiceButton(
                                  text: '처음으로',
                                  textColor: ivory,
                                  onTap: _handleRestart,
                                ),
                              ]
                            : [
                                for (final choice in node.choices) ...[
                                  _buildChoiceButton(
                                    text: choice.text,
                                    textColor: ivory,
                                    onTap: choice.triggersBattle
                                        ? () => _handleBattleChoice(choice.battleTrigger!)
                                        : () => _handleNodeChoice(choice.nextNodeId!),
                                  ),
                                  if (choice != node.choices.last)
                                    const SizedBox(height: 14),
                                ],
                              ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: PanelHandleButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceButton({
    required String text,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return _HoverChoiceButton(
      text: text,
      textColor: textColor,
      onTap: onTap,
    );
  }
}

class _HoverChoiceButton extends StatefulWidget {
  final String text;
  final Color textColor;
  final VoidCallback onTap;

  const _HoverChoiceButton({
    required this.text,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<_HoverChoiceButton> createState() => _HoverChoiceButtonState();
}

class _HoverChoiceButtonState extends State<_HoverChoiceButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          constraints: const BoxConstraints(
            minHeight: 88,
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Opacity(
                    opacity: 0.22,
                    child: Image.asset(
                      UiPaths.choiceBg,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _hovered
                          ? [
                        Colors.black.withOpacity(0.18),
                        Colors.black.withOpacity(0.08),
                      ]
                          : [
                        Colors.black.withOpacity(0.12),
                        Colors.black.withOpacity(0.04),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: _hovered
                          ? widget.textColor.withOpacity(0.60)
                          : widget.textColor.withOpacity(0.28),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.20),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.03),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  widget.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.4,
                    color: widget.textColor.withOpacity(_hovered ? 0.98 : 0.90),
                    fontWeight: FontWeight.w400,
                    shadows: const [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 8,
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
