/// 사용자가 특정 스토리팩(packId)에서 어디까지 읽었는지. GameState가 예전엔
/// currentNodeId/visitedNodeCount를 앱 전체에 하나만 갖고 있어서, 팩을
/// 옮겨다니면(한 팩을 읽다 다른 팩을 열었다 돌아오면) 서로의 위치를 그냥
/// 덮어썼다 — 그 값 두 개를 팩별로 쪼갠 게 이 모델이다(GameState의
/// Map<String, ReadingProgress> _readingProgress, packId로 키).
///
/// Firestore 직렬화는 이 클래스가 직접 하지 않는다 — GameState가 그렇듯
/// 이 모델도 Firestore를 모르는 순수 값 객체로 두고, 실제 문서 읽기/쓰기는
/// ReadingProgressRepository가 담당한다(users/{uid}/save/current를
/// GameState 대신 다루는 CloudSaveService와 같은 경계).
class ReadingProgress {
  final String currentNodeId;

  /// 지금까지 이 팩에서 이동한(다음 노드로 넘어간) 횟수 — 유료 팩의 무료
  /// 미리보기 한도(StoryPack.previewNodeLimit) 판단에 쓰인다.
  final int visitedNodeCount;

  /// 마지막으로 이 팩을 읽은 시각. 로그인 사용자만 실제 값을 갖는다
  /// (ReadingProgressRepository.save가 서버 타임스탬프로 채운다) — 게스트의
  /// 메모리 전용 진행 상황은 지금 UI 어디서도 이 값을 안 써서 null로 둔다.
  final DateTime? lastReadAt;

  /// currentNodeId가 이 팩의 마지막 노드(인터랙티브는 choices가 없는 결말,
  /// 선형은 nextNodeId가 없는 마지막 챕터)인지 — InteractiveReader/
  /// LinearReader가 다음 노드로 넘어가는 시점에 그 목적지 노드가 마지막인지
  /// 직접 판단해서 채운다(내 서재 탭의 완료 배지에 쓰인다).
  final bool completed;

  const ReadingProgress({
    required this.currentNodeId,
    required this.visitedNodeCount,
    this.lastReadAt,
    this.completed = false,
  });
}
