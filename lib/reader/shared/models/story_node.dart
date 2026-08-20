import 'bgm_override.dart';
import 'choice.dart';
import 'node_block.dart';
import 'node_effects.dart';

/// storyPacks/{storyId}/nodes/{nodeId} 문서 — 인터랙티브/선형 스토리 공통으로
/// 쓰는 리더 전용 노드 모델. admin 쪽 AdminStoryNode(lib/admin/models/
/// admin_story_node.dart, blocks/choices/nextNodeId를 mutable 편집 세션용으로
/// 들고 있는 별개 클래스)가 실제로 이 문서를 써 넣는다.
class StoryNode {
  final String id;

  /// 선형 스토리의 챕터 순서(및 인터랙티브 스토리 편집기 내 정렬)에 쓰는 값.
  final int order;

  /// images/{imageId} 참조(URL 아님) — AdminStoryPack.coverImageId와 같은
  /// 패턴이다. 이 리더 모델은 아직 URL로 resolve하지 않는다 — 노드를 읽는
  /// 데이터 레이어(Task 3/4에서 추가)가 images 컬렉션에서 조인해야 한다.
  final String? backgroundImage;

  /// [backgroundImage]가 설정돼 있을 때만 의미가 있다 — false면 이 노드는
  /// 배경 인계 체인에서 건너뛴다(작가가 "이 노드에만 적용"을 선택한 경우,
  /// lib/core/story/background_image_inheritance.dart).
  final bool backgroundAppliesForward;

  /// 이 노드에서만 storyPack.ambientBgm 대신 재생할 트랙. null이면 팩의
  /// 기본 ambientBgm을 그대로 이어서 쓴다.
  final BgmOverride? bgmOverride;

  /// 연출 효과(암전/화면 흔들림/효과음/진동) — SceneFrame이 타이핑 완료
  /// 시점에 재생한다. sfx.sfxId는 URL이 아니라 sfxLibrary/{sfxId} 참조라,
  /// [backgroundImage]와 같은 이유로 데이터 레이어(StoryReaderRepository)가
  /// 실제 재생 URL로 조인해 ResolvedStoryNode.sfxUrl에 담아 준다.
  final NodeEffects effects;

  final List<NodeBlock> blocks;

  /// storyPack.type == 'interactive'인 팩의 노드만 값을 갖는다. 선형
  /// 스토리이거나 분기 없는 인터랙티브 노드는 null.
  final List<Choice>? choices;

  /// 선형 스토리의 자동 다음 챕터, 또는 분기 없는 인터랙티브 노드의 다음
  /// 노드. 마지막 노드면 null.
  final String? nextNodeId;

  const StoryNode({
    required this.id,
    required this.order,
    this.backgroundImage,
    this.backgroundAppliesForward = true,
    this.bgmOverride,
    this.effects = const NodeEffects(),
    required this.blocks,
    this.choices,
    this.nextNodeId,
  });

  factory StoryNode.fromFirestore(String id, Map<String, dynamic> json) {
    final bgmOverrideJson = json['bgmOverride'] as Map<String, dynamic>?;
    final choicesJson = json['choices'] as List<dynamic>?;

    return StoryNode(
      id: id,
      order: (json['order'] as num?)?.toInt() ?? 0,
      backgroundImage: json['backgroundImage'] as String?,
      backgroundAppliesForward:
          json['backgroundAppliesForward'] as bool? ?? true,
      bgmOverride: bgmOverrideJson != null
          ? BgmOverride.fromJson(bgmOverrideJson)
          : null,
      effects: NodeEffects.fromJson(json['effects'] as Map<String, dynamic>?),
      blocks:
          (json['blocks'] as List<dynamic>?)
              ?.map((e) => NodeBlock.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      choices: choicesJson
          ?.map((e) => Choice.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextNodeId: json['nextNodeId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'order': order,
    'backgroundImage': backgroundImage,
    'backgroundAppliesForward': backgroundAppliesForward,
    'bgmOverride': bgmOverride?.toJson(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'choices': choices?.map((c) => c.toJson()).toList(),
    'nextNodeId': nextNodeId,
  };
}
