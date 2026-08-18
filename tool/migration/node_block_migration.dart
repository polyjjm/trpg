/// storyPacks/{packId}/nodes 문서를 옛 평평한 구조(body/bgImageId)에서 새
/// blocks 구조(lib/reader/shared/models/story_node.dart)로 바꾸는 순수 변환
/// 로직. Firebase/Flutter에 의존하지 않아 dry-run 스크립트와 (나중에 붙일)
/// 단위 테스트 양쪽에서 그대로 재사용할 수 있다.
library;

import 'package:sotry_trpg/core/text/paragraph_blocks.dart';

/// 옛 평평한 구조 노드인지 — `body` 필드가 있고 `blocks` 필드가 없으면
/// 아직 마이그레이션 안 된 문서로 본다. 두 필드가 동시에 있는 문서(마이그레이션
/// 중간에 걸린 경우)는 이 함수 밖에서 별도로 다뤄야 해서 여기선 old로 치지 않는다.
bool isOldFlatShapeNode(Map<String, dynamic> data) {
  return data.containsKey('body') && !data.containsKey('blocks');
}

/// 본문을 빈 줄 기준으로 나눠 paragraph 블록 목록을 만든다. 실제 분리
/// 규칙(splitIntoParagraphs)은 작가 편집기(NodeBodyEditor)와 공유한다 —
/// lib/core/text/paragraph_blocks.dart 참고.
List<Map<String, dynamic>> splitBodyIntoParagraphBlocks(String body) {
  return splitIntoParagraphs(
    body,
  ).map((segment) => <String, dynamic>{'type': 'paragraph', 'text': segment}).toList();
}

/// 노드 하나의 마이그레이션 미리보기 — Firestore에 쓰지 않고 보고서 출력에만 쓴다.
class NodeMigrationPreview {
  final String packId;
  final String nodeId;
  final String oldBody;
  final String? oldBgImageId;
  final List<Map<String, dynamic>> proposedBlocks;
  final String? proposedBackgroundImage;

  const NodeMigrationPreview({
    required this.packId,
    required this.nodeId,
    required this.oldBody,
    required this.oldBgImageId,
    required this.proposedBlocks,
    required this.proposedBackgroundImage,
  });

  factory NodeMigrationPreview.fromOldNode(
    String packId,
    String nodeId,
    Map<String, dynamic> data,
  ) {
    final body = data['body'] as String? ?? '';
    final bgImageId = data['bgImageId'] as String?;
    return NodeMigrationPreview(
      packId: packId,
      nodeId: nodeId,
      oldBody: body,
      oldBgImageId: bgImageId,
      proposedBlocks: splitBodyIntoParagraphBlocks(body),
      proposedBackgroundImage: bgImageId,
    );
  }
}
