import 'package:flutter/foundation.dart';

import '../../features/battle/models/battle_result.dart';
import 'reading_progress.dart';

/// 스토리 진행 상황 / 인벤토리 / 플레이어 능력치를 담는 상태 계층.
/// 지금은 메모리에만 보관하지만, toJson·fromJson 형태를 갖춰 두어
/// 나중에 DB 저장·불러오기를 붙일 때 이 클래스만 확장하면 되도록 만들었다.
class GameState extends ChangeNotifier {
  GameState();

  /// 팩별 읽기 진행 상황(현재 노드/미리보기 카운트) — packId로 키를 잡는다.
  /// 예전엔 currentNodeId/visitedNodeCount가 이 클래스에 스칼라 하나로만
  /// 있어서 팩을 옮겨다니면 서로의 위치를 덮어썼다(known limitation,
  /// CLAUDE.md 참고) — 이 맵이 그 자리를 대신한다. 게스트(로그인 안 함)도
  /// 이 맵 자체는 그대로 갖는다 — 세션(앱을 껐다 켜기 전까지) 안에서는
  /// 팩별로 안 섞이고, 앱을 재시작하면 다른 메모리 전용 상태와 마찬가지로
  /// 사라진다. 로그인 사용자는 ReadingProgressRepository가 이 맵의 항목을
  /// users/{uid}/readingProgress/{packId}에 별도로 저장한다(save/current의
  /// GameState.toJson()에는 안 실린다 — CloudSyncController가 아니라 리더
  /// 화면이 노드 이동 시점에 직접 저장한다).
  final Map<String, ReadingProgress> _readingProgress = {};

  ReadingProgress? progressFor(String packId) => _readingProgress[packId];

  /// 가장 최근에 연 팩 — 홈 화면의 "이어읽기" 카드가 어느 팩을 보여줄지
  /// 고르는 데 쓴다. [_readingProgress]는 Dart Map이라 삽입 순서만 보존하고
  /// (기존 키를 다시 대입해도 순서가 안 바뀐다) "최근"을 알려주지 못해서
  /// 별도로 둔 값이다 — 노드 이동/진행 상황을 불러오는 시점마다 갱신된다.
  String? _lastOpenedPackId;
  String? get lastOpenedPackId => _lastOpenedPackId;

  /// 노드 이동(선택지를 고르거나 "다음"을 눌렀을 때)마다 호출한다 —
  /// visitedNodeCount를 1 늘리고 currentNodeId를 갱신한다. [completed]는
  /// 방금 이동한 노드가 이 팩의 마지막 노드(인터랙티브는 결말, 선형은 마지막
  /// 챕터)인지 — 호출부(InteractiveReader/LinearReader)가 목적지 노드를 보고
  /// 직접 판단해서 넘긴다.
  void recordNodeVisit({
    required String packId,
    required String nodeId,
    bool completed = false,
  }) {
    final existing = _readingProgress[packId];
    _readingProgress[packId] = ReadingProgress(
      currentNodeId: nodeId,
      visitedNodeCount: (existing?.visitedNodeCount ?? 0) + 1,
      completed: completed,
    );
    _lastOpenedPackId = packId;
    notifyListeners();
  }

  /// Firestore(또는 이미 메모리에 있던 값)에서 읽어온 진행 상황을 그대로
  /// 채워 넣는다 — [recordNodeVisit]과 달리 visitedNodeCount를 더하지 않고
  /// 그 값 그대로 덮어쓴다("이동"이 아니라 "불러오기"라서).
  void seedPackProgress(String packId, ReadingProgress progress) {
    _readingProgress[packId] = progress;
    _lastOpenedPackId = packId;
    notifyListeners();
  }

  /// "처음부터 다시 시작" — 이 팩의 진행 상황만 시작 노드로 되돌린다.
  /// 하트/레벨/인벤토리 같은 전역 RPG 상태는 건드리지 않는다(그건
  /// [resetProgress]의 몫 — 호출부가 필요하면 둘 다 부른다).
  void resetPackProgress(String packId, String startingNodeId) {
    _readingProgress[packId] = ReadingProgress(
      currentNodeId: startingNodeId,
      visitedNodeCount: 0,
    );
    _lastOpenedPackId = packId;
    notifyListeners();
  }

  final Map<String, int> _inventory = {};
  Map<String, int> get inventory => Map.unmodifiable(_inventory);

  int playerAttack = 8;
  int playerDefense = 5;

  int level = 1;
  int exp = 0;

  static const int maxHearts = 3;
  int hearts = maxHearts;

  /// 이번 회차(리셋 전까지)에 리워드 광고 부활을 이미 사용했는지.
  /// true가 되면 RevivalPage는 광고 대신 유료 재화 부활만 제시한다.
  bool hasUsedAdRevival = false;

  final Set<String> _ownedPackIds = {};
  Set<String> get ownedPackIds => Set.unmodifiable(_ownedPackIds);

  bool ownsPack(String packId) => _ownedPackIds.contains(packId);

  /// 서버(purchasePack Cloud Function)가 실제로 코인을 차감하고
  /// users/{uid}/save/current.ownedPackIds에 packId를 반영한 "뒤에" 호출한다
  /// (lib/reader/shared/paywall.dart 참고) — 여기서 로컬 상태를 먼저 바꾸지
  /// 않는다. 이후 아무 GameState 변경으로든 CloudSyncController가 전체
  /// 문서를 다시 덮어쓸 때, 이 로컬 Set이 서버가 방금 승인한 packId를 이미
  /// 포함하고 있어야 그 값을 실수로 되돌리지 않는다.
  void markPackOwned(String packId) {
    if (_ownedPackIds.add(packId)) {
      notifyListeners();
    }
  }

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

      playerAttack += 2;
      playerDefense += 1;
    }

    if (leveledUp) {
      hearts = maxHearts;
    }

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
    // 하트는 전투 중 loseHeart()/healHeart()로 이미 이 GameState에 실시간
    // 반영되어 있으므로, 여기서는 보상(아이템/경험치)만 적용하면 된다.
    for (final itemId in result.reward.itemIds) {
      _inventory[itemId] = (_inventory[itemId] ?? 0) + 1;
    }
    if (result.reward.exp > 0) {
      addExp(result.reward.exp);
    }
    notifyListeners();
  }

  /// 광고 시청 등으로 부활할 때 하트를 하나 회복시켜, 최소 하트 1개로
  /// 다음 공격/사건을 버틸 수 있게 한다.
  void revive() => healHeart();

  /// 전역 RPG 상태(인벤토리/레벨/경험치/능력치/하트)를 초기값으로 되돌린다.
  /// 팩별 읽기 위치(currentNodeId/visitedNodeCount)는 더 이상 여기서 다루지
  /// 않는다 — 그건 [resetPackProgress]의 몫이다. "처음부터 다시 시작"처럼
  /// 둘 다 초기화해야 하는 호출부는 이 메서드와 [resetPackProgress]를 함께
  /// 부른다.
  void resetProgress() {
    _inventory.clear();
    level = 1;
    exp = 0;
    playerAttack = 8;
    playerDefense = 5;
    hearts = maxHearts;
    hasUsedAdRevival = false;
    notifyListeners();
  }

  /// 세이브 데이터 구조 버전. 필드를 추가/변경할 때마다 올리고
  /// fromJson()에서 이전 버전 데이터도 기본값으로 채워 읽을 수 있게 한다.
  /// v6: currentNodeId/visitedNodeCount가 이 blob에서 빠지고
  /// users/{uid}/readingProgress/{packId}(ReadingProgressRepository)로
  /// 옮겨갔다 — 이 문서에 남아 있던 옛 값은 이제 그냥 무시된다.
  /// v7: cashBalance(그리고 addCash/spendCash)가 완전히 사라졌다 —
  /// 코인 충전(Toss)/이야기 팩 구매 둘 다 이제 users/{uid}/wallet/current의
  /// balance(서버, confirmCoinCharge/purchasePack Cloud Function만 변경)로
  /// 통합됐다. 옛 세이브에 cashBalance가 남아 있어도 loadFromJson이 그
  /// 키를 아예 안 읽으므로 조용히 무시된다 — 에러가 나지 않는다.
  static const int currentSchemaVersion = 7;

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'inventory': _inventory,
    'playerAttack': playerAttack,
    'playerDefense': playerDefense,
    'level': level,
    'exp': exp,
    'hearts': hearts,
    'hasUsedAdRevival': hasUsedAdRevival,
    'ownedPackIds': _ownedPackIds.toList(),
  };

  factory GameState.fromJson(Map<String, dynamic> json) {
    final state = GameState();
    state.loadFromJson(json);
    return state;
  }

  /// 이미 존재하는 인스턴스에 저장된 데이터를 덮어쓴다.
  /// 앱 시작 시 만들어진 [GameState]는 위젯 트리 전체가 구독하는 단일 인스턴스이므로,
  /// 로그인 후 클라우드 세이브를 불러올 때는 새 인스턴스로 교체하는 대신 이 메서드로
  /// 값만 갱신한다.
  void loadFromJson(Map<String, dynamic> json) {
    _inventory.clear();
    final inventoryJson = json['inventory'] as Map<String, dynamic>?;
    inventoryJson?.forEach((itemId, count) {
      _inventory[itemId] = count as int;
    });

    playerAttack = json['playerAttack'] as int? ?? playerAttack;
    playerDefense = json['playerDefense'] as int? ?? playerDefense;
    level = json['level'] as int? ?? level;
    exp = json['exp'] as int? ?? exp;
    hearts = json['hearts'] as int? ?? hearts;
    hasUsedAdRevival = json['hasUsedAdRevival'] as bool? ?? hasUsedAdRevival;
    // 옛 세이브(v6 이하)에 남아 있을 수 있는 cashBalance는 의도적으로 안
    // 읽는다 — 그 키가 json에 있어도 그냥 무시된다(에러 없음).

    _ownedPackIds.clear();
    final ownedPackIdsJson = json['ownedPackIds'] as List<dynamic>?;
    ownedPackIdsJson?.forEach((id) => _ownedPackIds.add(id as String));

    notifyListeners();
  }
}
