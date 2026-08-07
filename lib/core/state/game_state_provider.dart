import 'package:flutter/widgets.dart';

import '../../features/story/data/story_nodes.dart';
import 'game_state.dart';
import 'game_state_scope.dart';

/// 앱 최상단에서 [GameState]를 생성·보관하고 하위 트리에 제공한다.
class GameStateProvider extends StatefulWidget {
  final Widget child;

  const GameStateProvider({super.key, required this.child});

  @override
  State<GameStateProvider> createState() => _GameStateProviderState();
}

class _GameStateProviderState extends State<GameStateProvider> {
  late final GameState _gameState =
      GameState(startingNodeId: storyStartNodeId);

  @override
  void dispose() {
    _gameState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameStateScope(
      gameState: _gameState,
      child: widget.child,
    );
  }
}
