import 'node_status.dart';
import 'pending_action.dart';

/// 사이드바 노드 목록 + 배경 이미지 인계 계산에 필요한 최소 필드만 담은
/// 요약 모델. blocks/choices까지 전부 역직렬화하지 않아 목록 스트림이
/// 가볍다 — [preview]는 blocks 배열의 첫 원소 text만 얕게 읽는다.
class AdminStoryNodeSummary {
  final String id;

  /// title 필드가 없어진 새 스키마에서 목록에 보여줄 짧은 미리보기 —
  /// 첫 번째 블록의 텍스트(트림됨). 블록이 없으면 빈 문자열.
  final String preview;

  final NodeStatus status;
  final PendingAction? pendingAction;

  /// 배경 이미지 인계 계산(lib/core/story/background_image_inheritance.dart)의
  /// 기준이 되는 순서.
  final int order;

  /// 이 노드가 명시적으로 고른 배경 이미지. null이면 인계받는 노드다.
  final String? backgroundImageId;

  const AdminStoryNodeSummary({
    required this.id,
    required this.preview,
    required this.status,
    required this.pendingAction,
    required this.order,
    required this.backgroundImageId,
  });

  factory AdminStoryNodeSummary.fromFirestore(String id, Map<String, dynamic> json) {
    final blocks = json['blocks'] as List<dynamic>?;
    final firstBlock = (blocks != null && blocks.isNotEmpty) ? blocks.first as Map<String, dynamic>? : null;
    final previewText = (firstBlock?['text'] as String?)?.trim() ?? '';

    return AdminStoryNodeSummary(
      id: id,
      preview: previewText,
      status: NodeStatusJson.fromWire(json['status'] as String?),
      pendingAction: pendingActionFromWire(json['pendingAction'] as String?),
      order: (json['order'] as num?)?.toInt() ?? 0,
      backgroundImageId: json['backgroundImage'] as String?,
    );
  }
}
