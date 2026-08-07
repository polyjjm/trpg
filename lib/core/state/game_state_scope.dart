import 'package:flutter/widgets.dart';

import 'game_state.dart';

/// [GameState]를 위젯 트리 아래로 전달하고, 변경 시 이를 구독한 위젯을 다시 빌드한다.
class GameStateScope extends InheritedNotifier<GameState> {
  const GameStateScope({
    super.key,
    required GameState gameState,
    required super.child,
  }) : super(notifier: gameState);

  static GameState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GameStateScope>();
    assert(scope != null, 'GameStateScope.of() called with no GameStateScope ancestor');
    return scope!.notifier!;
  }
}
