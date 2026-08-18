/// 선택지 하나 — label + nextNodeId만 갖는 단순한 모양. 이동할 노드는 이번
/// 패스에서는 직접 id를 입력한다(드롭다운 없음, 수동 입력으로 충분).
///
/// 리더 쪽 Choice(lib/reader/shared/models/choice.dart)와 Firestore 문서
/// 모양은 같지만, AdminNodeBlock과 같은 이유로 mutable 편집 세션 전용
/// 클래스를 따로 둔다.
class AdminNodeChoice {
  String label;
  String nextNodeId;

  AdminNodeChoice({this.label = '', this.nextNodeId = ''});

  factory AdminNodeChoice.fromJson(Map<String, dynamic> json) {
    return AdminNodeChoice(
      label: json['label'] as String? ?? '',
      nextNodeId: json['nextNodeId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'nextNodeId': nextNodeId,
      };
}
