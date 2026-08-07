import 'package:flutter/foundation.dart';

import '../../features/battle/models/battle_result.dart';

/// 스토리 진행 상황 / 인벤토리 / 플레이어 능력치를 담는 상태 계층.
/// 지금은 메모리에만 보관하지만, toJson·fromJson 형태를 갖춰 두어
/// 나중에 DB 저장·불러오기를 붙일 때 이 클래스만 확장하면 되도록 만들었다.
class GameState extends ChangeNotifier {
  GameState({required String startingNodeId})
      : _currentNodeId = startingNodeId;

  String _currentNodeId;
  String get currentNodeId => _currentNodeId;

  final Map<String, int> _inventory = {};
  Map<String, int> get inventory => Map.unmodifiable(_inventory);

  int playerMaxHp = 30;
  int playerHp = 30;
  int playerAttack = 8;

  void goToNode(String nodeId) {
    _currentNodeId = nodeId;
    notifyListeners();
  }

  void addItem(String itemId, [int count = 1]) {
    if (count <= 0) return;
    _inventory[itemId] = (_inventory[itemId] ?? 0) + count;
    notifyListeners();
  }

  bool removeItem(String itemId, [int count = 1]) {
    final current = _inventory[itemId] ?? 0;
    if (current < count) return false;

    final remaining = current - count;
    if (remaining <= 0) {
      _inventory.remove(itemId);
    } else {
      _inventory[itemId] = remaining;
    }
    notifyListeners();
    return true;
  }

  void applyBattleResult(BattleResult result) {
    playerHp = result.remainHp;
    for (final itemId in result.reward.itemIds) {
      _inventory[itemId] = (_inventory[itemId] ?? 0) + 1;
    }
    notifyListeners();
  }

  void resetProgress(String startingNodeId) {
    _currentNodeId = startingNodeId;
    _inventory.clear();
    playerHp = playerMaxHp;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'currentNodeId': _currentNodeId,
        'inventory': _inventory,
        'playerMaxHp': playerMaxHp,
        'playerHp': playerHp,
        'playerAttack': playerAttack,
      };

  factory GameState.fromJson(Map<String, dynamic> json) {
    final state = GameState(startingNodeId: json['currentNodeId'] as String);

    final inventoryJson = json['inventory'] as Map<String, dynamic>;
    inventoryJson.forEach((itemId, count) {
      state._inventory[itemId] = count as int;
    });

    state.playerMaxHp = json['playerMaxHp'] as int;
    state.playerHp = json['playerHp'] as int;
    state.playerAttack = json['playerAttack'] as int;

    return state;
  }
}
