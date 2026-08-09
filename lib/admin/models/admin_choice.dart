import 'choice_type.dart';
import 'move_mode.dart';
import 'random_move_candidate.dart';

/// 스토리 노드의 선택지 하나. story_editor_prototype.html의 choice 객체와 동일한
/// 필드 구성을 그대로 따른다 — 타입별로 실제 쓰는 필드만 다르고, 문서 자체는
/// 모든 타입의 필드를 함께 들고 있는 평평한(flat) 구조다(선택지 타입을 바꿔도
/// 이전에 입력해 둔 다른 타입 필드 값이 사라지지 않게 하기 위해서다).
class AdminChoice {
  String text;
  ChoiceType type;

  /// 선택지 전용 이미지. null이면 노드 배경 이미지를 그대로 쓴다.
  String? imageId;

  // --- move ---
  MoveMode mode;

  /// move(고정)/merchant/item 공통으로 쓰는 "이동할 노드" id.
  String target;
  List<RandomMoveCandidate> random;

  // --- battle ---
  String battleId;
  String winNode;
  String loseNode;

  /// battle의 도주 시 이동 노드 / encounter의 탈출 시 이동 노드를 겸한다.
  String escapeNode;

  // --- encounter ---
  String encounterId;

  // --- item ---
  String itemId;
  int itemCount;

  AdminChoice({
    this.text = '새 선택지',
    this.type = ChoiceType.move,
    this.imageId,
    this.mode = MoveMode.fixed,
    this.target = '',
    List<RandomMoveCandidate>? random,
    this.battleId = '',
    this.winNode = '',
    this.loseNode = '',
    this.escapeNode = '',
    this.encounterId = '',
    this.itemId = '',
    this.itemCount = 1,
  }) : random = random ?? [];

  factory AdminChoice.fromJson(Map<String, dynamic> json) {
    return AdminChoice(
      text: json['text'] as String? ?? '',
      type: ChoiceTypeLabel.fromWire(json['type'] as String?),
      imageId: json['imageId'] as String?,
      mode: MoveModeJson.fromWire(json['mode'] as String?),
      target: json['target'] as String? ?? '',
      random: (json['random'] as List<dynamic>?)
              ?.map((e) => RandomMoveCandidate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      battleId: json['battleId'] as String? ?? '',
      winNode: json['winNode'] as String? ?? '',
      loseNode: json['loseNode'] as String? ?? '',
      escapeNode: json['escapeNode'] as String? ?? '',
      encounterId: json['encounterId'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'type': type.wireValue,
        'imageId': imageId,
        'mode': mode.wireValue,
        'target': target,
        'random': random.map((r) => r.toJson()).toList(),
        'battleId': battleId,
        'winNode': winNode,
        'loseNode': loseNode,
        'escapeNode': escapeNode,
        'encounterId': encounterId,
        'itemId': itemId,
        'itemCount': itemCount,
      };
}
