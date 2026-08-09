import 'node_status.dart';
import 'pending_action.dart';

/// 사이드바 노드 목록에 필요한 최소 필드만 담은 요약 모델.
/// choices까지 전부 역직렬화하지 않아 목록 스트림이 가볍다.
class AdminStoryNodeSummary {
  final String id;
  final String title;
  final NodeStatus status;
  final PendingAction? pendingAction;

  const AdminStoryNodeSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.pendingAction,
  });

  factory AdminStoryNodeSummary.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminStoryNodeSummary(
      id: id,
      title: json['title'] as String? ?? '',
      status: NodeStatusJson.fromWire(json['status'] as String?),
      pendingAction: pendingActionFromWire(json['pendingAction'] as String?),
    );
  }
}
