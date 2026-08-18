/// storyPacks/{packId}/nodes 문서 하나가 세 가지 스키마 세대 중 어디에
/// 해당하는지 판정하는 순수 로직. Firebase/Flutter에 의존하지 않는다.
///
/// - "옛 평평한" 세대: body/day/title 필드.
/// - "옛 선택지 트리거" 세대: choices 배열 원소가 AdminChoice 모양
///   (type/mode/battleId/winNode/loseNode/escapeNode/encounterId/itemId/
///   itemCount/random 중 하나라도 있음, lib/admin/models/admin_choice.dart —
///   Task B에서 삭제됨).
/// - "새 blocks" 세대: blocks 필드, choices는 있다면 label/nextNodeId만.
///
/// 세 세대는 서로 배타적이지 않다 — 한 문서가 옛 필드와 새 필드를 동시에
/// 갖고 있을 수도 있어서(예: 수동 편집, 마이그레이션 중간 상태) 각각 독립적인
/// bool로 판정한다.
library;

const _legacyChoiceTriggerKeys = {
  'type',
  'mode',
  'battleId',
  'winNode',
  'loseNode',
  'escapeNode',
  'encounterId',
  'itemId',
  'itemCount',
  'random',
};

bool _isLegacyChoiceElement(Map<String, dynamic> choice) {
  return _legacyChoiceTriggerKeys.any(choice.containsKey);
}

bool _isNewShapeChoiceElement(Map<String, dynamic> choice) {
  return choice.containsKey('label') && choice.containsKey('nextNodeId') && !_isLegacyChoiceElement(choice);
}

class NodeShapeAudit {
  final String packId;
  final String nodeId;

  /// body 필드가 있다(옛 평평한 본문).
  final bool hasFlatBody;

  /// day 또는 title 필드가 있다(옛 평평한 세대의 나머지 필드).
  final bool hasLegacyTitleOrDay;

  /// blocks 필드가 있다(새 세대).
  final bool hasBlocks;

  /// choices 배열이 있고, 그 원소 중 하나 이상이 AdminChoice(옛 선택지
  /// 트리거) 모양이다 — 지금 편집기(NodeEditor/AdminNodeChoice)로는 이
  /// 정보를 표현·저장할 수 없다.
  final bool hasLegacyChoiceTriggers;

  /// choices 배열이 있고 비어있지 않으며, 모든 원소가 새 label/nextNodeId
  /// 모양이다.
  final bool hasNewStyleChoices;

  /// nextNodeId 필드가 있다(선형 노드 또는 분기 없는 인터랙티브 노드).
  final bool hasNextNodeId;

  const NodeShapeAudit({
    required this.packId,
    required this.nodeId,
    required this.hasFlatBody,
    required this.hasLegacyTitleOrDay,
    required this.hasBlocks,
    required this.hasLegacyChoiceTriggers,
    required this.hasNewStyleChoices,
    required this.hasNextNodeId,
  });

  /// 지금 NodeEditor(AdminStoryNode.fromFirestore)로 열었을 때 내용이
  /// 조용히 사라질 위험이 있는 문서인지 — body만 있고 blocks가 없거나,
  /// 옛 선택지 트리거가 있는 경우. AdminStoryNode.fromFirestore는 이런
  /// 필드를 그냥 무시하고(에러 없이) 빈 블록/빈 라벨로 읽어들인다.
  bool get atRiskOfSilentDataLoss => (hasFlatBody && !hasBlocks) || hasLegacyChoiceTriggers;

  factory NodeShapeAudit.fromFirestore(String packId, String nodeId, Map<String, dynamic> data) {
    final rawChoices = data['choices'];
    final choices = rawChoices is List
        ? rawChoices.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];

    return NodeShapeAudit(
      packId: packId,
      nodeId: nodeId,
      hasFlatBody: data.containsKey('body'),
      hasLegacyTitleOrDay: data.containsKey('title') || data.containsKey('day'),
      hasBlocks: data.containsKey('blocks'),
      hasLegacyChoiceTriggers: choices.any(_isLegacyChoiceElement),
      hasNewStyleChoices: choices.isNotEmpty && choices.every(_isNewShapeChoiceElement),
      hasNextNodeId: data.containsKey('nextNodeId'),
    );
  }
}
