import 'package:flutter/widgets.dart';

import '../auth/auth_scope.dart';
import '../auth/auth_service.dart';
import '../auth/google_auth_service.dart';
import 'cloud_sync_controller.dart';
import 'game_state.dart';
import 'game_state_scope.dart';

/// 앱 최상단에서 [GameState]와 로그인/클라우드 세이브 동기화 관련 인스턴스를
/// 생성·보관하고 하위 트리에 제공한다.
class GameStateProvider extends StatefulWidget {
  final Widget child;

  const GameStateProvider({super.key, required this.child});

  @override
  State<GameStateProvider> createState() => _GameStateProviderState();
}

class _GameStateProviderState extends State<GameStateProvider> {
  late final GameState _gameState = GameState();
  final AuthService _authService = GoogleAuthService();
  late final CloudSyncController _cloudSyncController = CloudSyncController(
    gameState: _gameState,
    authService: _authService,
  );

  @override
  void initState() {
    super.initState();
    _cloudSyncController.attach();
  }

  @override
  void dispose() {
    _cloudSyncController.detach();
    _gameState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      authService: _authService,
      cloudSyncController: _cloudSyncController,
      child: GameStateScope(gameState: _gameState, child: widget.child),
    );
  }
}
