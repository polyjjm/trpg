import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/text/paragraph_blocks.dart';
import '../data/node_diff.dart';
import 'admin_node_block.dart';
import 'admin_node_choice.dart';
import 'node_effects.dart';
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

  /// [backgroundImageId]가 설정돼 있을 때만 의미가 있다 — true(기본값)면 이
  /// 배경이 다음에 배경을 명시적으로 고르는 노드가 나올 때까지 이후 노드들에
  /// 자동으로 이어서 적용된다. false면 이 노드 자신에게만 적용되고, 다음 노드는
  /// (명시적으로 고르지 않았다면) 이 노드를 건너뛰어 그 이전에 이어져 오던
  /// 값을 그대로 물려받는다(lib/core/story/background_image_inheritance.dart).
  bool backgroundAppliesForward;

  /// storyPack.type == 'interactive'일 때만 편집기에 노출/저장된다.
  List<AdminNodeChoice> choices;

  /// storyPack.type == 'linear'일 때만 편집기에 노출/저장된다.
  String? nextNodeId;

  /// 연출 효과(암전/화면 흔들림/효과음/진동) — 전부 프리셋 전용, 기본은
  /// 꺼짐. 지금은 리더에서 실제로 재생되지 않는다("연출 효과" UI/스키마만
  /// 붙인 패스) — 실제 재생은 에셋이 준비된 다음 패스의 몫이다.
  NodeEffects effects;

  NodeStatus status;
  PendingAction? pendingAction;

  /// 마지막 반려 사유 — admin이 등록/수정 요청을 반려할 때 적는다
  /// (approvals_tab.dart). 승인되면(approveNode) 지워지고, 작가가 다시
  /// 손봐서 재제출하면(requestApprovalForNode) 그 시점에도 지워진다 —
  /// 새로 제출한 버전에 옛 반려 사유가 계속 붙어 있으면 안 되기 때문이다.
  /// null이면 반려된 적이 없거나, 반려 이후 이미 재제출/승인됐다는 뜻.
  String? rejectionReason;

  /// 마지막으로 승인되어 실제 플레이어에게 보이는 콘텐츠 스냅샷
  /// (blocks/backgroundImage/choices/nextNodeId). 한 번도 승인된 적 없으면
  /// null — 이 값의 null 여부로 "신규 등록"인지 "기존 노드 수정"인지 판단한다.
  Map<String, dynamic>? liveSnapshot;

  /// 승인 요청(등록/수정/삭제)을 보낸 시점 — 관리자 개요의 "대기" 열과
  /// "가장 오래 기다린 요청" 문구가 이 값만 쓴다.
  ///
  /// 서버가 채우는 값이라(AdminStoryRepository.stampApprovalRequestedAt이
  /// serverTimestamp로 쓴다) 이 모델은 읽어서 그대로 다시 쓰기만 한다 —
  /// liveSnapshot/ttsAudioUrl과 똑같은 "그냥 보존만 하는 필드"다. 보존이
  /// 필요한 이유: saveNode()는 `.set()` 전체 덮어쓰기라, 이 필드를 모델에
  /// 넣지 않으면 작가가 그 뒤에 임시저장을 한 번만 해도 값이 날아간다.
  ///
  /// 승인/반려로 pendingAction이 비어도 굳이 지우지 않는다 — 마지막 요청
  /// 시각으로 남겨두는 편이 나중에 되짚기 쉽다.
  DateTime? approvalRequestedAt;

  /// TTS 캐시 — synthesizeNodeTts Cloud Function만 쓴다(Admin SDK로 규칙을
  /// 우회해서 쓴다). 이 모델은 이 두 필드를 읽어서 그대로 다시 쓰기만 한다
  /// (절대 값을 스스로 계산/변경하지 않는다) — [toFirestoreJson]이 이
  /// 필드들을 payload에 포함하지 않으면, saveNode()의 전체 덮어쓰기(`.set()`)가
  /// 매번 작가의 무관한 draft 저장만으로도 캐시를 지워버려서, 다음 리더가
  /// 실제로는 그대로인 라이브 콘텐츠에 대해 또 Typecast를 호출하게 되는
  /// 낭비가 생긴다 — 그래서 liveSnapshot/rejectionReason과 똑같이 "그냥
  /// 보존만 하는" 필드로 모델에 포함시켰다. [contentSnapshot]에는 포함하지
  /// 않는다 — 작가가 쓴 콘텐츠가 아니라 서버가 만든 캐시 산출물이라
  /// liveSnapshot으로 복사될 대상이 아니다.
  String? ttsAudioUrl;
  String? ttsAudioGeneratedForBodyHash;

  /// "미리듣기" 잠정 캐시 — previewNodeTts Cloud Function만 쓴다(작가가 아직
  /// 저장도 안 한 초안으로 미리 들어본 결과). [ttsAudioUrl]/
  /// [ttsAudioGeneratedForBodyHash]와 똑같은 "그냥 보존만 하는" 이유로
  /// 모델에 포함된다 — 승인 시점에 해시가 일치하면(초안이 그대로 승인됐으면)
  /// onNodeApprovedGenerateTts가 이 파일을 재생성 없이 그대로 ttsAudioUrl로
  /// 승격한다(functions/src/index.ts 참고). [contentSnapshot]에는 포함하지
  /// 않는다 — 이유는 위 ttsAudioUrl과 같다.
  String? ttsPreviewAudioUrl;
  String? ttsPreviewAudioGeneratedForBodyHash;

  /// 로컬 편집 세션에서만 쓰는 플래그. Firestore에는 저장하지 않는다.
  bool dirty;

  AdminStoryNode({
    required this.id,
    this.order = 0,
    this.bodyText = '',
    List<AdminNodeBlock>? blocks,
    this.backgroundImageId,
    this.backgroundAppliesForward = true,
    List<AdminNodeChoice>? choices,
    this.nextNodeId,
    this.effects = const NodeEffects(),
    this.status = NodeStatus.draft,
    this.pendingAction,
    this.liveSnapshot,
    this.rejectionReason,
    this.approvalRequestedAt,
    this.ttsAudioUrl,
    this.ttsAudioGeneratedForBodyHash,
    this.ttsPreviewAudioUrl,
    this.ttsPreviewAudioGeneratedForBodyHash,
    this.dirty = false,
  }) : blocks = blocks ?? [],
       choices = choices ?? [];

  /// 이 노드가 Firestore에 한 번도 저장된 적 없는 순수 신규 노드인지.
  bool get isNew => liveSnapshot == null;

  /// [bodyText]를 문단 기준으로 나눠 [blocks]에 반영한다 — "한 번에 쓰기"
  /// (BulkNodeWriter)에서 붙여넣은 긴 텍스트를 문단 블록으로 변환할 때만
  /// 쓴다. 단일 노드 편집(NodeEditor)은 이제 [blocks]를 직접 수정하므로
  /// bodyText를 거치지 않는다.
  void applyBodyTextToBlocks() {
    blocks = splitIntoParagraphs(
      bodyText,
    ).map((text) => AdminNodeBlock(text: text)).toList();
  }

  /// 사이드바/승인 대기함에 title 대신 보여줄 짧은 미리보기 — 첫 번째
  /// 블록의 텍스트(트림됨). 블록이 없으면 빈 문자열.
  String get previewText {
    if (blocks.isEmpty) return '';
    return blocks.first.text.trim();
  }

  factory AdminStoryNode.fromFirestore(String id, Map<String, dynamic> json) {
    final blocks =
        (json['blocks'] as List<dynamic>?)
            ?.map((e) => AdminNodeBlock.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <AdminNodeBlock>[];

    return AdminStoryNode(
      id: id,
      order: (json['order'] as num?)?.toInt() ?? 0,
      blocks: blocks,
      backgroundImageId: json['backgroundImage'] as String?,
      backgroundAppliesForward:
          json['backgroundAppliesForward'] as bool? ?? true,
      choices:
          (json['choices'] as List<dynamic>?)
              ?.map((e) => AdminNodeChoice.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextNodeId: json['nextNodeId'] as String?,
      effects: NodeEffects.fromJson(json['effects'] as Map<String, dynamic>?),
      status: NodeStatusJson.fromWire(json['status'] as String?),
      pendingAction: pendingActionFromWire(json['pendingAction'] as String?),
      liveSnapshot: (json['liveSnapshot'] as Map<String, dynamic>?),
      rejectionReason: json['rejectionReason'] as String?,
      approvalRequestedAt: (json['approvalRequestedAt'] as Timestamp?)
          ?.toDate(),
      ttsAudioUrl: json['ttsAudioUrl'] as String?,
      ttsAudioGeneratedForBodyHash:
          json['ttsAudioGeneratedForBodyHash'] as String?,
      ttsPreviewAudioUrl: json['ttsPreviewAudioUrl'] as String?,
      ttsPreviewAudioGeneratedForBodyHash:
          json['ttsPreviewAudioGeneratedForBodyHash'] as String?,
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
    'rejectionReason': rejectionReason,
    'approvalRequestedAt': approvalRequestedAt == null
        ? null
        : Timestamp.fromDate(approvalRequestedAt!),
    'ttsAudioUrl': ttsAudioUrl,
    'ttsAudioGeneratedForBodyHash': ttsAudioGeneratedForBodyHash,
    'ttsPreviewAudioUrl': ttsPreviewAudioUrl,
    'ttsPreviewAudioGeneratedForBodyHash': ttsPreviewAudioGeneratedForBodyHash,
  };

  /// 승인 시 liveSnapshot에 복사해 넣을, 지금 이 순간의 콘텐츠 스냅샷.
  Map<String, dynamic> contentSnapshot() => {
    'order': order,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'backgroundImage': backgroundImageId,
    'backgroundAppliesForward': backgroundAppliesForward,
    'choices': choices.isEmpty ? null : choices.map((c) => c.toJson()).toList(),
    'nextNodeId': nextNodeId,
    'effects': effects.toJson(),
  };

  /// 이 노드가 "아직 승인 요청을 보내지 않은, 라이브 버전과 다른 내용"을
  /// 갖고 있는지 — sidebar의 "수정됨" 배지, "변경사항 전체 승인요청" 버튼,
  /// 승인 대기함의 "내용상 변경 없음" 판정까지 전부 이 getter 하나만 부른다.
  /// 실제 비교는 [NodeDiff.compute]에 통째로 위임한다(node_diff.dart의
  /// 클래스 doc 참고 — 이 계산 로직을 여러 곳에 따로 두지 않기 위해
  /// 그쪽으로 모았다). 이미 승인 요청이 걸려 있으면(pendingAction != null)
  /// 그 자체로 false — 제출 대상이 아니다.
  bool get hasUnsubmittedChanges {
    if (pendingAction != null) return false;
    return NodeDiff.compute(this).anyChanged;
  }
}
