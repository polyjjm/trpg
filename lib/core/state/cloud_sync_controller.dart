import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import 'cloud_save_service.dart';
import 'game_state.dart';

/// [GameState] 변경을 감지해 로그인된 사용자의 Firestore 세이브에 반영한다.
/// 로그인하지 않은 상태(게스트 플레이)에서는 아무 것도 하지 않는다.
class CloudSyncController {
  CloudSyncController({
    required GameState gameState,
    required AuthService authService,
    CloudSaveService? cloudSaveService,
  })  : _gameState = gameState,
        _authService = authService,
        _cloudSaveService = cloudSaveService ?? CloudSaveService();

  final GameState _gameState;
  final AuthService _authService;
  final CloudSaveService _cloudSaveService;

  void attach() {
    _gameState.addListener(_onGameStateChanged);
  }

  void detach() {
    _gameState.removeListener(_onGameStateChanged);
  }

  void _onGameStateChanged() {
    final uid = _authService.userId;
    if (uid == null) return;
    _cloudSaveService.save(uid, _gameState).catchError((Object e) {
      debugPrint('클라우드 세이브 저장 실패: $e');
    });
  }

  /// 로그인 직후 호출: 클라우드에 저장된 진행 상황이 있으면 불러오고,
  /// 없으면(첫 로그인) 현재 상태를 그대로 클라우드에 올려 초기 세이브를 만든다.
  /// 반환값은 "이미 존재하던 세이브를 불러왔는지" 여부 — 호출부가 바로 게임플레이로
  /// 들어갈지, 메인 메뉴를 보여줄지 분기하는 데 쓴다.
  Future<bool> loadOrInitialize() async {
    final uid = _authService.userId;
    if (uid == null) return false;

    final data = await _cloudSaveService.load(uid);
    if (data != null) {
      _gameState.loadFromJson(data);
      return true;
    }

    await _cloudSaveService.save(uid, _gameState);
    return false;
  }
}
