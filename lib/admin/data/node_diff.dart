import 'dart:convert';

import 'package:diff_match_patch/diff_match_patch.dart';

import '../models/admin_node_choice.dart';
import '../models/admin_story_node.dart';
import '../models/node_effects.dart';

/// 승인 대기 노드 하나의 "지금 편집 중인 내용"(after) vs "마지막으로 승인된
/// 스냅샷"(liveSnapshot, before)을 비교한 결과 — **이 프로젝트에서 "이 노드가
/// liveSnapshot과 다른가"를 답하는 유일한 곳**이다. 사이드바 "수정됨" 배지,
/// "변경사항 전체 승인요청" 버튼의 포함 여부(둘 다
/// [AdminStoryNode.hasUnsubmittedChanges]가 여기 [anyChanged]를 그대로
/// 위임한다), admin 승인 대기함의 diff 렌더링과 "내용상 변경 없음" 판정
/// (`ApprovalsTab`)까지 전부 이 계산 결과 하나만 쓴다.
///
/// 예전엔 이 셋이 서로 다른 비교 로직을 각자 갖고 있었다 — 배지는 세션 캐시
/// 존재 여부만, 버튼은 [AdminStoryNode.contentSnapshot]과 liveSnapshot을
/// 직접 jsonEncode 비교, 승인 화면은 본문/순서/배경 이미지/선택지 네 개만
/// 보고 `effects`는 아예 비교 대상에 없었다 — 그래서 노드가 실제로 바뀌었는데도
/// 화면마다 "바뀜"/"안 바뀜" 판정이 어긋나는 버그가 반복해서 났다(가장 최근엔
/// `effects.bgm`을 추가했을 때, 버튼 쪽은 고쳤지만 이 승인 화면 쪽은 그대로
/// 남아 있었다). 지금은 이 클래스 하나로 모으고, [AdminStoryNode]는 이
/// 클래스를 그대로 불러 쓴다(admin_story_node.dart가 이 파일을 import하고,
/// 이 파일도 [AdminStoryNode]를 import하는 순환 참조지만 — 둘 다 순수 클래스
/// 정의라 Dart에서 문제없이 컴파일된다).
class NodeDiff {
  final List<Diff> bodySegments;
  final bool bodyChanged;
  final String? beforeBackgroundImageId;
  final String? afterBackgroundImageId;
  final bool backgroundChanged;
  final int? beforeOrder;
  final int afterOrder;
  final bool orderChanged;
  final List<AdminNodeChoice> addedChoices;
  final List<AdminNodeChoice> removedChoices;
  final bool choicesChanged;

  /// `effects`(blackout/shake/sfx/flash/haptic/bgm/...) 전체를 하나의 map으로
  /// 놓고 통째로(구조적으로) 비교한 결과다 — **어떤 하위 필드가 바뀌었는지는
  /// 따지지 않는다.** 의도적인 설계다: 만약 여기서 "blackout이 바뀌었나?
  /// shake는? sfx는?..."처럼 알려진 효과 종류를 하나씩 나열해 비교했다면, 앞으로
  /// 새 효과 타입을 추가할 때마다 이 목록에도 매번 하나씩 손으로 더해야 하고
  /// (빠뜨리면 그 효과만 diff에서 안 잡히는 지금 이 버그가 다시 난다), 그 목록
  /// 유지는 실제로 그 효과를 동작시키는 작업과는 완전히 별개의, 잊기 쉬운
  /// 곁가지 작업이 된다. `NodeEffects.toJson()`/`fromJson()`에 새 필드를
  /// 넣는 것 — 그 효과가 실제로 동작하려면 어차피 반드시 해야 하는 작업 —
  /// 만으로 diff 대상에도 자동으로 포함되게 하려고, 두 스냅샷을 각각
  /// `NodeEffects.fromJson(...).toJson()`으로 정규화한 뒤 [jsonEncode]로
  /// 통째로 비교한다.
  final bool effectsChanged;

  final bool isBrandNew;

  /// 이 노드가 조금이라도 바뀌었는지 — 위 다섯 불리언의 OR에 [isBrandNew]를
  /// 더한 것(신규 노드는 내용이 뭐든 항상 "제출할 변경사항"이다 — 존재
  /// 자체가 변경이므로). "내용상 변경 없음" 배너와
  /// [AdminStoryNode.hasUnsubmittedChanges] 둘 다 이 값 하나만 본다.
  bool get anyChanged =>
      isBrandNew ||
      bodyChanged ||
      orderChanged ||
      backgroundChanged ||
      choicesChanged ||
      effectsChanged;

  const NodeDiff({
    required this.bodySegments,
    required this.bodyChanged,
    required this.beforeBackgroundImageId,
    required this.afterBackgroundImageId,
    required this.backgroundChanged,
    required this.beforeOrder,
    required this.afterOrder,
    required this.orderChanged,
    required this.addedChoices,
    required this.removedChoices,
    required this.choicesChanged,
    required this.effectsChanged,
    required this.isBrandNew,
  });

  /// "N번째" 표시용 — 0-based order를 사람이 읽는 1-based 순번으로.
  static String orderRankLabel(int order) => '${order + 1}번째';

  factory NodeDiff.compute(AdminStoryNode node) {
    final live = node.liveSnapshot;

    final beforeText = _bodyTextFrom(live);
    final afterText = node.blocks.map((b) => b.text).join('\n\n');
    final dmp = DiffMatchPatch();
    final segments = dmp.diff(beforeText, afterText);
    dmp.diffCleanupSemantic(segments);

    final beforeBg = live?['backgroundImage'] as String?;
    final afterBg = node.backgroundImageId;

    final isBrandNew = live == null;
    final beforeOrder = (live?['order'] as num?)?.toInt();
    final afterOrder = node.order;

    final beforeChoices = _choicesFrom(live);
    final afterChoices = node.choices;
    final removed = beforeChoices
        .where((b) => !afterChoices.any((a) => _choiceEquals(a, b)))
        .toList();
    final added = afterChoices
        .where((a) => !beforeChoices.any((b) => _choiceEquals(a, b)))
        .toList();

    final beforeEffectsJson = NodeEffects.fromJson(
      live?['effects'] as Map<String, dynamic>?,
    ).toJson();
    final afterEffectsJson = node.effects.toJson();

    return NodeDiff(
      bodySegments: segments,
      bodyChanged: beforeText != afterText,
      beforeBackgroundImageId: beforeBg,
      afterBackgroundImageId: afterBg,
      backgroundChanged: beforeBg != afterBg,
      beforeOrder: beforeOrder,
      afterOrder: afterOrder,
      orderChanged: !isBrandNew && beforeOrder != afterOrder,
      addedChoices: added,
      removedChoices: removed,
      choicesChanged: added.isNotEmpty || removed.isNotEmpty,
      effectsChanged:
          jsonEncode(beforeEffectsJson) != jsonEncode(afterEffectsJson),
      isBrandNew: isBrandNew,
    );
  }

  static String _bodyTextFrom(Map<String, dynamic>? snapshot) {
    final blocks = snapshot?['blocks'] as List<dynamic>?;
    if (blocks == null) return '';
    return blocks
        .map((b) => (b as Map<String, dynamic>)['text'] as String? ?? '')
        .join('\n\n');
  }

  static List<AdminNodeChoice> _choicesFrom(Map<String, dynamic>? snapshot) {
    final raw = snapshot?['choices'] as List<dynamic>?;
    if (raw == null) return const [];
    return raw
        .map((c) => AdminNodeChoice.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  static bool _choiceEquals(AdminNodeChoice a, AdminNodeChoice b) =>
      a.label == b.label && a.nextNodeId == b.nextNodeId;
}
