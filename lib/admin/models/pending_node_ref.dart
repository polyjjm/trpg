import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_story_node.dart';

/// 승인 대기함에 표시되는 항목 하나 — 어느 스토리팩 소속인지와 함께 들고 있어야
/// 승인/반려 시 올바른 서브컬렉션에 다시 쓸 수 있다.
///
/// [requestedAt]은 노드 문서의 `approvalRequestedAt`(승인 요청 시점에
/// serverTimestamp로 기록) — 개요 화면의 "대기" 열과 "가장 오래 기다린 요청"
/// 문구가 이 값만 쓴다. 이 필드가 붙기 전에 제출된 노드는 null이라,
/// 표시 쪽에서 항상 null을 감안해야 한다(개요는 '-'로 보여준다).
class PendingNodeRef {
  final String packId;
  final AdminStoryNode node;
  final DateTime? requestedAt;

  const PendingNodeRef({
    required this.packId,
    required this.node,
    this.requestedAt,
  });

  static DateTime? requestedAtFrom(Map<String, dynamic> json) =>
      (json['approvalRequestedAt'] as Timestamp?)?.toDate();
}
