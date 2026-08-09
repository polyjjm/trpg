import 'admin_choice.dart';
import 'node_status.dart';
import 'pending_action.dart';

/// 스토리 노드 문서(storyPacks/{packId}/nodes/{nodeId}) 하나를 편집 세션 동안
/// 들고 있는 로컬 가변(mutable) 모델. story_editor_prototype.html의 node 객체를
/// 그대로 옮긴 것으로, 폼 위젯들이 이 객체의 필드를 직접 mutate하고
/// [dirty] 플래그로 "저장 안 한 변경사항 있음"을 추적한다.
class AdminStoryNode {
  /// Firestore 문서 id. 새 노드는 저장 전까지 임시로 정한 값을 그대로 쓴다.
  String id;

  int day;
  String title;
  String body;
  String? bgImageId;
  List<AdminChoice> choices;

  NodeStatus status;
  PendingAction? pendingAction;

  /// 마지막으로 승인되어 실제 플레이어에게 보이는 콘텐츠 스냅샷
  /// (title/day/body/bgImageId/choices). 한 번도 승인된 적 없으면 null —
  /// 이 값의 null 여부로 "신규 등록"인지 "기존 노드 수정"인지 판단한다.
  Map<String, dynamic>? liveSnapshot;

  /// 로컬 편집 세션에서만 쓰는 플래그. Firestore에는 저장하지 않는다.
  bool dirty;

  AdminStoryNode({
    required this.id,
    this.day = 1,
    this.title = '새 노드',
    this.body = '',
    this.bgImageId,
    List<AdminChoice>? choices,
    this.status = NodeStatus.draft,
    this.pendingAction,
    this.liveSnapshot,
    this.dirty = false,
  }) : choices = choices ?? [];

  /// 이 노드가 Firestore에 한 번도 저장된 적 없는 순수 신규 노드인지.
  bool get isNew => liveSnapshot == null;

  factory AdminStoryNode.fromFirestore(String id, Map<String, dynamic> json) {
    return AdminStoryNode(
      id: id,
      day: (json['day'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      bgImageId: json['bgImageId'] as String?,
      choices: (json['choices'] as List<dynamic>?)
              ?.map((e) => AdminChoice.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      status: NodeStatusJson.fromWire(json['status'] as String?),
      pendingAction: pendingActionFromWire(json['pendingAction'] as String?),
      liveSnapshot: (json['liveSnapshot'] as Map<String, dynamic>?),
    );
  }

  /// Firestore에 그대로 덮어쓸(set) 전체 필드. id는 문서 id라 포함하지 않는다.
  Map<String, dynamic> toFirestoreJson() => {
        'day': day,
        'title': title,
        'body': body,
        'bgImageId': bgImageId,
        'choices': choices.map((c) => c.toJson()).toList(),
        'status': status.wireValue,
        'pendingAction': pendingAction?.wireValue,
        'liveSnapshot': liveSnapshot,
      };

  /// 승인 시 liveSnapshot에 복사해 넣을, 지금 이 순간의 콘텐츠 스냅샷.
  Map<String, dynamic> contentSnapshot() => {
        'title': title,
        'day': day,
        'body': body,
        'bgImageId': bgImageId,
        'choices': choices.map((c) => c.toJson()).toList(),
      };
}
