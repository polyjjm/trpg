import 'admin_story_node.dart';

/// 승인 대기함에 표시되는 항목 하나 — 어느 스토리팩 소속인지와 함께 들고 있어야
/// 승인/반려 시 올바른 서브컬렉션에 다시 쓸 수 있다.
class PendingNodeRef {
  final String packId;
  final AdminStoryNode node;

  const PendingNodeRef({required this.packId, required this.node});
}
