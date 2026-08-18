/// 텍스트를 빈 줄(사이에 공백만 있어도 빈 줄로 친다) 기준으로 나눠, 각
/// 조각을 트림한 문단 목록을 만든다. 트림 후 빈 조각은 버린다.
///
/// 작가 편집기의 본문 입력(NodeBodyEditor → AdminStoryNode.applyBodyTextToBlocks,
/// lib/admin/models/admin_story_node.dart)과 blocks 마이그레이션 dry-run 도구
/// (tool/migration/node_block_migration.dart)가 공유하는 단 하나의 분리 규칙이다
/// — 두 곳에서 각자 구현하면 규칙이 갈라질 수 있어 여기 한 곳에 둔다.
List<String> splitIntoParagraphs(String text) {
  return text
      .split(RegExp(r'\n\s*\n'))
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
}
