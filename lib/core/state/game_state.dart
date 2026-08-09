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
  int playerDefense = 5;

  int level = 1;
  int exp = 0;

  static const int maxHearts = 3;
  int hearts = maxHearts;

  /// 유료 재화(캐시) 잔액. 실제 IAP 연동 전까지는 [MonetizationService.purchaseCashPackage]
  /// 성공 시 [addCash]로, 이야기 팩 구매 시 [spendCash]로만 변경된다.
  int cashBalance = 0;

  final Set<String> _ownedPackIds = {};
  Set<String> get ownedPackIds => Set.unmodifiable(_ownedPackIds);

  /// 캐시를 더한다. 캐시 패키지 구매 성공 시 호출한다.
  void addCash(int amount) {
    if (amount <= 0) return;
    cashBalance += amount;
    notifyListeners();
  }

  /// 캐시를 사용한다. 잔액이 부족하면 아무 것도 바꾸지 않고 false를 반환한다.
  bool spendCash(int amount) {
    if (amount <= 0 || cashBalance < amount) return false;
    cashBalance -= amount;
    notifyListeners();
    return true;
  }

  bool ownsPack(String packId) => _ownedPackIds.contains(packId);

  void markPackOwned(String packId) {
    if (_ownedPackIds.add(packId)) {
      notifyListeners();
    }
  }

  /// 지금까지 진행한(goToNode로 이동한) 노드 수. 유료 팩의 무료 미리보기 한도를
  /// 판단하는 데 쓰인다.
  int visitedNodeCount = 0;

  /// 하트를 하나 잃는다. 반환값이 true면 하트가 0이 되어 사망 처리해야 한다는 뜻이다.
  bool loseHeart() {
    if (hearts > 0) {
      hearts -= 1;
      notifyListeners();
    }
    return hearts <= 0;
  }

  /// 하트를 하나 회복한다 (최대치를 넘지 않음).
  void healHeart() {
    if (hearts >= maxHearts) return;
    hearts += 1;
    notifyListeners();
  }

  /// 다음 레벨까지 필요한 누적 경험치.
  int expToNextLevel() => 20 + (level - 1) * 15;

  /// 경험치를 더하고, 필요하다면 여러 레벨을 한 번에 처리한다.
  void addExp(int amount) {
    if (amount <= 0) return;
    exp += amount;

    var leveledUp = false;
    while (exp >= expToNextLevel()) {
      exp -= expToNextLevel();
      level += 1;
      leveledUp = true;

      playerMaxHp += 5;
      playerAttack += 2;
      playerDefense += 1;
    }

    if (leveledUp) {
      playerHp = playerMaxHp;
    }

    notifyListeners();
  }

  void goToNode(String nodeId) {
    _currentNodeId = nodeId;
    visitedNodeCount += 1;
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
    if (result.reward.exp > 0) {
      addExp(result.reward.exp);
    }
    notifyListeners();
  }

  /// 광고 시청 등으로 부활할 때 HP를 일부 회복시킨다.
  void revive() {
    playerHp = (playerMaxHp / 2).ceil().clamp(1, playerMaxHp);
    notifyListeners();
  }

  void resetProgress(String startingNodeId) {
    _currentNodeId = startingNodeId;
    _inventory.clear();
    level = 1;
    exp = 0;
    playerMaxHp = 30;
    playerAttack = 8;
    playerDefense = 5;
    playerHp = playerMaxHp;
    hearts = maxHearts;
    visitedNodeCount = 0;
    notifyListeners();
  }

  /// 세이브 데이터 구조 버전. 필드를 추가/변경할 때마다 올리고
  /// fromJson()에서 이전 버전 데이터도 기본값으로 채워 읽을 수 있게 한다.
  static const int currentSchemaVersion = 3;

  Map<String, dynamic> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'currentNodeId': _currentNodeId,
        'inventory': _inventory,
        'playerMaxHp': playerMaxHp,
        'playerHp': playerHp,
        'playerAttack': playerAttack,
        'playerDefense': playerDefense,
        'level': level,
        'exp': exp,
        'hearts': hearts,
        'cashBalance': cashBalance,
        'ownedPackIds': _ownedPackIds.toList(),
        'visitedNodeCount': visitedNodeCount,
      };

  /// [fallbackNodeId]: 저장된 데이터에 currentNodeId가 없을 때 대신 쓸 시작 노드.
  /// GameState는 스토리 콘텐츠를 모르는 계층이라 임의의 노드 id를 하드코딩할 수 없으므로,
  /// 실제 시작 노드를 아는 호출부(예: 나중에 추가될 SaveService)가 넘겨준다.
  factory GameState.fromJson(
    Map<String, dynamic> json, {
    required String fallbackNodeId,
  }) {
    final state = GameState(
      startingNodeId: json['currentNodeId'] as String? ?? fallbackNodeId,
    );
    state.loadFromJson(json);
    return state;
  }

  /// 이미 존재하는 인스턴스에 저장된 데이터를 덮어쓴다.
  /// 앱 시작 시 만들어진 [GameState]는 위젯 트리 전체가 구독하는 단일 인스턴스이므로,
  /// 로그인 후 클라우드 세이브를 불러올 때는 새 인스턴스로 교체하는 대신 이 메서드로
  /// 값만 갱신한다.
  void loadFromJson(Map<String, dynamic> json) {
    _currentNodeId = json['currentNodeId'] as String? ?? _currentNodeId;

    _inventory.clear();
    final inventoryJson = json['inventory'] as Map<String, dynamic>?;
    inventoryJson?.forEach((itemId, count) {
      _inventory[itemId] = count as int;
    });

    playerMaxHp = json['playerMaxHp'] as int? ?? playerMaxHp;
    playerHp = json['playerHp'] as int? ?? playerHp;
    playerAttack = json['playerAttack'] as int? ?? playerAttack;
    playerDefense = json['playerDefense'] as int? ?? playerDefense;
    level = json['level'] as int? ?? level;
    exp = json['exp'] as int? ?? exp;
    hearts = json['hearts'] as int? ?? hearts;
    cashBalance = json['cashBalance'] as int? ?? cashBalance;

    _ownedPackIds.clear();
    final ownedPackIdsJson = json['ownedPackIds'] as List<dynamic>?;
    ownedPackIdsJson?.forEach((id) => _ownedPackIds.add(id as String));

    visitedNodeCount = json['visitedNodeCount'] as int? ?? visitedNodeCount;

    notifyListeners();
  }
}
