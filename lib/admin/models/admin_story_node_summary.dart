import 'admin_node_choice.dart';
import 'node_status.dart';
import 'pending_action.dart';

/// 노드를 한 줄로 가리킬 때 쓰는 짧은 라벨 — 첫 블록 텍스트의 앞 15자
/// 정도(없으면 노드 id 그대로). 노드 작성 카드 헤더("노드 {id} · {라벨}"),
/// ChoiceTargetPicker 카드, 스토리맵 팝오버 등 노드를 짧게 가리켜야 하는
/// 모든 자리에서 같은 값을 쓴다 — 자리마다 다른 잘라내기 규칙을 쓰면 같은
/// 노드가 위치마다 다르게 불리는 혼란이 생긴다.
String shortNodeLabel({required String id, required String firstBlockText}) {
  final trimmed = firstBlockText.trim();
  if (trimmed.isEmpty) return id;
  return trimmed.length > 15 ? '${trimmed.substring(0, 15)}…' : trimmed;
}

/// 사이드바 노드 목록 + 배경 이미지 인계 계산 + 스토리맵(story_map_view.dart)
/// 간선 렌더링에 필요한 필드를 담은 요약 모델. [preview]는 blocks 배열의 첫
/// 원소 text만 얕게 읽는다. choices/nextNodeId는 watchNodeSummaries()가 이미
/// 문서 전체를 읽어 오는 김에 같이 파싱하는 것뿐이라(Firestore 쪽에 별도
/// 필드 프로젝션 쿼리가 없다 — 문서 전체가 항상 함께 온다) 추가 네트워크
/// 비용은 없다.
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

  /// [backgroundImageId]가 설정돼 있을 때만 의미가 있다 — false면 이 노드는
  /// 배경 인계 체인 계산에서 건너뛴다(lib/core/story/
  /// background_image_inheritance.dart).
  final bool backgroundAppliesForward;

  /// liveSnapshot 존재 여부만(내용은 빼고) — 목록 스트림을 가볍게 유지하면서도
  /// StoryTabView가 "지금 편집 중인 노드가 서버에서 승인/반려됐는지"를 라이브로
  /// 감지하는 데 쓴다(liveSnapshot의 실제 내용은 여전히 fetchNode()로만 읽는다).
  final bool hasLiveSnapshot;

  /// storyPack.type == 'interactive'일 때만 의미가 있다 — 스토리맵의 간선을
  /// 그리는 데 쓴다.
  final List<AdminNodeChoice> choices;

  /// storyPack.type == 'linear'일 때만 의미가 있다 — 스토리맵의 간선을
  /// 그리는 데 쓴다.
  final String? nextNodeId;

  /// [shortNodeLabel] 참고 — [preview]의 앞 15자 정도(없으면 id).
  String get shortLabel => shortNodeLabel(id: id, firstBlockText: preview);

  const AdminStoryNodeSummary({
    required this.id,
    required this.preview,
    required this.status,
    required this.pendingAction,
    required this.order,
    required this.backgroundImageId,
    this.backgroundAppliesForward = true,
    required this.hasLiveSnapshot,
    this.choices = const [],
    this.nextNodeId,
  });

  factory AdminStoryNodeSummary.fromFirestore(
    String id,
    Map<String, dynamic> json,
  ) {
    final blocks = json['blocks'] as List<dynamic>?;
    final firstBlock = (blocks != null && blocks.isNotEmpty)
        ? blocks.first as Map<String, dynamic>?
        : null;
    final previewText = (firstBlock?['text'] as String?)?.trim() ?? '';

    final choices =
        (json['choices'] as List<dynamic>?)
            ?.map((e) => AdminNodeChoice.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <AdminNodeChoice>[];

    return AdminStoryNodeSummary(
      id: id,
      preview: previewText,
      status: NodeStatusJson.fromWire(json['status'] as String?),
      pendingAction: pendingActionFromWire(json['pendingAction'] as String?),
      order: (json['order'] as num?)?.toInt() ?? 0,
      backgroundImageId: json['backgroundImage'] as String?,
      backgroundAppliesForward:
          json['backgroundAppliesForward'] as bool? ?? true,
      hasLiveSnapshot: json['liveSnapshot'] != null,
      choices: choices,
      nextNodeId: json['nextNodeId'] as String?,
    );
  }
}
