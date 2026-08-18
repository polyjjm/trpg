import '../../core/text/paragraph_blocks.dart';
import 'admin_node_block.dart';
import 'admin_node_choice.dart';
import 'node_status.dart';
import 'pending_action.dart';

/// 스토리 노드 문서(storyPacks/{packId}/nodes/{nodeId}) 하나를 편집 세션 동안
/// 들고 있는 로컬 가변(mutable) 모델. 리더 쪽 blocks 구조(lib/reader/shared/
/// models/story_node.dart, Task 1)로 마이그레이션된 뒤의 모양이다 — 예전의
/// 평평한 day/title/body/bgImageId/choices(AdminChoice, move/battle/encounter/
/// merchant/item 분기) 구조는 완전히 대체됐다.
///
/// 이번 패스는 의도적으로 최소 범위다: blocks는 paragraph만, choices는
/// label/nextNodeId만 지원한다 — beat/image 블록, 드래그 재정렬, TTS override,
/// bgmOverride 필드는 리더 UI가 검증된 다음 패스에서 붙인다.
class AdminStoryNode {
  /// Firestore 문서 id. 새 노드는 저장 전까지 임시로 정한 값을 그대로 쓴다.
  String id;

  /// 선형 스토리의 챕터 순서 — 배경 이미지 인계(NodeEditor의 안내 문구,
  /// lib/core/story/background_image_inheritance.dart)가 "이 노드보다 앞선
  /// 노드"를 가리는 기준으로도 쓰인다.
  int order;

  /// 작가가 입력하는 원문 — 문단 사이에 빈 줄을 넣어 구분한다. [blocks]는
  /// 이 값을 저장(임시저장/승인요청) 시점에 [applyBodyTextToBlocks]로 나눈
  /// 결과일 뿐이라, 타이핑 중에는 서로 동기화되지 않는다(의도적 — "저장할
  /// 때 나뉜다"는 요구사항).
  String bodyText;

  /// Firestore에 실제로 저장되는 문단 블록 배열. [bodyText] 편집 중에는
  /// 갱신되지 않고, [applyBodyTextToBlocks] 호출 시점의 스냅샷을 그대로 담는다.
  List<AdminNodeBlock> blocks;

  /// images/{imageId} 참조 — 노드 상단 배경. null이면 이 노드는 배경을
  /// 명시적으로 고르지 않은 것이다 — storyPacks.defaultBackgroundImage까지
  /// 포함한 인계 규칙은 lib/core/story/background_image_inheritance.dart
  /// 참고(이 필드 자체는 항상 "이 노드가 명시적으로 고른 값"만 담는다).
  String? backgroundImageId;

  /// storyPack.type == 'interactive'일 때만 편집기에 노출/저장된다.
  List<AdminNodeChoice> choices;

  /// storyPack.type == 'linear'일 때만 편집기에 노출/저장된다.
  String? nextNodeId;

  NodeStatus status;
  PendingAction? pendingAction;

  /// 마지막으로 승인되어 실제 플레이어에게 보이는 콘텐츠 스냅샷
  /// (blocks/backgroundImage/choices/nextNodeId). 한 번도 승인된 적 없으면
  /// null — 이 값의 null 여부로 "신규 등록"인지 "기존 노드 수정"인지 판단한다.
  Map<String, dynamic>? liveSnapshot;

  /// 로컬 편집 세션에서만 쓰는 플래그. Firestore에는 저장하지 않는다.
  bool dirty;

  AdminStoryNode({
    required this.id,
    this.order = 0,
    this.bodyText = '',
    List<AdminNodeBlock>? blocks,
    this.backgroundImageId,
    List<AdminNodeChoice>? choices,
    this.nextNodeId,
    this.status = NodeStatus.draft,
    this.pendingAction,
    this.liveSnapshot,
    this.dirty = false,
  })  : blocks = blocks ?? const [],
        choices = choices ?? [];

  /// 이 노드가 Firestore에 한 번도 저장된 적 없는 순수 신규 노드인지.
  bool get isNew => liveSnapshot == null;

  /// [bodyText]를 문단 기준으로 나눠 [blocks]에 반영한다 — 저장(임시저장/
  /// 승인요청) 직전에만 호출한다. 그 전까지 [blocks]는 마지막으로 저장된
  /// 값 그대로다.
  void applyBodyTextToBlocks() {
    blocks = splitIntoParagraphs(bodyText).map((text) => AdminNodeBlock(text: text)).toList();
  }

  /// 사이드바/승인 대기함에 title 대신 보여줄 짧은 미리보기 — bodyText의
  /// 첫 문단(트림됨). blocks가 아니라 bodyText 기준이라 저장 전에도
  /// 타이핑한 내용이 그대로 반영된다.
  String get previewText {
    final paragraphs = splitIntoParagraphs(bodyText);
    return paragraphs.isEmpty ? '' : paragraphs.first;
  }

  factory AdminStoryNode.fromFirestore(String id, Map<String, dynamic> json) {
    final blocks = (json['blocks'] as List<dynamic>?)
            ?.map((e) => AdminNodeBlock.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <AdminNodeBlock>[];

    return AdminStoryNode(
      id: id,
      order: (json['order'] as num?)?.toInt() ?? 0,
      // blocks[].text를 빈 줄로 이어 붙여 편집 가능한 원문을 복원한다 —
      // NodeBodyEditor가 여는 순간부터 자연스러운 하나의 텍스트로 보이게 하려는 것.
      bodyText: blocks.map((b) => b.text).join('\n\n'),
      blocks: blocks,
      backgroundImageId: json['backgroundImage'] as String?,
      choices: (json['choices'] as List<dynamic>?)
              ?.map((e) => AdminNodeChoice.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextNodeId: json['nextNodeId'] as String?,
      status: NodeStatusJson.fromWire(json['status'] as String?),
      pendingAction: pendingActionFromWire(json['pendingAction'] as String?),
      liveSnapshot: (json['liveSnapshot'] as Map<String, dynamic>?),
    );
  }

  /// Firestore에 그대로 덮어쓸(set) 전체 필드. id는 문서 id라 포함하지 않는다.
  /// [blocks]가 [bodyText]를 반영한 최신 상태여야 하므로, 호출 전에 반드시
  /// [applyBodyTextToBlocks]를 먼저 불러야 한다(story_tab_view.dart의
  /// 저장 핸들러들이 그렇게 한다).
  Map<String, dynamic> toFirestoreJson() => {
        ...contentSnapshot(),
        'status': status.wireValue,
        'pendingAction': pendingAction?.wireValue,
        'liveSnapshot': liveSnapshot,
      };

  /// 승인 시 liveSnapshot에 복사해 넣을, 지금 이 순간의 콘텐츠 스냅샷.
  Map<String, dynamic> contentSnapshot() => {
        'order': order,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'backgroundImage': backgroundImageId,
        'choices': choices.isEmpty ? null : choices.map((c) => c.toJson()).toList(),
        'nextNodeId': nextNodeId,
      };
}
